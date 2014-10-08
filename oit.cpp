
#include <pyarlib/prec.h>
#include <pyarlib/shader.h>
#include <pyarlib/gpu.h>
#include <pyarlib/camera.h>
#include <lfb/lfbL.h>
#include <lfb/lfbLL.h>

#ifndef NO_CUDA
#define NO_CUDA 0
#endif

#if !NO_CUDA
#include "cuda/interface.h"
#endif

#include "oit.h"

static Shader depthOnly("count");
static Shader writeBMAMask("bmaMask");
static Shader debugShader("debug");

OIT::Optimization::Optimization() : parent(NULL), enabled(false)
{
}

OIT::Optimization::Optimization(std::string i, std::string n, OIT* p) : parent(p), enabled(false), id(i), name(n)
{
}

OIT::Optimization::operator const bool&() const
{
	return enabled;
}

OIT::Optimization& OIT::Optimization::operator=(const bool& b)
{
	if (enabled != b)
	{
		enabled = b;
		if (!parent->optimizationSet(id, enabled))
			enabled = !b; //cannot set. revert. NOTE: requires above (enabled != b) check
	}
	return *this;
}

std::string OIT::Optimization::getName()
{
	return name;
}

std::string OIT::Optimization::getID()
{
	return id;
}

OIT::OIT()
{
	colourBuffer = NULL;
	
	indexingTileSize = vec2i(2, 8);
	
	optimizations.push_back(Optimization("PACK", "Pack colour to RGBA8", this));
	optimizations.push_back(Optimization("TILES", "Index by Raster Pattern", this));
	//optimizations.push_back(Optimization("PASS", "No Sorting", this));
	optimizations.push_back(Optimization("BMA", "Backwards Memory Allocation", this));
	optimizations.push_back(Optimization("MERGESORT", "Include Mergesort", this));
	optimizations.push_back(Optimization("REGISTERSORT", "Sort in Registers", this));
	optimizations.push_back(Optimization("BSLMEM", "RBS from lmem", this));
	optimizations.push_back(Optimization("BSGMEM", "RBS from gmem", this));
	optimizations.push_back(Optimization("BSBASE", "BS in lmem", this));
	optimizations.push_back(Optimization("CUDA", "Basic CUDA", this));
	
	//NOTE: this must be before setting any defaults
	for (size_t i = 0; i < optimizations.size(); ++i)
		optimizationIDs[optimizations[i].id] = i;
	
	(*this)["PACK"] = true;
	(*this)["BMA"] = true;
	(*this)["BSLMEM"] = true;
		
	profiler = NULL;
	
	dirtyShaders = true;
	
	shaderComposite = new Shader("oit");
	shaderComposite->name("oit-composite");
	
	shaderSharedSort = new Shader("sharedsort");
	
	sortedOrder = new TextureBuffer(GL_R32I);
}

OIT::~OIT()
{
	shaderComposite->release();
	sortedOrder->release();
	shaderSharedSort->release();
	delete shaderComposite;
	delete sortedOrder;
	delete shaderSharedSort;
	
	for (size_t i = 0; i < bmaIntervals.size(); ++i)
	{
		bmaIntervals[i].shader->release();
		delete bmaIntervals[i].shader;
	}
}

void OIT::setLFBType(LFB::LFBType type)
{
	lfb.setType(type);
	lfb->requireCounts((*this)["BMA"]);
	lfb->profile = profiler;
	dirtyShaders = true;
}

void OIT::setMaxFrags(int frags)
{
	if (frags != lfb->getMaxFrags())
	{
		lfb->setMaxFrags(frags);
		//if ((*this)["BMA"])
		dirtyShaders = true;
	}
}

void OIT::renderToLFB(void (*scene)(Shader*), Shader* shader)
{
	if (profiler) profiler->start("Construct");
	
	//FIXME: potentially slow if changing every frame
	setDefines(shader);
	
	//first pass
	bool fullRender = lfb->begin();
	Shader* firstRender = fullRender ? shader : &depthOnly;
	firstRender->use();
	CHECKERROR;
	lfb->setUniforms(*firstRender, "lfb");
	scene(firstRender);
	firstRender->unuse();
	
	//second pass, if needed
	if (lfb->count())
	{
		CHECKERROR;
		shader->use();
		lfb->setUniforms(*shader, "lfb");
		CHECKERROR;
		scene(shader);
		CHECKERROR;
		shader->unuse();
	}
	lfb->end();
	CHECKERROR;
	
	if (profiler) profiler->time("Construct");
}

void OIT::createBMAMask()
{
	glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
	glEnable(GL_STENCIL_TEST);
	glStencilOp(GL_KEEP, GL_REPLACE, GL_REPLACE);
	
	writeBMAMask.use();
	lfb->setUniforms(writeBMAMask, "lfb");
	for (int i = (int)bmaIntervals.size()-1; i >= 0; --i)
	{
		writeBMAMask.set("interval", bmaIntervals[i].start);
		glStencilFunc(GL_GREATER, 1<<i, 0xFF);
		drawSSQuad();
	}
	writeBMAMask.unuse();
	
	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	glDisable(GL_STENCIL_TEST);
	
	if (profiler) profiler->time("Create Mask");
}

void OIT::compositeWithBMA()
{
	glEnable(GL_STENCIL_TEST);
	glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
	for (int i = (int)bmaIntervals.size()-1; i >= 0; --i)
	{
		glStencilFunc(GL_EQUAL, 1<<i, 0xFF);
		bmaIntervals[i].shader->use();
		lfb->setUniforms(*bmaIntervals[i].shader, "lfb");
		drawSSQuad();
		bmaIntervals[i].shader->unuse();
		if (profiler) profiler->time("BMA" + intToString(i));
	}
	glDisable(GL_STENCIL_TEST);
}

void OIT::compositeFromLFB()
{
	//other profiler->time() may be set inbetween. start "composite" timing from the previous time() call
	if (profiler) profiler->start("Composite");
	
	glClearColor(1,1,1,1);
	glClear(GL_COLOR_BUFFER_BIT);
	
	if ((*this)["CUDA"])
	{
		#if !NO_CUDA
		static OIT_CUDA* oitCUDA = NULL;
		if (!oitCUDA)
			oitCUDA = getOIT_CUDA();
		
		colourBuffer->resize(lfb->getTotalPixels() * 4);
		
		oitCUDA->mergesort = (*this)["MERGESORT"];
		oitCUDA->registersort = (*this)["BSLMEM"];
		oitCUDA->sortAndComposite(&lfb, colourBuffer);
		
		CHECKERROR;
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, *colourBuffer);
		CHECKERROR;
		glWindowPos2i(0, 0);
		CHECKERROR;
		glDrawPixels(lfb->getSize().x, lfb->getSize().y, GL_RGBA, GL_UNSIGNED_BYTE, 0);
		CHECKERROR;
		glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
		CHECKERROR;
		#endif
	}
	else if ((*this)["BMA"])
	{
		glClear(GL_STENCIL_BUFFER_BIT);
		createBMAMask();
		compositeWithBMA();
	}
	else
	{
		//render OIT
		if (!shaderComposite->use())
			return;
		lfb->setUniforms(*shaderComposite, "lfb");
		drawSSQuad();
		shaderComposite->unuse();
	}
	
	if (profiler) profiler->time("Composite");
}

void OIT::setDefines(Shader* shader)
{
	std::string tileDim = format("%i,%i",indexingTileSize.x,indexingTileSize.y);
	shader->define("INDEX_WITH_TILES", (*this)["TILES"]);
	shader->define("INDEX_TILE_SIZE", tileDim);
	shader->define("INCLUDE_MERGESORT", (*this)["MERGESORT"]);
	shader->define("SORT_IN_REGISTERS", (*this)["REGISTERSORT"]);
	
	bool blockSort = (*this)["BSLMEM"] || (*this)["BSGMEM"] || (*this)["BSBASE"];
	shader->define("SORT_IN_BOTH", blockSort);
	shader->define("BLOCKSORT_LMEM", (*this)["BSLMEM"]);
	shader->define("BLOCKSORT_GMEM", (*this)["BSGMEM"]);
	shader->define("BLOCKSORT_BASE", (*this)["BSBASE"]);
	shader->define("COMPOSITE_ONLY", (*this)["PASS"]);
	
	lfb->setDefines(*shader);
}
	
void OIT::updateShaders()
{
	printf("====== Updating Shaders ======\n");

	dirtyShaders = false;

	//update BMA shaders
	int maxBMAInterval = 0;
	if ((*this)["BMA"])
		maxBMAInterval = 1 << ceilLog2(lfb->getMaxFrags());
	int prev = 0;
	int i = 0;
	
	std::vector<int> splits;
	
	#if 1
	for (int interval = 8; interval <= maxBMAInterval; interval *= 2)
		splits.push_back(interval);
	#else
	for (int interval = 8; interval <= maxBMAInterval; interval += 8)
		splits.push_back(interval);
	#endif
		
	//splits.push_back(192);
	
	std::sort(splits.begin(), splits.end());
	
	for (size_t j = 0; j < splits.size(); ++j)
	{
		int intervalEnd = splits[j];
		if (i >= (int)bmaIntervals.size())
			bmaIntervals.push_back(BMA());
		bmaIntervals[i].start = prev;
		bmaIntervals[i].end = intervalEnd;
		if (!bmaIntervals[i].shader)
			bmaIntervals[i].shader = new Shader("oit");
		bmaIntervals[i].shader->name("oit-bma" + intToString(intervalEnd));
		bmaIntervals[i].shader->define("MAX_FRAGS_OVERRIDE", intervalEnd);
		prev = intervalEnd;
		++i;
	}
	int intervalsNeeded = i;
	while (i < (int)bmaIntervals.size())
	{
		bmaIntervals[i].shader->release();
		delete bmaIntervals[i].shader;
		++i;
	}
	bmaIntervals.resize(intervalsNeeded);
	
	//update defines
	for (size_t j = 0; j < bmaIntervals.size(); ++j)
		setDefines(bmaIntervals[j].shader);
	setDefines(shaderComposite);
	setDefines(shaderSharedSort);
	setDefines(&writeBMAMask);
	setDefines(&depthOnly);
	
	printf("Shaders Updated\n");
		
	#if 1
	shaderComposite->reload();
	std::ofstream ofile("shader.bin", std::ios::binary);
	std::string b = shaderComposite->getBinary();
	for (size_t j = 0; j < b.size(); ++j)
		if ((b[j] < 32 && b[j] != 10) || b[j] > 126)
			b[j] = '#';
	ofile << b;
	ofile.flush();
	#endif
}

bool OIT::optimizationSet(const std::string& id, bool enabled)
{
	printf("%s: %s\n", (*this)[id].getName().c_str(), enabled?"enabled":"disabled");
	
	if (enabled)
	{
		//check for conflicts. call optimizationSet(id, false) to resolve
		
		//apply any initialization
		if (id == "TILES")
			lfb->setPack(indexingTileSize);
	}
	else
	{
		//deinitialization
		if (id == "TILES")
			lfb->setPack(vec2i(1, 1));
	}
	
	lfb->setFormat((*this)["PACK"] ? GL_RG32F : GL_RGBA32F);
	
	lfb->requireCounts((*this)["BMA"]);
	
	if ((*this)["CUDA"])
	{
		if (!colourBuffer)
			colourBuffer = new TextureBuffer(GL_RGBA8);
	}
	else
	{
		if (colourBuffer)
		{
			colourBuffer->release();
			delete colourBuffer;
			colourBuffer = NULL;
		}
	}
	
	dirtyShaders = true;
	return true;
}

void OIT::draw(void (*scene)(Shader*), Shader* shader)
{
	if (shader->error() || shaderComposite->error())
		return;

	vec4i vp;
	glGetIntegerv(GL_VIEWPORT, (GLint*)&vp);
	if (lfb->resize(vp.zw()))
		dirtyShaders = true;
	
	if (dirtyShaders)
		updateShaders();
	
	renderToLFB(scene, shader);
	
	glDisable(GL_DEPTH_TEST);
	compositeFromLFB();
}

OIT::Optimization& OIT::operator[](int i)
{
	if (i < 0 || i > (int)optimizations.size())
	{
		static OIT::Optimization notfound;
		return notfound;
	}
	return optimizations[i];
}

OIT::Optimization& OIT::operator[](const std::string& i)
{
	if (optimizationIDs.find(i) == optimizationIDs.end())
	{
		static OIT::Optimization notfound;
		return notfound;
	}
	return this->operator[](optimizationIDs[i]);
}

int OIT::getMaxFrags()
{
	return lfb->getMaxFrags();
}

int OIT::getTotalFragments()
{
	return lfb->getTotalFragments();
}

int OIT::numOptimizations()
{
	return (int)optimizations.size();
}

std::string OIT::info()
{
	return lfb->getMemoryInfo();
}

void OIT::setProfiler(Profiler* p)
{
	profiler = p;
	lfb->profile = profiler;
}

bool OIT::getDepthHistogram(std::vector<unsigned int>& histogram)
{
	return lfb->getDepthHistogram(histogram);
}

void OIT::drawDebug(Camera* source, Camera* view)
{
	glDisable(GL_CULL_FACE);
	glEnable(GL_DEPTH_TEST);
	glDisable(GL_BLEND);
	mat44 projection = view->getProjection() * view->getInverse() * source->getTransform() * source->getProjectionInv();
	setDefines(&debugShader);
	debugShader.use();
	lfb->setUniforms(debugShader, "lfb");
	debugShader.set("projectionMat", projection);
	for (int i = 0; i < getMaxFrags(); i += 10)
	{
		debugShader.set("batch", i);
		glDrawArrays(GL_POINTS, 0, lfb->getSize().x * lfb->getSize().y);
	}
	debugShader.unuse();
}




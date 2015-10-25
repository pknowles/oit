
#include <pyarlib/prec.h>
#include <pyarlib/shader.h>
#include <pyarlib/gpu.h>
#include <pyarlib/camera.h>
#include <lfb/lfbCL.h>
#include <lfb/lfbL.h>
#include <lfb/lfbLL.h>

#ifndef NO_CUDA
#define NO_CUDA 0
#endif

#if !NO_CUDA
#include "cuda/interface.h"
#endif

#include "oit.h"

#ifndef glDispatchCompute
#ifdef __cplusplus
extern "C" {
#endif
#ifndef APIENTRY
#define APIENTRY
#endif
#ifndef APIENTRYP
#define APIENTRYP APIENTRY *
#endif
#ifndef GLAPI
#define GLAPI extern
#endif
#define GL_MAX_COMPUTE_WORK_GROUP_COUNT 0x91BE
GLAPI void APIENTRY glDispatchCompute (GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z);
GLAPI void APIENTRY glDispatchComputeIndirect (GLintptr indirect);
typedef void (APIENTRYP PFNGLDISPATCHCOMPUTEPROC) (GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z);
typedef void (APIENTRYP PFNGLDISPATCHCOMPUTEINDIRECTPROC) (GLintptr indirect);
#ifdef __cplusplus
}
#endif
#endif


static Shader depthOnly("count");
static Shader writeBMAMask("bmaMask");
static Shader debugShader("debug");
static Shader patternRecord("pattern");

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
			enabled = !b; //revert. NOTE: requires above (enabled != b) check
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
	
	presortTileSize = vec2i(16, 16);
	indexingTileSize = vec2i(2, 8);
	
	optimizations.push_back(Optimization("BINDLESS", "Bindless Graphics", this));
	optimizations.push_back(Optimization("PACK", "Pack colour to RGBA8", this));
	optimizations.push_back(Optimization("TILES", "Index by Raster Pattern", this));
	optimizations.push_back(Optimization("PASS", "No Sorting", this));
	optimizations.push_back(Optimization("BMA", "Backwards Memory Allocation", this));
	optimizations.push_back(Optimization("PRESORT", "Attempt Sort Reuse", this));
	optimizations.push_back(Optimization("MERGESORT", "Include Mergesort", this));
	optimizations.push_back(Optimization("REGISTERSORT", "Sort in Registers", this));
	optimizations.push_back(Optimization("BSLMEM", "RBS from lmem", this));
	optimizations.push_back(Optimization("BSGMEM", "RBS from gmem", this));
	optimizations.push_back(Optimization("BSBASE", "BS in lmem", this)); //same as RBS, but without fancy unrolling and registers
	optimizations.push_back(Optimization("CUDA", "Basic CUDA", this));
	optimizations.push_back(Optimization("NONE", "No LFB", this));
	//optimizations.push_back(Optimization("SHAREDSORT", "Shared Sort Test", this));
	
	//STUPID PYAR!!! This comes FIRST!!!
	for (size_t i = 0; i < optimizations.size(); ++i)
		optimizationIDs[optimizations[i].id] = (int)i;
	
	(*this)["PACK"] = true;
		
	profiler = NULL;
	
	dirtyShaders = true;
	
	shaderPresort = new Shader("oit");
	shaderPresort->name("oit-presort");
	shaderPresort->define("PRESORT_SORT", 1);
	
	shaderReuse = new Shader("oit");
	shaderReuse->name("oit-reuse");
	shaderReuse->define("PRESORT_REUSE", 1);
	
	shaderComposite = new Shader("oit");
	shaderComposite->name("oit-composite");
	
	shaderSharedSort = new Shader("sharedsort");
	
	sortedOrder = new TextureBuffer(GL_R32I);
}

OIT::~OIT()
{
	shaderPresort->release();
	shaderReuse->release();
	shaderComposite->release();
	sortedOrder->release();
	shaderSharedSort->release();
	delete shaderPresort;
	delete shaderReuse;
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
	lfb->requireCounts((*this)["BMA"] || (*this)["PRESORT"]);
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
	bool direct = (*this)["NONE"];
	if (profiler) profiler->start("Construct");
	
	//FIXME: potentially slow if changing every frame
	setDefines(shader);
	
	//first pass
	bool fullRender = direct || lfb->begin();
	Shader* firstRender = fullRender ? shader : &depthOnly;
	firstRender->use();
	CHECKERROR;
	lfb->setUniforms(*firstRender, "lfb");
	scene(firstRender);
	firstRender->unuse();
	
	//second pass, if needed
	if (!direct && lfb->count())
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
	else if ((*this)["PRESORT"])
	{
		vec2i presortTileCount = lfb->getSize() / presortTileSize;
		
		//FIXME: maybe pack this?
		sortedOrder->resize(presortTileCount.x * presortTileCount.y * sizeof(unsigned int) * lfb->getMaxFrags());
	
		if (!shaderPresort->use())
			return;
		lfb->setUniforms(*shaderPresort, "lfb");
		shaderPresort->set("sortedOrder", *sortedOrder);
		shaderPresort->set("presortTileSize", presortTileSize);
		shaderPresort->set("presortTiles", presortTileCount);
		drawSSQuad(presortTileCount);
		shaderPresort->unuse();
		
		if (profiler) profiler->time("Presort");
		
		glClear(GL_STENCIL_BUFFER_BIT);
		glEnable(GL_STENCIL_TEST);
		glStencilFunc(GL_ALWAYS, 1<<7, 1<<7);
		glStencilOp(GL_REPLACE, GL_REPLACE, GL_REPLACE);
		if (!shaderReuse->use())
			return;
		lfb->setUniforms(*shaderReuse, "lfb");
		shaderReuse->set("sortedOrder", *sortedOrder);
		shaderReuse->set("presortTileSize", presortTileSize);
		shaderReuse->set("presortTiles", presortTileCount);
		drawSSQuad();
		shaderReuse->unuse();
		
		if (profiler) profiler->time("Reuse");
		
		if (profiler) profiler->start("Fix");
		
		if ((*this)["BMA"])
		{
			createBMAMask();
			compositeWithBMA();
		}
		else
		{
			glStencilFunc(GL_NOTEQUAL, 1<<7, 1<<7);
			glStencilOp(GL_KEEP, GL_REPLACE, GL_REPLACE);
			//render OIT
			if (!shaderComposite->use())
				return;
			lfb->setUniforms(*shaderComposite, "lfb");
			drawSSQuad();
			shaderComposite->unuse();
		}
		glDisable(GL_STENCIL_TEST);
		
		if (profiler) profiler->time("Fix");
	}
	else if ((*this)["BMA"])
	{
		glClear(GL_STENCIL_BUFFER_BIT);
		createBMAMask();
		compositeWithBMA();
	}
	else
	{
		if ((*this)["SHAREDSORT"])
		{
			shaderSharedSort->use();
			shaderSharedSort->set("totalPixels", (int)lfb->getTotalPixels());
			lfb->setUniforms(*shaderSharedSort, "lfb");
			int i = 65000;
			//glGetIntegerv(GL_MAX_COMPUTE_WORK_GROUP_COUNT, &i);
			//glDispatchCompute(mymin(i, ceil(lfb->getTotalPixels(),8)), 1, 1);
			CHECKERROR;
			shaderSharedSort->unuse();
			if (profiler) profiler->time("Shared Sort");
		}
		
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
	shader->define("DIRECT_RENDER", (*this)["NONE"]);
	
	lfb->setDefines(*shader);
}
	
void OIT::updateShaders()
{
	printf("====== Updating Shaders ======\n");
	fflush(stdout);

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
	for (size_t i = 0; i < bmaIntervals.size(); ++i)
		setDefines(bmaIntervals[i].shader);
	setDefines(shaderPresort);
	setDefines(shaderReuse);
	setDefines(shaderComposite);
	setDefines(shaderSharedSort);
	setDefines(&writeBMAMask);
	setDefines(&depthOnly);
	
	printf("Shaders Updated\n");
		
	#if 0
	shaderComposite->reload();
	std::ofstream ofile("shader.bin", std::ios::binary);
	std::string b = shaderComposite->getBinary();
	for (size_t i = 0; i < b.size(); ++i)
		if ((b[i] < 32 && b[i] != 10) || b[i] > 126)
			b[i] = '#';
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
			
		if (id == "PRESORT")
			sortedOrder->release();
	}
	
	lfb->useBindlessGraphics((*this)["BINDLESS"]);
	
	lfb->setFormat((*this)["PACK"] ? GL_RG32F : GL_RGBA32F);
	
	lfb->requireCounts((*this)["BMA"] || (*this)["PRESORT"]);
	
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
	bool direct = (*this)["NONE"];
	CHECKERROR;

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
	if (!direct)
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

size_t OIT::getTotalFragments()
{
	return lfb->getTotalFragments();
}

size_t OIT::getMemoryUsage()
{
	return lfb->getMemoryUsage();
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
	setDefines(&debugShader);
	debugShader.use();
	lfb->setUniforms(debugShader, "lfb");
	debugShader.set("reprojectMat", view->getProjection() * view->getInverse() * source->getTransform() * source->getProjectionInv());
	debugShader.set("sourceProjectionInv", source->getProjectionInv());
	debugShader.set("sourceCameraToClip", view->getProjection() * view->getInverse() * source->getTransform());
	for (int i = 0; i < getMaxFrags(); i += 10)
	{
		debugShader.set("batch", i);
		glDrawArrays(GL_POINTS, 0, lfb->getSize().x * lfb->getSize().y);
	}
	debugShader.unuse();
}

const LFBBase* OIT::getLFB()
{
	return (LFBBase*)lfb;
}

std::vector<vec2i> OIT::computeRasterPattern()
{
	std::vector<vec2i> pattern;

	vec4i vp;
	int layers = 4;
	glGetIntegerv(GL_VIEWPORT, (GLint*)&vp);
	
	TextureBuffer positions(GL_RG32UI);
	positions.resize(sizeof(vec2i) * vp.z * vp.w * layers);
	
	TextureBuffer counter;
	counter.resize(sizeof(unsigned int));
	*(unsigned int*)counter.map() = 0;
	counter.unmap();
	
	glBindBufferBase(GL_ATOMIC_COUNTER_BUFFER, 0, counter);
	
	patternRecord.use();
	patternRecord.set("positions", positions);
	drawSSQuad(vec3i(vp.z, vp.w, layers));
	patternRecord.unuse();
	
	typedef std::basic_string<unsigned int> BigStr;
	std::map<BigStr, int> freq;
	
	unsigned int c = *(unsigned int*)counter.map();
	counter.unmap();
	vec2i* p = (vec2i*)positions.map();
	vec2i last = p[0];
	BigStr str;
	for (unsigned int i = 1; i < c; ++i)
	{
		vec2i d = p[i] - last;
		last = p[i];
		if (myabs(d.x) > 32 || myabs(d.y) > 32)
		{
			str.clear();
			continue;
		}
		
		unsigned short x = d.x+127;
		unsigned short y = d.y+127;
		unsigned int e = x | (y << 16);
		str += e;
		
		if (str.size() > 32)
		{
			for (size_t j = 0; j < str.size()-32; ++j)
			{
				BigStr sub = str.substr(j);
				if (freq.find(sub) == freq.end())
					freq[sub] = 1;
				else
					++freq[sub];
			}
		}
		
		if (str.size() > 256)
			str.clear();
	}
	positions.unmap();
	
	int maxFreq = 0;
	for (std::map<BigStr, int>::iterator it = freq.begin(); it != freq.end(); ++it)
		maxFreq = mymax(maxFreq, it->second);
	
	BigStr maxLen;
	for (std::map<BigStr, int>::iterator it = freq.begin(); it != freq.end(); ++it)
	{
		if (it->second == maxFreq && it->first.size() > maxLen.size())
			maxLen = it->first;
	}
	
	for (size_t i = 0; i < maxLen.size(); ++i)
	{
		unsigned short x = maxLen[i] & 0xFFFF;
		unsigned short y = (maxLen[i] >> 16) & 0xFFFF;
		pattern.push_back(vec2i(x-127, y-127));
	}
	
	positions.release();
	counter.release();
	return pattern;
}




/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */

/*
Visual studio *spit* *spit* *spit* steps:
1. Add entire pyarlib directory to a pyarlib library project or your main executable
2. Add resources.rc to your main executable
3. Include these libraries (project properties->linker->input->additional dependecies):
	glew32.lib;freetype248.lib;SDL2.lib;libpng.lib;zlib.lib;opengl32.lib;glu32.lib
4. Some files (currently just "pyarlib/mesh/simpleobj/obj.c") need to be compiled as C++
	project properties->C++->advanced->compile as
5. Build (this file, template.txt, is an example main.cpp file)
	the following include might need " quotes and a local path instead
*/

#include <pyarlib/pyarlib.h>
#include <pyarlib/benchmark.h>
#include <pyarlib/scene.h>

#ifndef _WIN32
#include <unistd.h>
#endif

#include <signal.h>

#include "oit.h"

using namespace pyarlib;

Jeltz jeltz("Jeltz");
JeltzFly fly;
JeltzGUI gui;
Scene scene;

Benchmark benchmark;

Profiler profiler;

VBOMesh quads;
VBOMesh dragon;

QG::DropSelect lfbType("LFB Type");
QG::DropDown oitOptimize("Optimization");
QG::Widget infoPanel;
QG::Slider maxFragsSlider("Max Frags", 0, 6);
QG::Slider viewSlider("View", 0, 1);
QG::Label status("<status>");
QG::Slider alpha("Alpha", 0, 1, true);

Shader phong("phong");

FrameBuffer rtt;

OIT oit;
	
const char* sceneFiles[] = {
	"scenes/dragon.xml",
	"scenes/atrium.xml",
	"scenes/powerplant.xml",
	"scenes/hairball.xml",
	"scenes/tree.xml",
	"scenes/planes2.xml",
	};

bool directionalLight = true;

static Camera debugView;
bool usingDebugCamera = false;

void (*currentScene)(Shader*) = NULL;

void drawQuads(Shader* shader);
void drawScene(Shader* shader);

void selectType()
{
	switch (lfbType.selected)
	{
	case 0: oit.setLFBType(LFB::LFB_TYPE_LL); break;
	case 1: oit.setLFBType(LFB::LFB_TYPE_L); break;
	case 2: oit.setLFBType(LFB::LFB_TYPE_CL); break;
	case 3: oit.setLFBType(LFB::LFB_TYPE_B); break;
	}
}

void toggleOptimize()
{
	for (int i = 0; i < oitOptimize.size(); ++i)
	{
		oit[i] = ((QG::CheckBox*)oitOptimize[i])->b;
	}
}

void changeMaxFrags()
{
	int maxFrags = 8 << maxFragsSlider.i;
	oit.setMaxFrags(maxFrags);
	
	maxFragsSlider.textf("Max Frags: %i", maxFrags);
}

void changeView()
{
	int view = viewSlider.i;
	if (scene.getNumViews() > view)
	{
		scene.setView(view);
		std::string viewname = scene.getViewName(view);
		viewSlider.text = "View: " + viewname;
		if (benchmark.running)
			benchmark.currentTest()->overrideOutput("view", viewname);
	}
	else
	{
		printf("\n\n\n########## ERROR: MISSING VIEW (%s) ##########\n\n\n", scene.getName().c_str());
	}
}

void changeScene(std::string sceneFile)
{
	scene.load(sceneFile);
	viewSlider.upper = mymax(0, scene.getNumViews() - 1);
	viewSlider.i = (int)benchmark.get("view", 0);
	changeView();
}

void reshape(vec2i size)
{
	//if (rtt.resize(size >> 5))      //// ############# LOW REZ DEBUG VIEW HERE
	//if (rtt.resize(size << 1))
	if (rtt.resize(size))
		rtt.attach();
	debugView.setAspectRatio(size.x / (float)size.y);
	debugView.regenProjection();
	if (size != jeltz.winSize())
		printf("Note: render size does not match window.\n");
}

void updateBenchmark()
{
	//change scene if needed
	std::string sceneName = benchmark.getStr("scene");
	if (sceneName.size())
		changeScene("scenes/" + sceneName + ".xml");
	else if (benchmark.running)
		printf("\n\n\n########## ERROR: INVALID SCENE NAME (%s) ##########\n\n\n", sceneName.c_str());
	benchmark.ignoreNextUpdate();
	
	//set resolution
	int resx = (int)benchmark.get("resx", 0);
	int resy = (int)benchmark.get("resy", 0);
	if (resx > 0 && resy > 0)
		reshape(vec2i(resx, resy));
	if (benchmark.running)
		benchmark.currentTest()->overrideOutput("pixels", rtt.size.x * rtt.size.y);
	
	//change lfb type
	std::string lfbTypeStr = benchmark.getStr("lfb");
	bool setType = true;
	if (lfbTypeStr == "ll") lfbType.selected = 0;
	else if (lfbTypeStr == "l") lfbType.selected = 1;
	else if (lfbTypeStr == "cl") lfbType.selected = 2;
	else if (lfbTypeStr == "b") lfbType.selected = 3;
	else setType = false;
	if (setType)
		selectType();
	
	//set max frags
	maxFragsSlider.i = ilog2((stringToInt(benchmark.getStr("max")))/8);
	changeMaxFrags();

	//set optimizations
	if (benchmark.running)
	{
		for (int i = 0; i < oit.numOptimizations(); ++i)
		{
			cout << oit[i].getID() << " " << (int)benchmark.get(oit[i].getID()) << endl;
			((QG::CheckBox*)oitOptimize[i])->b = ((int)benchmark.get(oit[i].getID()) == 1);
			((QG::CheckBox*)oitOptimize[i])->setDirty();
			oit[i] = ((QG::CheckBox*)oitOptimize[i])->b;
		}
	}
	
	static bool wasRunning = false;
	if (benchmark.running)
		wasRunning = true;
	if (!benchmark.running && wasRunning)
		jeltz.quit();
	
/*
	if (benchmark.running)
		currentScene = drawQuads;
	else
	{
		currentScene = drawScene;
		if (rtt.resize(jeltz.winSize()))
			rtt.attach();
	}
	
	if (benchmark.running)
	{
		for (int i = 0; i < oit.numOptimizations(); ++i)
		{
			((QG::CheckBox*)oitOptimize[i])->b = (benchmark.get(oit[i].getID()) == 1);
			((QG::CheckBox*)oitOptimize[i])->setDirty();
			oit[i] = ((QG::CheckBox*)oitOptimize[i])->b;
		}
		
		int numPixels = benchmark["numPixels"];
		vec2i res;
		res.x = ceilSqrt(numPixels);
		res.y = ceil(numPixels, res.x);
		//printf("%i %i\n", res.x, res.y);
		if (rtt.resize(res))
			rtt.attach();
		
		if (benchmark.currentTest())
		{
			benchmark.currentTest()->overrideOutput("numPixels", res.x * res.y);
			benchmark.currentTest()->overrideOutput("numFragments", oit.getTotalFragments());
		}

		int lfbIndex = benchmark["LFB"];
		((QG::RadioButton*)lfbType[lfbIndex])->set();
	}
	
	int numQuads = benchmark["numPolygons"] / 2;
	int numLayers = mymax(1, benchmark["numLayers"]);
	vec2i grid(1);
	if (numQuads > 0)
	{
		grid.x = isqrt(ceil(numQuads, numLayers));
		grid.y = ceil(numQuads, numLayers) / grid.x;
	}
	printf("Grid %i %i %i %i==%i\n", grid.x, grid.y, numLayers, grid.x*grid.y*numLayers, numQuads);
	quads.release();
	quads = VBOMesh::grid(grid, VBOMesh::paramPlane);
	quads.setMaterial(new Material("../../images/tigre.png"));
*/
}

#include <ostream>
#include <istream>
using namespace std;

void update(float dt)
{
/*
	static bool running = false;
	static ofstream ofile("frames-fast.txt");
	static float rot = 0.0f;
	if (jeltz.buttonDown("z"))
	{
		running = true;
	}
	if (running)
	{
		rot += dt*0.4;
		fly.camera.rotate(vec2f(0, dt*0.4));
		fly.camera.regen();
		ofile << dt << endl;
		if (rot > 2.0f * pi)
		{
			ofile.close();
			jeltz.quit();
		}
	}
	*/
	
	if (jeltz.buttonDown("g"))
	{
		std::swap(fly.camera, debugView);
		usingDebugCamera = !usingDebugCamera;
	}
	
	if (jeltz.buttonDown("`"))
	{
		gui.visible = !gui.visible;
		gui.fps.print = !gui.visible;
	}
	
	if (jeltz.buttonDown("q"))
	{
		static bool editMode = false;
		editMode = !editMode;
		scene.edit(editMode);
	}
	
	if (jeltz.buttonDown("l"))
		directionalLight = !directionalLight;
		
	for (int i = 0; i < (int)(sizeof(sceneFiles)/sizeof(char*)); ++i)
		if (jeltz.buttonDown(intToString(i+1).c_str())) changeScene(sceneFiles[i]);
	
	if (jeltz.resized() && !benchmark.running)
	{
		reshape(jeltz.winSize());
	}
	
	static float reloadTimer = 0.0f;
	reloadTimer -= dt;
	if (reloadTimer < 0.0f)
	{
		std::string statusStr;
		statusStr += oit.info();
		statusStr += profiler.toString();
		statusStr += "Frags: " + humanNumber(oit.getTotalFragments()) + "\n";
		statusStr += format("Benchmark ETA: %.2fm\n", benchmark.expectedTimeToCompletion()/60.0f);
		status = statusStr;
	
		reloadTimer = 1.0f;
		if (Shader::reloadModified())
			jeltz.postUnfocusedRedisplay();
	}
	
	if (jeltz.buttonDown("h"))
	{
		std::vector<unsigned int> h;
		if (oit.getDepthHistogram(h))
		{
			std::ofstream hfile("hist.csv");
			for (size_t i = 0; i < h.size(); ++i)
				hfile << i << "," << h[i] << std::endl;
			hfile.close();
			printf("Max DC: %i\n", (int)(h.size()-1));
			printf("Frags: %i\n", oit.getTotalFragments());
		}
		else
			printf("ERROR: No counts for histogram\n");
	}
	
	if (jeltz.buttonDown("b"))
	{
		jeltz.removeBorder();
		std::string vendor((const char*)glGetString(GL_VENDOR));
		std::string renderer((const char*)glGetString(GL_RENDERER));
		std::string version((const char*)glGetString(GL_VERSION));
		benchmark.setDefault("device", renderer + " GL" + version);
		benchmark.start();
	}
	benchmark.update(dt);
	
	if (benchmark.running)
	{
		benchmark.currentTest()->overrideOutput("memory_mb", (int)(oit.getMemoryUsage()));
		benchmark.currentTest()->overrideOutput("tmemory_mb", (int)(getGPUMemoryUsage()));
	}
	
	if (jeltz.buttonDown("F3"))
		jeltz.removeBorder(!jeltz.getBorderless());
		
	if (jeltz.buttonDown("p"))
		oit.getLFB()->save("oit.lfb");
}

void drawQuads(Shader* shader)
{
	int numLayers = (int)benchmark["numLayers"];
	
	//glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
	
	shader->set("lightPos", vec4f(0.5,0.5,2,1));
	shader->set("colourIn", vec4f(1));
	shader->set("colourMod", vec4f(1,0,0,1.0/(numLayers+1)));
	shader->set("projectionMat", mat44::scale(2.0f) * mat44::translate(-0.5f, -0.5f, -0.5f));
	shader->set("normalMat", mat33(mat44::identity()));
	for (int i = 0; i < numLayers; ++i)
	{
		float x = ((i+1) / (float)numLayers) * ((i%2==0)?1.0f:-1.0f);
		shader->set("modelviewMat", mat44::translate(0.0, 0.0, x*0.5+0.5));
		quads.draw();
		CHECKERROR;
	}
	
	//drawSSQuad();
	//glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

void drawScene(Shader* shader)
{
	fly.uploadCamera(shader);
	//glEnable(GL_CULL_FACE);
	
	if (directionalLight)
		shader->set("lightPos", vec4f(0,0,0,1));
	else
		shader->set("lightPos", fly.camera.getInverse() * vec4f(0,2,1,1));
	shader->set("colourIn", vec4f(1));
	
	for (int i = 0; i < 0; ++i)
	{
		shader->set("colourMod", vec4f(1,1,1,1.0/(i+1)));
	
		shader->set("modelviewMat", fly.camera.getInverse() * mat44::translate(0,0,i/20.0));
		shader->set("normalMat", mat33((fly.camera.getInverse() * mat44::translate(0,0,i)).inverse().transpose()));
		dragon.draw();
	}
	
	if (!usingDebugCamera)
		scene.setCamera(&fly.camera);
	else
		scene.setCamera(&debugView);
	shader->set("colourMod", vec4f(1, 1, 1, alpha.f));
	scene.draw(shader);
	
	//glDisable(GL_CULL_FACE);
}

void drawProjection(Camera& cam)
{
	glMultMatrixf((cam.getTransform() * cam.getProjectionInv()).m);
	glColor3f(0, 0, 0);
	glBegin(GL_LINES);
	glVertex3f(-1,-1,-1); glVertex3f(1,-1,-1);
	glVertex3f(-1,-1,1); glVertex3f(1,-1,1);
	glVertex3f(-1,1,-1); glVertex3f(1,1,-1);
	glVertex3f(-1,1,1); glVertex3f(1,1,1);
	glVertex3f(-1,1,1); glVertex3f(1,1,1);
	glVertex3f(-1,-1,-1); glVertex3f(-1,1,-1);
	glVertex3f(-1,-1,1); glVertex3f(-1,1,1);
	glVertex3f(1,-1,-1); glVertex3f(1,1,-1);
	glVertex3f(1,-1,1); glVertex3f(1,1,1);
	glVertex3f(-1,-1,-1); glVertex3f(-1,-1,1);
	glVertex3f(-1,1,-1); glVertex3f(-1,1,1);
	glVertex3f(1,-1,-1); glVertex3f(1,-1,1);
	glVertex3f(1,1,-1); glVertex3f(1,1,1);
	glEnd();
}

void display()
{
	static bool running = false;
	static ifstream ifile;
	static float rot = 0.0f;
	static bool done = true;
	if (done)
		running = false;
	if (jeltz.buttonDown("z"))
	{
		ifile.open("frames.txt");
		running = true;
		done = false;
	}
	if (running)
	{
		fly.camera.rotate(vec2f(0, rot*0.4));
		fly.camera.regen();
		if (!(ifile >> rot))
			done = true;
	}
	
	
	profiler.begin();
	
	rtt.bind();
	glDisable(GL_DEPTH_TEST);
	glDisable(GL_CULL_FACE);
	glClear(GL_COLOR_BUFFER_BIT);
	if (currentScene)
		oit.draw(currentScene, &phong);
	rtt.unbind();
	
	if (jeltz.buttonDown("f"))
	{
		debugView = fly.camera;
		
		Camera& sceneView = usingDebugCamera ? debugView : fly.camera;
		Camera& visView = usingDebugCamera ? fly.camera : debugView;
		
		visView.setDistance(0.1f, 200.0f);
		visView.setPerspective(90.0f * pi / 180.0f);
		//visView.setOrthographic(32.0f);
		visView.regen();
		
		sceneView.setDistance(2.0f, 20.0f);
		sceneView.setPerspective(40.0f * pi / 180.0f);
		//sceneView.setDistance(2.0f, 8.0f);
		//sceneView.setOrthographic(12.0f);
		sceneView.regen();
	}
	if (usingDebugCamera)
	{
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		oit.drawDebug(&debugView, &fly.camera);
		glMatrixMode(GL_PROJECTION);
		glLoadMatrixf(fly.camera.getProjection().m);
		glMatrixMode(GL_MODELVIEW);
		glLoadMatrixf(fly.camera.getInverse().m);
		drawProjection(debugView);
	}
	else
		rtt.blit(0, false, vec2i(0), jeltz.winSize());
	
	if (running)
	{
		static int f = 0;
		std::string outName = "anim/frame" + intToString(f++, 4) + ".png";
		QI::ImagePNG out;
		out.readTexture(*rtt.colour[0]);
		out.saveImage(outName);
	}
	
	#if 0
	glClear(GL_DEPTH_BUFFER_BIT);
	fly.uploadCamera();
	glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
	dragon.draw();
	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	
	glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(1.0, 2);
	glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
	dragon.draw();
	glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
	glDisable(GL_POLYGON_OFFSET_FILL);
	#endif
}


/*
static void hdl (int sig, siginfo_t *siginfo, void *context)
{
	printf ("Sending PID: %ld, UID: %ld\n",
			(long)siginfo->si_pid, (long)siginfo->si_uid);
}
#include <dlfcn.h>
#include "cuda/interface.h"

Shader s("s");
*/

int main(int argc, char* argv[])
{
/*
	void* lib = dlopen("cuda/liboitcuda.so", RTLD_NOW);
	printf("%p\n", lib);
	getOIT_CUDA_FPTR get = (getOIT_CUDA_FPTR)dlsym(lib, "getOIT_CUDA");
	printf("%p\n", get);
	OIT_CUDA* qwe = get();
*/

	jeltz.setUpdate(update);
	jeltz.setDisplay(display);
	jeltz.add(&scene);
	jeltz.add(&gui);
	jeltz.add(&fly);
	jeltz.init();
	jeltz.resize(640, 480);
	
	#if 0
	s.reload();
	std::cout << s.getBinary() << std::endl;
	return 0;
	#endif
	
	VBOMeshOBJ::registerLoader();
	VBOMesh3DS::registerLoader();
	VBOMeshCTM::registerLoader();
	VBOMeshIFS::registerLoader();
	FileFinder::addDir(Config::getString("models"));
	
	scene.forceDoubleSided = true;
	scene.setCamera(&fly.camera);
	scene.load(sceneFiles[1]);
	scene.enableLighting(false);
	viewSlider.i = 0;
	viewSlider.upper = mymax(0, scene.getNumViews() - 1);
	changeView();
	
	gui.body.add(infoPanel);
	infoPanel.expand = QG::BOTH;
	infoPanel.fill = QG::BOTH;
	
	infoPanel.add(status);
	status.text.colour = vec4f(vec3f(0.0f), 1.0f);
	status.border = 1;
	status.anchor = QG::TOP_RIGHT;
	status.expand = QG::BOTH;
	status.fill = QG::NONE;
	//status.removeBackground();
	
	gui.controls.add(maxFragsSlider);
	gui.controls.add(viewSlider);
	gui.controls.add(lfbType);
	gui.controls.add(oitOptimize);
	maxFragsSlider.width = 300;
	maxFragsSlider.setDirty();
	maxFragsSlider.i = ilog2(oit.getMaxFrags()/8);
	changeMaxFrags();
	
	gui.controls.add(scene);
	gui.controls.add(alpha);
	
	maxFragsSlider.capture(QG::SCROLL, changeMaxFrags);
	viewSlider.capture(QG::SCROLL, changeView);
	
	lfbType.add("LL-LFB");
	lfbType.add("L-LFB");
	lfbType.add("CL-LFB");
	lfbType.add("B-LFB");
	lfbType.capture(QG::SELECT, selectType);

	for (int i = 0; i < oit.numOptimizations(); ++i)
	{
		oitOptimize.add(new QG::CheckBox(oit[i].getName().c_str()));
		if (((QG::CheckBox*)oitOptimize[i])->b != oit[i])
		{
			((QG::CheckBox*)oitOptimize[i])->b = oit[i];
			((QG::CheckBox*)oitOptimize[i])->setDirty();
		}
	}
	oitOptimize.capture(QG::CLICK, toggleOptimize);

	Material::defaultAnisotropy = 16;

/*
	//dragon.load("sponza/sponza.3ds");
	//dragon.load("powerplant/powerplant.ctm");
	dragon.load("dragon.ctm");
	dragon.computeInfo();
	dragon.transform(mat44::scale(vec3f(1.0f/dragon.boundsSize.y)) * mat44::translate(-vec3f(dragon.center.x, dragon.center.y, dragon.center.z)));
	//dragon.writeOBJ("mesh.obj");
	//dragon.repairWinding();
	//dragon.generateNormals();
	dragon.upload();
	*/
	
	//printf("Polygons: %i\n", dragon.numPolygons);
	//printf("Indices: %i\n", dragon.numIndices);
	//printf("Vertices: %i\n", dragon.numVertices);
	
	benchmark.setDefault("max", 64);
	
/*
	benchmark.setDefault("numLayers", 64);
	benchmark.setDefault("numPolygons", 0);
	benchmark.setDefault("numPixels", 512*512);
	Benchmark::Test *test;
	for (int t = 0; t < 3; ++t)
	{
		#if 0
		switch (t)
		{
		case 0:
			test = benchmark.createTest("Window Size");
			test->addVariable("numPixels", 256*256, 2048*2048, 2048*256);
			break;
		case 1:
			test = benchmark.createTest("Quad Layers");
			test->addVariable("numLayers", 0, 64, 4);
			break;
		case 2:
			test = benchmark.createTest("Poly Count");
			test->addVariable("numPolygons", 16*2, 1000000, 100000);
			break;
		}
		#else
		test = benchmark.createTest("Optimizations");
		#endif
		
		test->minToStart.time *= 2;
		test->minToStart.frames *= 2;
		test->minToTest.time *= 2;
		test->minToTest.time *= 2;
		
		for (int i = 0; i < oit.numOptimizations(); ++i)
			test->addVariable(oit[i].getID(), 0, 1);
		
		test->addVariable("LFB", 0, lfbType.size()-1);
	}
*/
	
	//benchmark.load("tests/sort_registers.xml");
		
	if (argc > 1)
	{
		std::string firstArg(argv[1]);
		if (basefilepath(firstArg) == "tests/")
		{
			//for (int i = 0; i < sizeof(sceneFiles)/sizeof(char*); ++i)
			//	scene.load(sceneFiles[i]); //prime the scenes
			benchmark.load(firstArg);
		}
	}
	
	alpha.f = 0.3f;
	
	
	benchmark.callback(updateBenchmark);
	//jeltz.redrawUnfocused();
	
	benchmark.include(&profiler);
	oit.setProfiler(&profiler);
	
	rtt.colour[0] = new Texture2D(vec2i(0), GL_RGBA8);
	rtt.stencil = new Texture2D(vec2i(0), GL_DEPTH24_STENCIL8);
	
	updateBenchmark();
	
	currentScene = drawScene;
	//currentScene = drawQuads;
	
	gui.drawSpeedup = false;
	
	//ShaderBuild::printProcessed = true;
	
	jeltz.run();
	return 0;
}

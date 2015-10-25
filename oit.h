/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */

#ifndef PYAR_OIT_H
#define PYAR_OIT_H

#include <pyarlib/vec.h>
#include <lfb/lfb.h>

#include <vector>
#include <map>
#include <string>

class Camera;
class Shader;
class Profiler;
class LFBBase;

class OIT
{
public:
	class Optimization {
		friend class OIT;
		OIT* parent;
		bool enabled;
		std::string id;
		std::string name;
	public:
		Optimization();
		Optimization(std::string i, std::string n, OIT* p);
		operator const bool&() const;
		Optimization& operator=(const bool& b);
		std::string getName();
		std::string getID();
	};
	friend class Optimization;
private:
	struct BMA {
		int start, end;
		Shader* shader;
		BMA() : start(0), end(0), shader(NULL) {}
	};
	
	bool dirtyShaders;
	Profiler* profiler;
	vec2i presortTileSize;
	vec2i indexingTileSize;
	TextureBuffer* sortedOrder;
	TextureBuffer* colourBuffer;
	Shader* shaderPresort;
	Shader* shaderReuse;
	Shader* shaderComposite;
	Shader* shaderSharedSort;
	std::vector<BMA> bmaIntervals;
	std::vector<Optimization> optimizations;
	std::map<std::string, int> optimizationIDs;
	LFB lfb;
	void setDefines(Shader* shader);
	void renderToLFB(void (*scene)(Shader*), Shader* shader);
	void createBMAMask();
	void compositeWithBMA();
	void compositeFromLFB();
	bool optimizationSet(const std::string& id, bool enabled); //returns false to undo/indicate option is invalid
	void updateShaders();
public:
	OIT();
	virtual ~OIT();
	void setLFBType(LFB::LFBType type);
	void setMaxFrags(int frags);
	int getMaxFrags();
	size_t getMemoryUsage(); //memory in GPU buffers only
	void setProfiler(Profiler* p);
	void draw(void (*scene)(Shader*), Shader* shader);
	size_t getTotalFragments();
	Optimization& operator[](int i);
	Optimization& operator[](const std::string& i);
	int numOptimizations();
	std::string info();
	bool getDepthHistogram(std::vector<unsigned int>& histogram); //requires using an LFB and optimization that uses per-pixel counts
	void drawDebug(Camera* source, Camera* view);
	const LFBBase* getLFB();
	std::vector<vec2i> computeRasterPattern();
};

#endif

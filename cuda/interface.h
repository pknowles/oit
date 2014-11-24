
#ifndef OIT_CUDA_INTERFACE_H
#define OIT_CUDA_INTERFACE_H

#if BUILDING_OIT_CUDA && HAVE_VISIBILITY
#define OC_DLL_EXPORT __attribute__((__visibility__("default")))
#elif BUILDING_LIBFOO && defined _MSC_VER
#define OC_DLL_EXPORT __declspec(dllexport)
#elif defined _MSC_VER
#define OC_DLL_EXPORT __declspec(dllimport)
#else
#define OC_DLL_EXPORT
#endif

class OIT_CUDA;
class LFB;
struct GPUBuffer;

typedef OIT_CUDA* (*getOIT_CUDA_FPTR)();
OC_DLL_EXPORT OIT_CUDA* getOIT_CUDA();

template<typename T> struct my_demand;

class OIT_CUDA
{
	friend struct my_demand<OIT_CUDA>;
	OIT_CUDA();
	bool error;
	void init();
public:
	virtual ~OIT_CUDA();
	bool mergesort;
	bool registersort;
	bool sortAndComposite(LFB* lfb, GPUBuffer* outBufferTexture); //returns false on error
};

#endif


#include "interface.h"
#include "oit.cuh"

#include <pyarlib/prec.h>
#include <pyarlib/util.h>
#include <pyarlib/gpu.h>

#include <lfb/lfb.h>
#include <lfb/lfbL.h>
#include <lfb/lfbLL.h>

static pyarlib::on_demand<OIT_CUDA> instance;

OIT_CUDA* getOIT_CUDA()
{
	return &(OIT_CUDA&)instance;
}

OIT_CUDA::OIT_CUDA()
{
	isDirty = true;
	mergesort = false;
	error = false;
	init();
}
OIT_CUDA::~OIT_CUDA()
{
}
void OIT_CUDA::init()
{
	error = error || !initCUDA();
}
bool OIT_CUDA::sortAndComposite(LFB* lfb, GPUBuffer* outBufferTexture)
{
	if (error)
		return false;
	
	LFBBase* lfbInstance = (LFBBase*)(*lfb);
	LFB_L* lfbL = dynamic_cast<LFB_L*>(lfbInstance);
	LFB_LL* lfbLL = dynamic_cast<LFB_LL*>(lfbInstance);
	
	bool needRefresh = false;
	static int bufferChecks[16];
	if (lfbL)
	{
		needRefresh =
			(lfbL->offsets->placementID != bufferChecks[0]) ||
			(lfbL->data->placementID != bufferChecks[1]) ||
			(outBufferTexture->placementID != bufferChecks[2]);
		bufferChecks[0] = lfbL->offsets->placementID;
		bufferChecks[1] = lfbL->data->placementID;
		bufferChecks[2] = outBufferTexture->placementID;
	}
	else if (lfbLL)
	{
		needRefresh =
			(lfbLL->headPtrs->placementID != bufferChecks[0]) ||
			(lfbLL->nextPtrs->placementID != bufferChecks[1]) ||
			(lfbLL->data->placementID != bufferChecks[2]) ||
			(outBufferTexture->placementID != bufferChecks[3]);
		bufferChecks[0] = lfbLL->headPtrs->placementID;
		bufferChecks[1] = lfbLL->nextPtrs->placementID;
		bufferChecks[2] = lfbLL->data->placementID;
		bufferChecks[3] = outBufferTexture->placementID;
	}
	
	if (isDirty || needRefresh)
	{
		isDirty = false;
		refreshCUDABuffers();
	}
	
	bool ok = false;
	if (lfbL)
		ok = compositeLinearizedShared(*lfbL->offsets, *lfbL->data, *outBufferTexture, (*lfb)->getTotalPixels(), (*lfb)->getMaxFrags());
		//ok = compositeLinearizedGlobal(*lfbL->offsets, *lfbL->data, *lfbL->ids, outBufferTexture, (*lfb)->getTotalPixels(), (*lfb)->getMaxFrags());
	else if (lfbLL)
	{
		ok = compositeLinkedLists(*lfbLL->headPtrs, *lfbLL->nextPtrs, *lfbLL->data, *outBufferTexture, (*lfb)->getTotalPixels(), (*lfb)->getMaxFrags(), mergesort, registersort);
	}
	
	error = !ok;
	
	return ok;
}

void OIT_CUDA::setDirty()
{
	isDirty = true;
}

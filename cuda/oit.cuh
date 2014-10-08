
#ifndef OIT_CUDA_H
#define OIT_CUDA_H

bool initCUDA();
void refreshCUDABuffers();
bool compositeLinkedLists(int heads, int nexts, int data, int outBufferTexture, int pixels, int maxFrags, bool mergeSort, bool registerSort);
bool compositeLinearizedShared(int offsets, int data, int outBufferTexture, int pixels, int maxFrags);
bool compositeLinearizedGlobal(int offsets, int data, int ids, int outBufferTexture, int pixels, int maxFrags);

#endif


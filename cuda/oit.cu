
#include <map>
#include <string>
#include <set>
#include <vector>
#include <list>
#include <pyarlib/includegl.h>
#include <pyarlib/util.h>
#include <inttypes.h>
#include <assert.h>

#include "oit.cuh"

#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_gl_interop.h>
#include <cudaGL.h>
//#include <cudpp.h>
#include <helper_cuda.h>         // helper functions for CUDA error check
#include <helper_cuda_gl.h>      // helper functions for CUDA/GL interop
#include <vector_types.h>


inline __host__ __device__ float4 operator+(float4 a, float4 b)
{
    return make_float4(a.x + b.x, a.y + b.y, a.z + b.z,  a.w + b.w);
}
inline __host__ __device__ float4 operator*(float4 a, float s)
{
    return make_float4(a.x * s, a.y * s, a.z * s, a.w * s);
}
inline __device__ float fract(float x)
{
	return x - floor(x);
}
__device__ float4 floatToRGBA8(float x)
{
	union { float f; unsigned int i; } tmp;
	tmp.f = x;
	unsigned int i = tmp.i;
	return make_float4(
		((float)(i>>24))/255.0f,
		((float)((i>>16)&0xFF))/255.0f,
		((float)((i>>8)&0xFF))/255.0f,
		((float)(i & 0xFF))/255.0f
		);
}


template<int A> struct Log2 {
	enum
	{
		value = Log2<(A >> 1)>::value + 1
	};
};
template<> struct Log2<1> {enum{value = 0};};
//Usage:
//uint n=Log2<16u>::value;

template <int A, int B>
struct Ceil
{
	enum
	{
		value = (A / B) + (A % B == 0 ? 0 : 1)
	};
};

template<size_t MAX_FRAGS>
__global__ void kernelLinkedLists(unsigned int* headPtrs, unsigned int* nextPtrs, float* data, uchar4* framebuffer, int stride, int n)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index >= n)
		return;
	
	float2 frags[MAX_FRAGS];
	
	int count = 0;
	
	int node = headPtrs[index];
	while (node != 0 && count < MAX_FRAGS)
	{
		frags[count].x = data[node * stride];
		frags[count].y = data[node * stride + 1];
		++count;
		node = nextPtrs[node];
	}
	
	for (int j = 1; j < count; ++j)
	{
		float2 key = frags[j];
		int i = j - 1;
		while (i >= 0 && frags[i].y > key.y)
		{
			frags[i+1] = frags[i];
			--i;
		}
		frags[i+1] = key;
	}
	
	float4 fragColour = {1.0f, 1.0f, 1.0f, 1.0f};
	for (int i = 0; i < count; ++i)
	{
		float4 col = floatToRGBA8(frags[count-i-1].x);
		fragColour = fragColour * (1.0 - col.w) + col * col.w;
	}
	
	fragColour = fragColour * 255;
	
	framebuffer[index] = make_uchar4(fragColour.x, fragColour.y, fragColour.z, 255);
	
	//unsigned char complexity = count;
	//framebuffer[index] = make_uchar4(complexity, complexity, complexity, 255);
	//framebuffer[index] = debug;
	//framebuffer[index] = make_uchar4(threadIndex%800, threadIndex/800, 0, 255);
}

#define FRAGS(x) frags[x]
#define LFB_FRAG_DEPTH(x) (x).y

template<size_t MAX_FRAGS>
__device__ void merge(float2 frags[], int step, int a, int b, int c)
{
	float2 leftArray[MAX_FRAGS/2];

	int i;
	for (i = 0; i < step; ++i)
		leftArray[i] = FRAGS(a+i);

	i = 0;
	int j = 0;
	for (int k = a; k < c; ++k)
	{
		if (b+j >= c || (i < step && LFB_FRAG_DEPTH(leftArray[i]) < LFB_FRAG_DEPTH(FRAGS(b+j))))
			FRAGS(k) = leftArray[i++];
		else
			FRAGS(k) = FRAGS(b+j++);
	}
}

template<size_t MAX_FRAGS>
__device__ void sort_merge(float2 frags[], int fragCount)
{
	int n = fragCount;
	int step = 1;
	while (step <= n)
	{
		int i = 0;
		while (i < n - step)
		{
			merge<MAX_FRAGS>(frags, step, i, i + step, min(i + step + step, n));
			i += 2 * step;
		}
		step *= 2;
	}
}

template<size_t MAX_FRAGS>
__global__ void kernelLinkedListsMerge(unsigned int* headPtrs, unsigned int* nextPtrs, float* data, uchar4* framebuffer, int stride, int n)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index >= n)
		return;
	
	float2 frags[MAX_FRAGS];
	
	int count = 0;
	
	int node = headPtrs[index];
	while (node != 0 && count < MAX_FRAGS)
	{
		frags[count].x = data[node * stride];
		frags[count].y = data[node * stride + 1];
		++count;
		node = nextPtrs[node];
	}
	
	if (count >= 32)
		sort_merge<MAX_FRAGS>(frags, count);
	else
	{
		for (int j = 1; j < count; ++j)
		{
			float2 key = frags[j];
			int i = j - 1;
			while (i >= 0 && frags[i].y > key.y)
			{
				frags[i+1] = frags[i];
				--i;
			}
			frags[i+1] = key;
		}
	}
	
	float4 fragColour = {1.0f, 1.0f, 1.0f, 1.0f};
	for (int i = 0; i < count; ++i)
	{
		float4 col = floatToRGBA8(frags[count-i-1].x);
		fragColour = fragColour * (1.0 - col.w) + col * col.w;
	}
	
	fragColour = fragColour * 255;
	
	framebuffer[index] = make_uchar4(fragColour.x, fragColour.y, fragColour.z, 255);
	
	//unsigned char complexity = count;
	//framebuffer[index] = make_uchar4(complexity, complexity, complexity, 255);
	//framebuffer[index] = debug;
	//framebuffer[index] = make_uchar4(threadIndex%800, threadIndex/800, 0, 255);
}

#define NUM_REGISTERS 32

__device__ void sortInRegisters(float2* frags, int count)
{
	/*
	//insertion sort into registers. OH WAIT NO. CUDA IS RETARDED AND WON'T UNROLL THE LOOPS
	#pragma unroll
	for (int i = 0; i < N; ++i)
	{
		if (i < count)
		{
			int j;
			float2 next = frags[i];
			#pragma unroll
			for (j = i; j > 0; --j)
				if (next.y < registers[j-1].y)
					registers[j] = registers[j-1];
			registers[j] = next;
		}
	}
	*/
	
	float2 tmp;
	#define SWAP(a, b) \
		if (frag##a.y > frag##b.y) {tmp = frag##a; frag##a = frag##b; frag##b = tmp;}
	
	#define N NUM_REGISTERS
	
	//BEGIN GENERATED
#if N > 0
float2 frag0,frag1,frag2,frag3,frag4,frag5,frag6,frag7;
#endif
#if N > 8
float2 frag8,frag9,frag10,frag11,frag12,frag13,frag14,frag15;
#endif
#if N > 16
float2 frag16,frag17,frag18,frag19,frag20,frag21,frag22,frag23,frag24,frag25,frag26,frag27,frag28,frag29,frag30,frag31;
#endif
#if N > 0
if (count > 0) frag0 = frags[0];
if (count > 1) frag1 = frags[1];
if (count > 2) frag2 = frags[2];
if (count > 3) frag3 = frags[3];
if (count > 4) frag4 = frags[4];
if (count > 5) frag5 = frags[5];
if (count > 6) frag6 = frags[6];
if (count > 7) frag7 = frags[7];
#endif
#if N > 8
if (count > 8) frag8 = frags[8];
if (count > 9) frag9 = frags[9];
if (count > 10) frag10 = frags[10];
if (count > 11) frag11 = frags[11];
if (count > 12) frag12 = frags[12];
if (count > 13) frag13 = frags[13];
if (count > 14) frag14 = frags[14];
if (count > 15) frag15 = frags[15];
#endif
#if N > 16
if (count > 16) frag16 = frags[16];
if (count > 17) frag17 = frags[17];
if (count > 18) frag18 = frags[18];
if (count > 19) frag19 = frags[19];
if (count > 20) frag20 = frags[20];
if (count > 21) frag21 = frags[21];
if (count > 22) frag22 = frags[22];
if (count > 23) frag23 = frags[23];
if (count > 24) frag24 = frags[24];
if (count > 25) frag25 = frags[25];
if (count > 26) frag26 = frags[26];
if (count > 27) frag27 = frags[27];
if (count > 28) frag28 = frags[28];
if (count > 29) frag29 = frags[29];
if (count > 30) frag30 = frags[30];
if (count > 31) frag31 = frags[31];
#endif

#if N > 0
if (count > 0) {
if (count > 1) {SWAP(0, 1);
if (count > 2) {SWAP(1, 2);SWAP(0, 1);
if (count > 3) {SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 4) {SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 5) {SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 6) {SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 7) {SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
#if N > 8
if (count > 8) {SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 9) {SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 10) {SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 11) {SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 12) {SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 13) {SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 14) {SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 15) {SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
#if N > 16
if (count > 16) {SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 17) {SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 18) {SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 19) {SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 20) {SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 21) {SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 22) {SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 23) {SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 24) {SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 25) {SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 26) {SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 27) {SWAP(26, 27);SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 28) {SWAP(27, 28);SWAP(26, 27);SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 29) {SWAP(28, 29);SWAP(27, 28);SWAP(26, 27);SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 30) {SWAP(29, 30);SWAP(28, 29);SWAP(27, 28);SWAP(26, 27);SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
if (count > 31) {SWAP(30, 31);SWAP(29, 30);SWAP(28, 29);SWAP(27, 28);SWAP(26, 27);SWAP(25, 26);SWAP(24, 25);SWAP(23, 24);SWAP(22, 23);SWAP(21, 22);SWAP(20, 21);SWAP(19, 20);SWAP(18, 19);SWAP(17, 18);SWAP(16, 17);SWAP(15, 16);SWAP(14, 15);SWAP(13, 14);SWAP(12, 13);SWAP(11, 12);SWAP(10, 11);SWAP(9, 10);SWAP(8, 9);SWAP(7, 8);SWAP(6, 7);SWAP(5, 6);SWAP(4, 5);SWAP(3, 4);SWAP(2, 3);SWAP(1, 2);SWAP(0, 1);
}}}}}}}}}}}}}}}}
#endif
}}}}}}}}
#endif
}}}}}}}}
#endif

#if N > 0
if (count > 0) frags[0] = frag0;
if (count > 1) frags[1] = frag1;
if (count > 2) frags[2] = frag2;
if (count > 3) frags[3] = frag3;
if (count > 4) frags[4] = frag4;
if (count > 5) frags[5] = frag5;
if (count > 6) frags[6] = frag6;
if (count > 7) frags[7] = frag7;
#endif
#if N > 8
if (count > 8) frags[8] = frag8;
if (count > 9) frags[9] = frag9;
if (count > 10) frags[10] = frag10;
if (count > 11) frags[11] = frag11;
if (count > 12) frags[12] = frag12;
if (count > 13) frags[13] = frag13;
if (count > 14) frags[14] = frag14;
if (count > 15) frags[15] = frag15;
#endif
#if N > 16
if (count > 16) frags[16] = frag16;
if (count > 17) frags[17] = frag17;
if (count > 18) frags[18] = frag18;
if (count > 19) frags[19] = frag19;
if (count > 20) frags[20] = frag20;
if (count > 21) frags[21] = frag21;
if (count > 22) frags[22] = frag22;
if (count > 23) frags[23] = frag23;
if (count > 24) frags[24] = frag24;
if (count > 25) frags[25] = frag25;
if (count > 26) frags[26] = frag26;
if (count > 27) frags[27] = frag27;
if (count > 28) frags[28] = frag28;
if (count > 29) frags[29] = frag29;
if (count > 30) frags[30] = frag30;
if (count > 31) frags[31] = frag31;
#endif

	//END GENERATED
}


template<size_t MAX_FRAGS>
__global__ void kernelLinkedListsRegisters(unsigned int* headPtrs, unsigned int* nextPtrs, float* data, uchar4* framebuffer, int stride, int n)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index >= n)
		return;
	
	float2 frags[MAX_FRAGS];
	
	int count = 0;
	
	int node = headPtrs[index];
	while (node != 0 && count < MAX_FRAGS)
	{
		frags[count].x = data[node * stride];
		frags[count].y = data[node * stride + 1];
		++count;
		node = nextPtrs[node];
	}
	
	//sort blocks in registers
	for (int i = 0; i < count; i += NUM_REGISTERS)
		sortInRegisters(frags + i, min(count - i, NUM_REGISTERS));
	//sortInRegisters<NUM_REGISTERS>(frags, NUM_REGISTERS);
	
	const int MERGE_SIZE = Ceil<MAX_FRAGS, NUM_REGISTERS>::value;
	
	//begin min-finding (actually since we want reverse order it's max-finding)
	int next[MERGE_SIZE];
	#pragma unroll
	for (int i = 0; i < MERGE_SIZE; ++i)
		next[i] = min(count, (i + 1) * NUM_REGISTERS) - 1;
	
	float4 fragColour = {1.0f, 1.0f, 1.0f, 1.0f};
	for (int i = 0; i < count; ++i)
	{
		#if 1
		
		int n; //I'll assume n *will* be set by the end of the loop
		float2 f;
		f.y = 0.0;
		#pragma unroll
		for (int j = 0; j < MERGE_SIZE; ++j)
		{
			if (next[j] >= j * NUM_REGISTERS)
			{
				if (frags[next[j]].y > f.y)
				{
					f = frags[next[j]];
					n = j;
				}
			}
		}
		
		#pragma unroll
		for (int j = 0; j < MERGE_SIZE; ++j)
			if (n == j)
				--next[j];
		
		#else
		
		float2 f = frags[i];
		
		#endif
		
		float4 col = floatToRGBA8(f.x);
		fragColour = fragColour * (1.0 - col.w) + col * col.w;
	}
	
	fragColour = fragColour * 255;
	
	framebuffer[index] = make_uchar4(fragColour.x, fragColour.y, fragColour.z, 255);
	
	//unsigned char complexity = count;
	//framebuffer[index] = make_uchar4(complexity, complexity, complexity, 255);
	//framebuffer[index] = debug;
	//framebuffer[index] = make_uchar4(threadIndex%800, threadIndex/800, 0, 255);
}

template<size_t NFRAGS>
__global__ void kernelLinearizedParallel(float* data, uchar4* out, int n)
{
	//*out = make_uchar4(n, n, 255, 255);
	//return;
	
	__shared__ float2 frags[NFRAGS];
	int i = threadIdx.x;
	
	//load the data
	if (i < n)
	{
		frags[i].x = data[i*2+0];
		frags[i].y = data[i*2+1];
	}
	else
	{
		frags[i].x = 0.0f;
		frags[i].y = 999.0f;
	}
	__syncthreads();

	int logn = Log2<NFRAGS>::value;
	float2 tmp;
	#define SWAPB(a, b) \
		if (a.y > b.y) {tmp = a; a = b; b = tmp;}

	//sort with bitonic sorting network
	for (int lk = 1; lk <= logn; ++lk)
	{
		int k = 1<<lk;
		for (int lj = lk-1; lj >= 0; --lj)
		{
			int j = 1<<lj;
			int ixj=i^j;
			if (ixj > i)
			{
				if ((i&k)==0) SWAPB(frags[i],frags[ixj])
				if ((i&k)!=0) SWAPB(frags[ixj],frags[i])
			}
			__syncthreads();
		}
	}
	
	//blend in pairs
	for (int lk = 0; lk < logn; ++lk)
	{
		int k = 1<<lk;
		if (i % k == 0)
		{
			uchar4& col = *reinterpret_cast<uchar4*>(&frags[i].x);
			uchar4 col2 = *reinterpret_cast<uchar4*>(&frags[i+k].x);
			float a = col.w / 255.0f;
			col2.x = col.x * a + col2.x * (1.0f - a);
			col2.y = col.y * a + col2.y * (1.0f - a);
			col2.z = col.z * a + col2.z * (1.0f - a);
			col2.w = 1.0f - (1.0f - a) * (1.0f - col2.w / 255.0f);
			frags[i].x = *reinterpret_cast<float*>(&col2);
		}
		__syncthreads();
	}
	
	//write the result
	if (i == 0)
	{
		*out = *reinterpret_cast<uchar4*>(&frags[0].x);
	}
}

template<size_t NFRAGS, size_t TPB>
__global__ void kernelLinearizedParallelSpawner(unsigned int* offsets, float* data, uchar4* framebuffer, int stride, int n)
{
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	if (index >= n)
		return;

	int offset = 0;
	if (index > 0)
		offset = offsets[index-1];
	int count = min((int)NFRAGS, (int)(offsets[index] - offset));
	
	kernelLinearizedParallel<NFRAGS><<<1, NFRAGS, NFRAGS*sizeof(float2)>>>(data + offset, framebuffer + index, count);
}

template<size_t MAX_FRAGS, size_t TPB>
__global__ void kernelLinearized(unsigned int* offsets, float* data, uchar4* framebuffer, int stride, int n)
{
	int index = blockIdx.x * TPB + threadIdx.x;

	__shared__ float2 temp[TPB];
	float2 frags[MAX_FRAGS];
	int fo = threadIdx.x * MAX_FRAGS;
	
	int count = 0;
	
	float4 fragColour = {1.0f, 1.0f, 1.0f, 1.0f};
	
	//read this: http://cuda-programming.blogspot.com.au/2013/02/bank-conflicts-in-shared-memory-in-cuda.html
	
	for (int i = 0; i < TPB; ++i) //i is the thread in this warp we're reading stuff for
	{
		int p = blockIdx.x * TPB + i; //p is the pixel index
		if (p < n)
		{
			for (int j = 0; j < MAX_FRAGS/TPB; ++j) //j is the element in i's array we're reading
			{
				//read the pixel's offset and count
				int o = 0;
				if (p > 0)
					o = offsets[p-1];
				int c = min((int)MAX_FRAGS, (int)(offsets[p] - o));
				
				//if there's data for us to load, load it
				int f = (j*TPB+threadIdx.x);
				if (f < c)
				{
					temp[threadIdx.x].x = data[(o + f) * stride + 0];
					temp[threadIdx.x].y = data[(o + f) * stride + 1];
				}
				
				__syncthreads();
				
				if (i == threadIdx.x)
				{
					count = c;
					for (int k = 0; k < TPB && j*TPB+k < c; ++k)
						frags[j*TPB+k] = temp[k];
				}
				
				__syncthreads();
			}
		}
	}
	
	if (index >= n)
		return;

	for (int j = 1; j < count; ++j)
	{
		float2 key = frags[fo+j];
		int i = j - 1;
		while (i >= 0 && frags[fo+i].y > key.y)
		{
			frags[fo+i+1] = frags[fo+i];
			--i;
		}
		frags[fo+i+1] = key;
	}
	
	for (int i = 0; i < count; ++i)
	{
		float4 col = floatToRGBA8(frags[fo+count-i-1].x);
		fragColour = fragColour * (1.0 - col.w) + col * col.w;
	}
	
	fragColour = fragColour * 255;
	
	framebuffer[index] = make_uchar4(fragColour.x, fragColour.y, fragColour.z, 255);
	
	//unsigned char complexity = count;
	//framebuffer[index] = make_uchar4(complexity, complexity, complexity, 255);
	//framebuffer[index] = debug;
	//framebuffer[index] = make_uchar4(threadIndex%800, threadIndex/800, 0, 255);
}

#define CHECK_CUDA_ERROR _checkCudaError(__FILE__, __LINE__)

bool _checkCudaError(const char* file, int line)
{
	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess)
	{
		printf("CUDA Error %s:%i: %s\n", file, line, cudaGetErrorString(err));
		return true;
	}
	return false;
}

class CUDAGLBuffer {
private:
	bool mapped;
	GLuint buffer;
	cudaGraphicsResource_t resource;
	static std::map<GLuint, CUDAGLBuffer*> cache;
public:
	CUDAGLBuffer(GLuint buffer) : buffer(buffer), resource(NULL)
	{
		printf("Created CUDA mapping for buffer %i\n", buffer);
		mapped = false;
		registerBuffer();
	}
	virtual ~CUDAGLBuffer()
	{
		unregisterBuffer();
	}
	void registerBuffer()
	{
		resource = NULL;
		checkCudaErrors(cudaGraphicsGLRegisterBuffer(&resource, buffer, cudaGraphicsRegisterFlagsNone));
		assert(resource != NULL);
	}
	void unregisterBuffer()
	{
		checkCudaErrors(cudaGraphicsUnregisterResource(resource));
		resource = NULL;
	}
	void* map()
	{
		if (!resource)
			registerBuffer();
	
		size_t size = 0;
		void* ptr = NULL;
		checkCudaErrors(cudaGraphicsMapResources(1, &resource, 0));
		checkCudaErrors(cudaGraphicsResourceGetMappedPointer((void **)&ptr, &size, resource));
		mapped = true;
		
		int actualSize;
		glBindBuffer(GL_ARRAY_BUFFER, buffer);
		glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &actualSize);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
		
		if (size != actualSize) //re-register if size has changed... uuuuurgh!
		{
			printf("CUDA RE-REGISTER %i\n", buffer);
			unmap(); unregisterBuffer(); registerBuffer();
			checkCudaErrors(cudaGraphicsMapResources(1, &resource, 0));
			checkCudaErrors(cudaGraphicsResourceGetMappedPointer((void **)&ptr, &size, resource));
			mapped = true;
			assert(size == actualSize);
		}
		
		return ptr;
	}
	void unmap()
	{
		if (!mapped)
			return;
		
		checkCudaErrors(cudaGraphicsUnmapResources(1, &resource, 0));
		mapped = false;
	}
	static struct Getter {
		void* operator[](GLuint i)
		{
			if (cache.find(i) == cache.end())
				cache[i] = new CUDAGLBuffer(i);
			return cache[i]->map();
		}
	} get;
	static void unmapAll()
	{
		std::map<GLuint, CUDAGLBuffer*>::iterator it;
		for (it = cache.begin(); it != cache.end(); ++it)
			it->second->unmap();
	}
	static void refreshAll()
	{
		std::map<GLuint, CUDAGLBuffer*>::iterator it;
		for (it = cache.begin(); it != cache.end(); ++it)
			it->second->unregisterBuffer();
	}
};
std::map<GLuint, CUDAGLBuffer*> CUDAGLBuffer::cache;
CUDAGLBuffer::Getter CUDAGLBuffer::get;

void refreshCUDABuffers()
{
	CUDAGLBuffer::refreshAll();
	printf("Refreshing buffers\n");
}

bool initCUDA()
{
	static bool hasInit = false;
	if (hasInit)
	{
		printf("Warning: trying to init cuda multiple times\n");
		return true;
	}
	
	int num_devices, device;
	cudaGetDeviceCount(&num_devices);
	if (num_devices == 0)
	{
		printf("NO CUDA DEVICES FOUND\n");
		return false;
	}
	int max_multiprocessors = 0, max_device = 0;
	for (device = 0; device < num_devices; device++)
	{
		cudaDeviceProp properties;
		cudaGetDeviceProperties(&properties, device);
		printf("Found CUDA DEVICE %i: %s %i %i\n", device, properties.name, properties.sharedMemPerBlock, properties.multiProcessorCount);
		if (max_multiprocessors < properties.multiProcessorCount) {
			max_multiprocessors = properties.multiProcessorCount;
			max_device = device;
		}
	}

	max_device = 0;

	cudaGLSetGLDevice(0);
	printf("Chose %i\n", max_device);
	cudaSetDevice(max_device);
	
	checkCudaErrors(cudaDeviceSetCacheConfig(cudaFuncCachePreferL1));
	
	hasInit = true;
	return true;
}

#define SWITCH_FRAGS(maxFrags, kernel, ...) \
	switch (maxFrags) \
	{ \
	case 8: kernel<8><<<grid,block>>>(__VA_ARGS__); break; \
	case 16: kernel<16><<<grid,block>>>(__VA_ARGS__); break; \
	case 32: kernel<32><<<grid,block>>>(__VA_ARGS__); break; \
	case 64: kernel<64><<<grid,block>>>(__VA_ARGS__); break; \
	case 128: kernel<128><<<grid,block>>>(__VA_ARGS__); break; \
	case 256: kernel<256><<<grid,block>>>(__VA_ARGS__); break; \
	case 512: kernel<512><<<grid,block>>>(__VA_ARGS__); break; \
	default: success = false; break; \
	} \

bool compositeLinkedLists(int heads, int nexts, int data, int outBufferTexture, int pixels, int maxFrags, bool mergeSort, bool registerSort)
{
	int stride = 2;
	unsigned int* headPtrs = (unsigned int*)CUDAGLBuffer::get[heads];
	unsigned int* nextPtrs = (unsigned int*)CUDAGLBuffer::get[nexts];
	float* dataPtr = (float*)CUDAGLBuffer::get[data];
	uchar4* framebuffer = (uchar4*)CUDAGLBuffer::get[outBufferTexture];
	
	//FIXME: 32 TPB is always faster. doesn't make sense - should then be limited by blocks per SM
	int tpb = 32;
	dim3 grid(ceil(pixels, tpb), 1, 1);
	dim3 block(tpb, 1, 1);
	
	bool success = true;
	
	
	if (registerSort)
	{
		switch (maxFrags)
		{
		case 8: kernelLinkedListsRegisters<8><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 16: kernelLinkedListsRegisters<16><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 32: kernelLinkedListsRegisters<32><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 64: kernelLinkedListsRegisters<64><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 128: kernelLinkedListsRegisters<128><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 256: kernelLinkedListsRegisters<256><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 512: kernelLinkedListsRegisters<512><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		default: success = false; break;
		}
	}
	else if (mergeSort)
	{
		SWITCH_FRAGS(maxFrags, kernelLinkedListsMerge, headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels);
	}
	else
	{
		switch (maxFrags)
		{
		case 8: kernelLinkedLists<8><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 16: kernelLinkedLists<16><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 32: kernelLinkedLists<32><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 64: kernelLinkedLists<64><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 128: kernelLinkedLists<128><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 256: kernelLinkedLists<256><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		case 512: kernelLinkedLists<512><<<grid,block>>>(headPtrs, nextPtrs, dataPtr, framebuffer, stride, pixels); break;
		default: success = false; break;
		}
	}
	
	if (CHECK_CUDA_ERROR)
		success = false;
	
	CUDAGLBuffer::unmapAll();
	return success;
}

bool compositeLinearizedShared(int offsets, int data, int outBufferTexture, int pixels, int maxFrags)
{
	int stride = 2;
	unsigned int* offsetsPtr = (unsigned int*)CUDAGLBuffer::get[offsets];
	float* dataPtr = (float*)CUDAGLBuffer::get[data];
	uchar4* framebuffer = (uchar4*)CUDAGLBuffer::get[outBufferTexture];
		
	const int tpb = 32;
	dim3 grid(ceil(pixels, tpb), 1, 1);
	dim3 block(tpb, 1, 1);
	
	int shared = sizeof(float2) * tpb;
	
	bool success = true;
	
	/*
	switch (maxFrags)
	{
	case 8: kernelLinearizedParallelSpawner<8, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 16: kernelLinearizedParallelSpawner<16, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 32: kernelLinearizedParallelSpawner<32, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 64: kernelLinearizedParallelSpawner<64, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 128: kernelLinearizedParallelSpawner<128, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 256: kernelLinearizedParallelSpawner<256, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	case 512: kernelLinearizedParallelSpawner<512, tpb><<<grid,block,shared>>>(offsetsPtr, dataPtr, framebuffer, stride, pixels); break;
	default: success = false; break;
	}
	*/
	
	if (CHECK_CUDA_ERROR)
		success = false;
	
	CUDAGLBuffer::unmapAll();
	return success;
}

bool compositeLinearizedGlobal(int offsets, int data, int ids, int outBufferTexture, int pixels, int maxFrags)
{
	return false;
}



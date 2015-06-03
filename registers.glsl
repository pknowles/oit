
#define NFRAGS MAX_FRAGS

#define REGISTERS_DISABLE_SORTING 0
#define REGISTERS_SORT_BITONIC 0
#define EXPLICIT_UNROLL 1

#if !EXPLICIT_UNROLL
void sortAndCompositeRegisters(int fragIndex)
{
	int fragCount = 0;
	
	//without this, the compiler chooses not to unroll above 16
	#pragma optionNV(unroll all)
	
	LFB_INIT(lfb, fragIndex);
	LFB_ITER_BEGIN(lfb);
	for (int i = 0; i < NFRAGS; ++i)
	{
		if (LFB_ITER_CONDITION(lfb))
		{
			fragCount = i+1;
			frags[i] = LFB_GET(lfb);
			LFB_ITER_INC(lfb);
			continue;
		}
		break;
	}
	
	#if !REGISTERS_DISABLE_SORTING
	
	LFB_FRAG_TYPE tmp;
	#define SWAP(a, b) \
		if (LFB_FRAG_DEPTH(a) > LFB_FRAG_DEPTH(b)) {tmp = a; a = b; b = tmp;}
	
	#if !REGISTERS_SORT_BITONIC
	
	#if 1
	//standard insertion
	
	for (int i = 1; i < NFRAGS; ++i)
	{
		if (i < fragCount)
		{
			for (int j = i; j > 0; --j)
				SWAP(frags[j-1], frags[j])
			continue;
		}
		break;
	}
	
	#else
	//semi insertion
	
	#pragma optionNV(unroll none)
	for (int i = 1; i < fragCount; ++i)
	{
		#define PART(j) if (i >= j) SWAP(frags[j-1], frags[j])
		#if NFRAGS > 32
		PART(63);
		PART(62);
		PART(61);
		PART(60);
		PART(59);
		PART(58);
		PART(57);
		PART(56);
		PART(55);
		PART(54);
		PART(53);
		PART(52);
		PART(51);
		PART(50);
		PART(49);
		PART(48);
		PART(47);
		PART(46);
		PART(45);
		PART(44);
		PART(43);
		PART(42);
		PART(41);
		PART(40);
		PART(39);
		PART(38);
		PART(37);
		PART(36);
		PART(35);
		PART(34);
		PART(33);
		PART(32);
		#endif
		#if NFRAGS > 16
		PART(31);
		PART(30);
		PART(29);
		PART(28);
		PART(27);
		PART(26);
		PART(25);
		PART(24);
		PART(23);
		PART(22);
		PART(21);
		PART(20);
		PART(19);
		PART(18);
		PART(17);
		PART(16);
		#endif
		#if NFRAGS > 8
		PART(15);
		PART(14);
		PART(13);
		PART(12);
		PART(11);
		PART(10);
		PART(9);
		PART(8);
		#endif
		PART(7);
		PART(6);
		PART(5);
		PART(4);
		PART(3);
		PART(2);
		PART(1);
	}
	#pragma optionNV(unroll all)
	
	#endif
				
	#else //REGISTERS_SORT_BITONIC
	
	for (int i = 1; i <= NFRAGS; ++i)
		if (fragCount < i)
			LFB_FRAG_DEPTH(frags[i-1]) = 9999.0;
	
	#if NFRAGS == 8
	#define LOG2_NFRAGS 3
	#elif NFRAGS == 16
	#define LOG2_NFRAGS 4
	#elif NFRAGS == 32
	#define LOG2_NFRAGS 5
	#elif NFRAGS == 64
	#define LOG2_NFRAGS 6
	#elif NFRAGS == 128
	#define LOG2_NFRAGS 7
	#endif

	for (int lk = 1; lk <= LOG2_NFRAGS; ++lk)
	{
		int k = 1<<lk;
		for (int lj = lk-1; lj >= 0; --lj)
		{
			int j = 1<<lj;
			for (int i = 0; i < NFRAGS; ++i)
			{
				int ixj=i^j;
				if (ixj > i)
				{
					if ((i&k)==0) SWAP(frags[i],frags[ixj])
					if ((i&k)!=0) SWAP(frags[ixj],frags[i])
				}
			}
		}
	}
	
	#endif //REGISTERS_SORT_BITONIC
	#endif //REGISTERS_DISABLE_SORTING
	
	fragColour = vec4(1.0);
	for (int i = NFRAGS-1; i >= 0; --i)
	{
		if (i < fragCount)
		{
			LFB_FRAG_TYPE f = frags[i];
			vec4 col = floatToRGBA8(f.x); //extract rgba from x
			fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a);
		}
	}
	fragColour.a = 1.0;
}

#else

void sortAndCompositeRegisters(int fragIndex)
{
	#define SWAP(idxa, idxb) if (LFB_FRAG_DEPTH(frag##idxa) > LFB_FRAG_DEPTH(frag##idxb)) {tmp=frag##idxa;frag##idxa=frag##idxb;frag##idxb=tmp;}
	#define SWAP_INS(idxa, idxb) if (LFB_FRAG_DEPTH(frag##idxa) > LFB_FRAG_DEPTH(frag##idxb)) {tmp=frag##idxa;frag##idxa=frag##idxb;frag##idxb=tmp;
	#define BLEND(idx) {col = floatToRGBA8(frag##idx.x); fragColour.rgb = mix(fragColour.rgb, col.rgb, col.a); }
	
	vec4 col;
	int fragCount;
	LFB_FRAG_TYPE tmp;
	fragColour = vec4(1.0);
	
	#define OPT_OUT_IFS 0 //OK, GLSL. you win. I know removing if statements that will always evaluate to true should be better but it's not
	
	#if OPT_OUT_IFS && IS_BMA_SHADER && MAX_FRAGS > 8
	#define IF_FRAGS_8(x)
	#define BLEND_8(i) BLEND(i)
	#else
	#define IF_FRAGS_8(x) if (x)
	#define BLEND_8(i) if (fragCount > i) BLEND(i)
	#endif
	
	#if OPT_OUT_IFS && IS_BMA_SHADER && MAX_FRAGS > 16
	#define IF_FRAGS_16(x)
	#define BLEND_16(i) BLEND(i)
	#else
	#define IF_FRAGS_16(x) if (x)
	#define BLEND_16(i) if (fragCount > i) BLEND(i)
	#endif
	
	#if OPT_OUT_IFS && IS_BMA_SHADER && MAX_FRAGS > 32
	#define IF_FRAGS_32(x)
	#define BLEND_32(i) BLEND(i)
	#else
	#define IF_FRAGS_32(x) if (x)
	#define BLEND_32(i) if (fragCount > i) BLEND(i)
	#endif
	
	#if OPT_OUT_IFS && IS_BMA_SHADER && MAX_FRAGS > 64
	#define IF_FRAGS_64(x)
	#define BLEND_64(i) BLEND(i)
	#else
	#define IF_FRAGS_64(x) if (x)
	#define BLEND_64(i) if (fragCount > i) BLEND(i)
	#endif
	
	
	#include "registersExplicit.glsl"

/*
	//BEGIN GENERATED
	
LFB_FRAG_TYPE frag0,frag1,frag2,frag3,frag4,frag5,frag6,frag7
        #if MAX_FRAGS > 8
        ,frag8,frag9,frag10,frag11,frag12,frag13,frag14,frag15
        #endif
        #if MAX_FRAGS > 16
        ,frag16,frag17,frag18,frag19,frag20,frag21,frag22,frag23,frag24,frag25,frag26,frag27,frag28,frag29,frag30,frag31
        #endif
        ;
LFB_INIT(lfb, fragIndex);
LFB_ITER_BEGIN(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 1; frag0 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 2; frag1 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 3; frag2 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 4; frag3 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 5; frag4 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 6; frag5 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 7; frag6 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_8(LFB_ITER_CONDITION(lfb)) {fragCount = 8; frag7 = LFB_GET(lfb); LFB_ITER_INC(lfb);
#if MAX_FRAGS > 8
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 9; frag8 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 10; frag9 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 11; frag10 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 12; frag11 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 13; frag12 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 14; frag13 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 15; frag14 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_16(LFB_ITER_CONDITION(lfb)) {fragCount = 16; frag15 = LFB_GET(lfb); LFB_ITER_INC(lfb);
#endif
#if MAX_FRAGS > 16
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 17; frag16 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 18; frag17 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 19; frag18 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 20; frag19 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 21; frag20 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 22; frag21 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 23; frag22 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 24; frag23 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 25; frag24 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 26; frag25 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 27; frag26 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 28; frag27 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 29; frag28 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 30; frag29 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 31; frag30 = LFB_GET(lfb); LFB_ITER_INC(lfb);
IF_FRAGS_32(LFB_ITER_CONDITION(lfb)) {fragCount = 32; frag31 = LFB_GET(lfb); LFB_ITER_INC(lfb);
#endif
#if MAX_FRAGS > 8
}}}}}}}}
#endif
#if MAX_FRAGS > 16
}}}}}}}}}}}}}}}}
#endif
}}}}}}}}
#if !REGISTERS_DISABLE_SORTING
#if !REGISTERS_SORT_BITONIC
IF_FRAGS_8(fragCount > 1) {SWAP_INS(0, 1)}
IF_FRAGS_8(fragCount > 2) {SWAP_INS(1, 2)SWAP_INS(0, 1)}}
IF_FRAGS_8(fragCount > 3) {SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}
IF_FRAGS_8(fragCount > 4) {SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}
IF_FRAGS_8(fragCount > 5) {SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}
IF_FRAGS_8(fragCount > 6) {SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}
IF_FRAGS_8(fragCount > 7) {SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}
#if MAX_FRAGS > 8
IF_FRAGS_16(fragCount > 8) {SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}
IF_FRAGS_16(fragCount > 9) {SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}
IF_FRAGS_16(fragCount > 10) {SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}
IF_FRAGS_16(fragCount > 11) {SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}
IF_FRAGS_16(fragCount > 12) {SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}
IF_FRAGS_16(fragCount > 13) {SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}
IF_FRAGS_16(fragCount > 14) {SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}
IF_FRAGS_16(fragCount > 15) {SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}
#if MAX_FRAGS > 16
IF_FRAGS_32(fragCount > 16) {SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 17) {SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 18) {SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 19) {SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 20) {SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 21) {SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 22) {SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 23) {SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 24) {SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 25) {SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 26) {SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 27) {SWAP_INS(26, 27)SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 28) {SWAP_INS(27, 28)SWAP_INS(26, 27)SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 29) {SWAP_INS(28, 29)SWAP_INS(27, 28)SWAP_INS(26, 27)SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 30) {SWAP_INS(29, 30)SWAP_INS(28, 29)SWAP_INS(27, 28)SWAP_INS(26, 27)SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}
IF_FRAGS_32(fragCount > 31) {SWAP_INS(30, 31)SWAP_INS(29, 30)SWAP_INS(28, 29)SWAP_INS(27, 28)SWAP_INS(26, 27)SWAP_INS(25, 26)SWAP_INS(24, 25)SWAP_INS(23, 24)SWAP_INS(22, 23)SWAP_INS(21, 22)SWAP_INS(20, 21)SWAP_INS(19, 20)SWAP_INS(18, 19)SWAP_INS(17, 18)SWAP_INS(16, 17)SWAP_INS(15, 16)SWAP_INS(14, 15)SWAP_INS(13, 14)SWAP_INS(12, 13)SWAP_INS(11, 12)SWAP_INS(10, 11)SWAP_INS(9, 10)SWAP_INS(8, 9)SWAP_INS(7, 8)SWAP_INS(6, 7)SWAP_INS(5, 6)SWAP_INS(4, 5)SWAP_INS(3, 4)SWAP_INS(2, 3)SWAP_INS(1, 2)SWAP_INS(0, 1)}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}
#endif
#endif
#if MAX_FRAGS > 8
}}}}}}}}
#endif
#if MAX_FRAGS > 16
}}}}}}}}}}}}}}}}
#endif
}}}}}}}
#else
if (fragCount < 1) LFB_FRAG_DEPTH(frag0) = 9999.0;
if (fragCount < 2) LFB_FRAG_DEPTH(frag1) = 9999.0;
if (fragCount < 3) LFB_FRAG_DEPTH(frag2) = 9999.0;
if (fragCount < 4) LFB_FRAG_DEPTH(frag3) = 9999.0;
if (fragCount < 5) LFB_FRAG_DEPTH(frag4) = 9999.0;
if (fragCount < 6) LFB_FRAG_DEPTH(frag5) = 9999.0;
if (fragCount < 7) LFB_FRAG_DEPTH(frag6) = 9999.0;
if (fragCount < 8) LFB_FRAG_DEPTH(frag7) = 9999.0;
#if MAX_FRAGS > 8
if (fragCount < 9) LFB_FRAG_DEPTH(frag8) = 9999.0;
if (fragCount < 10) LFB_FRAG_DEPTH(frag9) = 9999.0;
if (fragCount < 11) LFB_FRAG_DEPTH(frag10) = 9999.0;
if (fragCount < 12) LFB_FRAG_DEPTH(frag11) = 9999.0;
if (fragCount < 13) LFB_FRAG_DEPTH(frag12) = 9999.0;
if (fragCount < 14) LFB_FRAG_DEPTH(frag13) = 9999.0;
if (fragCount < 15) LFB_FRAG_DEPTH(frag14) = 9999.0;
if (fragCount < 16) LFB_FRAG_DEPTH(frag15) = 9999.0;
#if MAX_FRAGS > 16
if (fragCount < 17) LFB_FRAG_DEPTH(frag16) = 9999.0;
if (fragCount < 18) LFB_FRAG_DEPTH(frag17) = 9999.0;
if (fragCount < 19) LFB_FRAG_DEPTH(frag18) = 9999.0;
if (fragCount < 20) LFB_FRAG_DEPTH(frag19) = 9999.0;
if (fragCount < 21) LFB_FRAG_DEPTH(frag20) = 9999.0;
if (fragCount < 22) LFB_FRAG_DEPTH(frag21) = 9999.0;
if (fragCount < 23) LFB_FRAG_DEPTH(frag22) = 9999.0;
if (fragCount < 24) LFB_FRAG_DEPTH(frag23) = 9999.0;
if (fragCount < 25) LFB_FRAG_DEPTH(frag24) = 9999.0;
if (fragCount < 26) LFB_FRAG_DEPTH(frag25) = 9999.0;
if (fragCount < 27) LFB_FRAG_DEPTH(frag26) = 9999.0;
if (fragCount < 28) LFB_FRAG_DEPTH(frag27) = 9999.0;
if (fragCount < 29) LFB_FRAG_DEPTH(frag28) = 9999.0;
if (fragCount < 30) LFB_FRAG_DEPTH(frag29) = 9999.0;
if (fragCount < 31) LFB_FRAG_DEPTH(frag30) = 9999.0;
if (fragCount < 32) LFB_FRAG_DEPTH(frag31) = 9999.0;
#endif
#endif
SWAP(0, 1);SWAP(3, 2);SWAP(4, 5);SWAP(7, 6);
#if MAX_FRAGS > 8
SWAP(8, 9);SWAP(11, 10);SWAP(12, 13);SWAP(15, 14);
#if MAX_FRAGS > 16
SWAP(16, 17);SWAP(19, 18);SWAP(20, 21);SWAP(23, 22);SWAP(24, 25);SWAP(27, 26);SWAP(28, 29);SWAP(31, 30);
#endif
#endif
SWAP(0, 2);SWAP(1, 3);SWAP(6, 4);SWAP(7, 5);
#if MAX_FRAGS > 8
SWAP(8, 10);SWAP(9, 11);SWAP(14, 12);SWAP(15, 13);
#if MAX_FRAGS > 16
SWAP(16, 18);SWAP(17, 19);SWAP(22, 20);SWAP(23, 21);SWAP(24, 26);SWAP(25, 27);SWAP(30, 28);SWAP(31, 29);
#endif
#endif
SWAP(0, 1);SWAP(2, 3);SWAP(5, 4);SWAP(7, 6);
#if MAX_FRAGS > 8
SWAP(8, 9);SWAP(10, 11);SWAP(13, 12);SWAP(15, 14);
#if MAX_FRAGS > 16
SWAP(16, 17);SWAP(18, 19);SWAP(21, 20);SWAP(23, 22);SWAP(24, 25);SWAP(26, 27);SWAP(29, 28);SWAP(31, 30);
#endif
#endif
SWAP(0, 4);SWAP(1, 5);SWAP(2, 6);SWAP(3, 7);
#if MAX_FRAGS > 8
SWAP(12, 8);SWAP(13, 9);SWAP(14, 10);SWAP(15, 11);
#if MAX_FRAGS > 16
SWAP(16, 20);SWAP(17, 21);SWAP(18, 22);SWAP(19, 23);SWAP(28, 24);SWAP(29, 25);SWAP(30, 26);SWAP(31, 27);
#endif
#endif
SWAP(0, 2);SWAP(1, 3);SWAP(4, 6);SWAP(5, 7);
#if MAX_FRAGS > 8
SWAP(10, 8);SWAP(11, 9);SWAP(14, 12);SWAP(15, 13);
#if MAX_FRAGS > 16
SWAP(16, 18);SWAP(17, 19);SWAP(20, 22);SWAP(21, 23);SWAP(26, 24);SWAP(27, 25);SWAP(30, 28);SWAP(31, 29);
#endif
#endif
SWAP(0, 1);SWAP(2, 3);SWAP(4, 5);SWAP(6, 7);
#if MAX_FRAGS > 8
SWAP(9, 8);SWAP(11, 10);SWAP(13, 12);SWAP(15, 14);
#if MAX_FRAGS > 16
SWAP(16, 17);SWAP(18, 19);SWAP(20, 21);SWAP(22, 23);SWAP(25, 24);SWAP(27, 26);SWAP(29, 28);SWAP(31, 30);
#endif
#endif
#if MAX_FRAGS > 8
SWAP(0, 8);SWAP(1, 9);SWAP(2, 10);SWAP(3, 11);SWAP(4, 12);SWAP(5, 13);SWAP(6, 14);SWAP(7, 15);
#if MAX_FRAGS > 16
SWAP(24, 16);SWAP(25, 17);SWAP(26, 18);SWAP(27, 19);SWAP(28, 20);SWAP(29, 21);SWAP(30, 22);SWAP(31, 23);
#endif
SWAP(0, 4);SWAP(1, 5);SWAP(2, 6);SWAP(3, 7);SWAP(8, 12);SWAP(9, 13);SWAP(10, 14);SWAP(11, 15);
#if MAX_FRAGS > 16
SWAP(20, 16);SWAP(21, 17);SWAP(22, 18);SWAP(23, 19);SWAP(28, 24);SWAP(29, 25);SWAP(30, 26);SWAP(31, 27);
#endif
SWAP(0, 2);SWAP(1, 3);SWAP(4, 6);SWAP(5, 7);SWAP(8, 10);SWAP(9, 11);SWAP(12, 14);SWAP(13, 15);
#if MAX_FRAGS > 16
SWAP(18, 16);SWAP(19, 17);SWAP(22, 20);SWAP(23, 21);SWAP(26, 24);SWAP(27, 25);SWAP(30, 28);SWAP(31, 29);
#endif
SWAP(0, 1);SWAP(2, 3);SWAP(4, 5);SWAP(6, 7);SWAP(8, 9);SWAP(10, 11);SWAP(12, 13);SWAP(14, 15);
#if MAX_FRAGS > 16
SWAP(17, 16);SWAP(19, 18);SWAP(21, 20);SWAP(23, 22);SWAP(25, 24);SWAP(27, 26);SWAP(29, 28);SWAP(31, 30);
#endif
#if MAX_FRAGS > 16
SWAP(0, 16);SWAP(1, 17);SWAP(2, 18);SWAP(3, 19);SWAP(4, 20);SWAP(5, 21);SWAP(6, 22);SWAP(7, 23);SWAP(8, 24);SWAP(9, 25);SWAP(10, 26);SWAP(11, 27);SWAP(12, 28);SWAP(13, 29);SWAP(14, 30);SWAP(15, 31);
SWAP(0, 8);SWAP(1, 9);SWAP(2, 10);SWAP(3, 11);SWAP(4, 12);SWAP(5, 13);SWAP(6, 14);SWAP(7, 15);SWAP(16, 24);SWAP(17, 25);SWAP(18, 26);SWAP(19, 27);SWAP(20, 28);SWAP(21, 29);SWAP(22, 30);SWAP(23, 31);
SWAP(0, 4);SWAP(1, 5);SWAP(2, 6);SWAP(3, 7);SWAP(8, 12);SWAP(9, 13);SWAP(10, 14);SWAP(11, 15);SWAP(16, 20);SWAP(17, 21);SWAP(18, 22);SWAP(19, 23);SWAP(24, 28);SWAP(25, 29);SWAP(26, 30);SWAP(27, 31);
SWAP(0, 2);SWAP(1, 3);SWAP(4, 6);SWAP(5, 7);SWAP(8, 10);SWAP(9, 11);SWAP(12, 14);SWAP(13, 15);SWAP(16, 18);SWAP(17, 19);SWAP(20, 22);SWAP(21, 23);SWAP(24, 26);SWAP(25, 27);SWAP(28, 30);SWAP(29, 31);
SWAP(0, 1);SWAP(2, 3);SWAP(4, 5);SWAP(6, 7);SWAP(8, 9);SWAP(10, 11);SWAP(12, 13);SWAP(14, 15);SWAP(16, 17);SWAP(18, 19);SWAP(20, 21);SWAP(22, 23);SWAP(24, 25);SWAP(26, 27);SWAP(28, 29);SWAP(30, 31);
#endif
#endif
#endif
#endif
#if MAX_FRAGS > 16
BLEND_32(31);BLEND_32(30);BLEND_32(29);BLEND_32(28);BLEND_32(27);BLEND_32(26);BLEND_32(25);BLEND_32(24);BLEND_32(23);BLEND_32(22);BLEND_32(21);BLEND_32(20);BLEND_32(19);BLEND_32(18);BLEND_32(17);BLEND_32(16);
#endif
#if MAX_FRAGS > 8
BLEND_16(15);BLEND_16(14);BLEND_16(13);BLEND_16(12);BLEND_16(11);BLEND_16(10);BLEND_16(9);BLEND_16(8);
#endif
BLEND_8(7);BLEND_8(6);BLEND_8(5);BLEND_8(4);BLEND_8(3);BLEND_8(2);BLEND_8(1);BLEND_8(0);
	//END GENERATED
	*/
}
#endif

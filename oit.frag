/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */
#version 430
#extension GL_NV_gpu_shader5: enable

#define MAX_FRAGS_OVERRIDE 0
#if MAX_FRAGS_OVERRIDE != 0
#define MAX_FRAGS MAX_FRAGS_OVERRIDE
#endif

#define DEBUG 0

#define IS_BMA_SHADER (MAX_FRAGS_OVERRIDE != 0)

//We read the linearized LFB in reverse order to make them match the linked list LFB order
#define LFB_L_REVERSE 1

#include "lfb.glsl"
#include "util.glsl"

LFB_DEC(lfb);

#if LFB_FRAG_SIZE == 2 && 0
struct FragPack
{
	vec2 data[2];
};
#define FRAGS(x) packedFrags[(x)>>1].data[(x)&1]
FragPack packedFrags[MAX_FRAGS/2];
#else
#define FRAGS(x) frags[x]
LFB_FRAG_TYPE frags[MAX_FRAGS];
#endif

#include "sortlfb.glsl"

out vec4 fragColour;

#define INDEX_WITH_TILES set_by_app
#define INDEX_TILE_SIZE 2,8

#define PRESORT_SORT 0
#define PRESORT_REUSE 0
#define SORT_IN_REGISTERS 0
#define SORT_IN_BOTH 0
#define COMPOSITE_ONLY 0

#if PRESORT_SORT || PRESORT_REUSE
#include "presort.glsl"
#else
//force early fragment tests. seems to be an issue with some drivers
layout(early_fragment_tests) in;
#endif

#if SORT_IN_REGISTERS || SORT_IN_BOTH
#include "registers.glsl"
#endif
		
#if SORT_IN_BOTH
#include "hybridsort.glsl"
#endif

#include "standard.glsl"

#if 1

float avg(vec3 c)
{
	return (c.r + c.g + c.b) / 3.0;
}

void main()
{
	#if INDEX_WITH_TILES
	int fragIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), ivec2(gl_FragCoord.xy));
	#else
	int fragIndex = LFB_FRAG_HASH(lfb);
	#endif
	
	#if PRESORT_SORT
	presortFrags();
	#elif PRESORT_REUSE
	reuseSort(fragIndex);
	#else
		#if COMPOSITE_ONLY
		compositeOnly(fragIndex);
		#else
			#if (SORT_IN_REGISTERS || SORT_IN_BOTH) && MAX_FRAGS <= 32
			sortAndCompositeRegisters(fragIndex);
			#elif SORT_IN_BOTH
			sortAndCompositeBlocks(fragIndex);
			#else
			sortAndComposite(fragIndex);
			#endif
		#endif
	#endif
	
	#if IS_BMA_SHADER
	//fragColour.rgb = mix(fragColour.rgb, debugColLog(MAX_FRAGS), 0.25);
	float dc = MAX_FRAGS_OVERRIDE/float(_MAX_FRAGS);
	dc = sqrt(dc);
	fragColour.rgb = mix(vec3(avg(fragColour.rgb)), heat(dc), 0.25);
	//fragColour.rgb *= fragColour.rgb * fragColour.rgb;
	#endif
	
	#ifdef LFB_COUNT
	//fragColour.rgb = heat(LFB_COUNT(lfb)/float(_MAX_FRAGS));
	#endif
	
	fragColour.a = 1.0;
}
#endif

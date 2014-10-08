/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */

#version 420

#include "lfb.glsl"

LFB_DEC(lfb)

uniform int interval;

#define DEBUG 0

#if DEBUG
#include "util.glsl"
out vec4 fragColour;
#endif

#define INDEX_WITH_TILES set_by_app
#define INDEX_TILE_SIZE 4,8

void main()
{
	#if INDEX_WITH_TILES
	int fragIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), ivec2(gl_FragCoord.xy));
	#else
	int fragIndex = LFB_FRAG_HASH(lfb);
	#endif
	
	int fragCount = LFB_COUNT_AT(lfb, fragIndex);
	
	if (fragCount <= interval)
		discard;
	
	#if DEBUG
	fragColour = vec4(debugColLog(fragCount), 1.0);
	#endif
}


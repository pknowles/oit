/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */
#version 420

#include "lfb.glsl"
LFB_DEC(lfb);

#define INDEX_WITH_TILES set_by_app
#define INDEX_TILE_SIZE 4,8

void main()
{
	#if INDEX_WITH_TILES
	int fragIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), ivec2(gl_FragCoord.xy));
	#else
	int fragIndex = LFB_FRAG_HASH(lfb);
	#endif
	
	addFragment(lfb, fragIndex, LFB_FRAG_TYPE(0.0));
}


/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */
#version 420

#define DIRECT_RENDER 0

out vec4 fragColour;

flat in int triangleID;
in vec3 osFrag;

in vec3 debug;

#if !DIRECT_RENDER
#include "lfb.glsl"
LFB_DEC(lfb);
#endif

#define BACKLIT
#include "phong.glsl"
#include "util.glsl"

uniform vec4 colourMod;

uniform ivec2 packTileSize;

uniform int counting;
layout(size1x32) uniform coherent uimageBuffer fragCounts;

#define INDEX_WITH_TILES set_by_app
#define INDEX_TILE_SIZE 4,8

void main()
{
	fragColour = phong();
	//fragColour.rgb = 1.0 - exp(fragColour.rgb * -4.0);

	
	//vec3 N = normalize(esNorm);
	
	#if 0
	fragColour = fract(osFrag.x*3) > 0.5 ? vec4(1,1,1,0.1) : vec4(0,1,0,1);
	fragColour.rgb *= abs(N.z);
	#endif
	
	//fragColour.rgb = N;
	
	fragColour *= colourMod;
	//fragColour.a = 1.0;
	//fragColour.a = 1.0-abs(N.z);
	//fragColour.a *= 0.5;

	#if !DIRECT_RENDER
	//float d = gl_FragCoord.z;
	float d = -esFrag.z;
	#if INDEX_WITH_TILES
	int index = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), ivec2(gl_FragCoord.xy));
	#else
	int index = LFB_FRAG_HASH(lfb);
	#endif
	addFragment(lfb, index, make_lfb_data(vec2(rgba8ToFloat(fragColour), d)));
	#endif
}


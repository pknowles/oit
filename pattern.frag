/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */

#version 420

layout(binding = 0, offset = 0) uniform atomic_uint counter;
layout(rg32ui) uniform uimageBuffer positions;

void main()
{
	int index = int(atomicCounterIncrement(counter));
	imageStore(positions, index, uvec4(gl_FragCoord.xy, 0, 0));
	discard;
}

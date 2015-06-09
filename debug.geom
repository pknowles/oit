#version 420
layout(points) in;
layout(triangle_strip, max_vertices = 30) out;

#include "lfb.glsl"
#include "util.glsl"

#define INDEX_WITH_TILES 0
#define INDEX_TILE_SIZE 4,8

uniform mat4 reprojectMat;
uniform mat4 sourceProjectionInv;
uniform mat4 sourceCameraToClip;

flat in int pixel[1];

out vec2 quadCoord;
out vec4 colour;

uniform int batch;

LFB_DEC(lfb);

vec4 project(vec2 coord, float depth)
{
	#if 0
	return reprojectMat * vec4(coord, depth * 2.0 - 1.0, 1.0);
	#else
	//phong.frag currently gives eye space depth
	vec4 A = sourceProjectionInv * vec4(coord, -1.0, 1.0);
	vec4 B = sourceProjectionInv * vec4(coord, 1.0, 1.0);
	A /= A.w;
	B /= B.w;
	return sourceCameraToClip * mix(A, B, (-depth-A.z)/(B.z-A.z));
	#endif
}

void main()
{
	ivec2 coord = ivec2(pixel[0] % lfbInfolfb.size.x, pixel[0] / lfbInfolfb.size.x);
	
	#if INDEX_WITH_TILES
	int fragIndex = tilesIndex(LFB_SIZE(lfb), ivec2(INDEX_TILE_SIZE), coord);
	#else
	int fragIndex = pixel[0];
	#endif
	
	vec2 clipCoordA = 2.0 * vec2(coord) / vec2(lfbInfolfb.size) - 1.0f;
	vec2 clipCoordB = 2.0 * vec2(coord.x,coord.y+2) / vec2(lfbInfolfb.size) - 1.0f;
	vec2 clipCoordC = 2.0 * vec2(coord.x+2,coord.y) / vec2(lfbInfolfb.size) - 1.0f;
	
	#if 0 //why isn't anything drawing.... for the 10th time!!!
	colour = vec4(1,0,0,1);
	quadCoord = vec2(0.0, 0.0);
	gl_Position = projectionMat * vec4(clipCoordA, 0.5 * 2.0 - 1.0, 1.0);
	EmitVertex();
	quadCoord = vec2(0.0, 2.0);
	gl_Position = projectionMat * vec4(clipCoordB, 0.5 * 2.0 - 1.0, 1.0);
	EmitVertex();
	quadCoord = vec2(2.0, 0.0);
	gl_Position = projectionMat * vec4(clipCoordC, 0.5 * 2.0 - 1.0, 1.0);
	EmitVertex();
	EndPrimitive();
	return;
	#endif
	
	LFB_INIT(lfb, fragIndex);
	
	int i = 0;
	LFB_ITER_BEGIN(lfb);
	while (i < batch && LFB_ITER_CONDITION(lfb))
	{
		LFB_ITER_INC(lfb);
		++i;
	}
	i = 0;
	while (i < 10 && LFB_ITER_CONDITION(lfb))
	{
		//IF ITS NOT DRAWING, DEPTH IS PROBABLY NOT WRITTEN IN THE CORRECT STATE
	
		LFB_FRAG_TYPE frag = LFB_GET(lfb);
		LFB_ITER_INC(lfb);
		colour = floatToRGBA8(frag.x);
		++i;
		quadCoord = vec2(0.0, 0.0);
		gl_Position = project(clipCoordA, LFB_FRAG_DEPTH(frag));
		EmitVertex();
		quadCoord = vec2(0.0, 2.0);
		gl_Position = project(clipCoordB, LFB_FRAG_DEPTH(frag));
		EmitVertex();
		quadCoord = vec2(2.0, 0.0);
		gl_Position = project(clipCoordC, LFB_FRAG_DEPTH(frag));
		EmitVertex();
		EndPrimitive();
	}
}

/* Copyright 2011 Pyarelal Knowles, under GNU LGPL (see LICENCE.txt) */

#version 420

in vec4 osVert;
in vec3 osNorm;
in vec3 osTangent;
in vec2 texCoord;

uniform mat4 projectionMat;
uniform mat4 modelviewMat;
uniform mat3 normalMat;
uniform vec4 lightPos;

#include "phong.glsl"

out vec3 osFragV;
	
void main()
{
	phong();
	osFragV = osVert.xyz;
}


#version 420

flat out int pixel;

void main()
{
	pixel = gl_VertexID;
	gl_Position = vec4(0);
}

#version 420

in vec4 colour;
in vec2 quadCoord;

out vec4 fragColour;

void main()
{
	if (quadCoord.x > 1.0 || quadCoord.y > 1.0)
		discard;
	fragColour = vec4(colour.rgb, 1.0);
}

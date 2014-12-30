#version 420

in vec4 colour;
in vec2 quadCoord;

out vec4 fragColour;

void main()
{
	if (quadCoord.x > 1.0 || quadCoord.y > 1.0)
		discard;
	fragColour = vec4(colour.rgb, 1.0);
	if (max(abs(quadCoord.x-0.5), abs(quadCoord.y-0.5)) > 0.45)
		fragColour = vec4(0,0,0,1);
}

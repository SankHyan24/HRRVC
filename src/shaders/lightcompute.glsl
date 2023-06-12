
#version 430
#define PI 3.1415926535897932

#define KS 32 // kernel size
layout (local_size_x = KS, local_size_y = KS) in;

uniform sampler2D u_inputTex;
uniform writeonly image2D u_outImg;

void main()
{
	const ivec2 gid = ivec2(gl_WorkGroupID.xy);
	const ivec2 tid = ivec2(gl_LocalInvocationID.xy);
	const ivec2 pixelPos = ivec2(KS) * gid + tid;
	vec2 pixelPosf = ivec2(KS) * gid + tid; 
	imageStore(u_outImg, pixelPos,
		vec4(pixelPosf, 128.0, 172.0));
}

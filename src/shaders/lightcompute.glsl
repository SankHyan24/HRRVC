
#version 430
#define PI 3.1415926535897932

#define KS 16 // kernel size
layout (local_size_x = KS, local_size_y = KS) in;

uniform sampler2D u_inputTex;
uniform writeonly uimage2D u_outImg;

void main()
{
	const ivec2 gid = ivec2(gl_WorkGroupID.xy);
	const ivec2 tid = ivec2(gl_LocalInvocationID.xy);
	const ivec2 pixelPos = ivec2(KS) * gid + tid;

	const ivec2 pos1 = ivec2(0, 0);
	const ivec2 pos2 = ivec2(0, 1);
	const ivec2 pos3 = ivec2(0, 2);
	const ivec2 pos4 = ivec2(0, 3);
	const ivec2 pos5 = ivec2(0, 4);
	const ivec2 pos6 = ivec2(0, 5);
	const ivec2 pos7 = ivec2(0, 6);
	const ivec2 pos8 = ivec2(0, 7);
	const ivec2 pos9 = ivec2(0, 8);


	
	
	// imageStore(u_outImg, pixelPos,
	// 	uvec4(255.0 * texelFetch(u_inputTex, pixelPos, 0).rgb, 255u));
	//test imagestore
	imageStore(u_outImg, pos1, uvec4(0u));
	imageStore(u_outImg, pos2, uvec4(255u));
	imageStore(u_outImg, pos3, uvec4(0u));
	imageStore(u_outImg, pos4, uvec4(255u));
	imageStore(u_outImg, pos5, uvec4(0u));
	imageStore(u_outImg, pos6, uvec4(255u));
	imageStore(u_outImg, pos7, uvec4(0u));
	imageStore(u_outImg, pos8, uvec4(255u));
	imageStore(u_outImg, pos9, uvec4(0u));
}

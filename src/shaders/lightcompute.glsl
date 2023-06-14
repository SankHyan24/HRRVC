
#version 430

#define KS 32 // kernel size
layout (local_size_x = KS, local_size_y = KS) in;

uniform sampler2D u_inputTex;
uniform writeonly image2D u_outImg;

#include common/uniforms.glsl
#include common/globals.glsl
#include common/intersection.glsl
#include common/sampling.glsl
#include common/envmap.glsl
#include common/anyhit.glsl
#include common/closest_hit.glsl
#include common/disney.glsl
#include common/lambert.glsl
#include common/pathtrace.glsl
#include sc/lightvertex.glsl


// struct LightPathNode {
//     vec3 position;
//     vec3 radiance;
//     vec3 normal;
//     vec3 ffnormal;
//     vec3 direction; 
//     float eta; 
//     int matID; 
//     int avaliable;
    
//     Material mat;
// };

void main()
{

	const ivec2 gid = ivec2(gl_WorkGroupID.xy);
	const ivec2 tid = ivec2(gl_LocalInvocationID.xy);
	ivec2 pixelPos = ivec2(KS) * gid + tid;

	if(pixelPos[1] == 0){
		float seed = 0.0; 
		sc_constructLightPath(seed); 
		
		for(int j = 0; j < 3; j++){
			imageStore(u_outImg, ivec2(pixelPos[0],j),     vec4(lightVertices[j].position, 0.0));
			imageStore(u_outImg, ivec2(pixelPos[0],j + 3), vec4(lightVertices[j].radiance, 0.0));
			imageStore(u_outImg, ivec2(pixelPos[0],j + 6), vec4(lightVertices[j].normal, 0.0));
			imageStore(u_outImg, ivec2(pixelPos[0],j + 9), vec4(lightVertices[j].ffnormal, 0.0));
			imageStore(u_outImg, ivec2(pixelPos[0],j + 12), vec4(lightVertices[j].direction, 0.0));
			imageStore(u_outImg, ivec2(pixelPos[0],j + 15), vec4(lightVertices[j].eta, 
																 lightVertices[j].matID, 
																 lightVertices[j].avaliable, 0.0));
		}
	}
}

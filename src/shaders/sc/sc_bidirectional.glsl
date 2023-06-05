



void sc_constructLightPath(in float seed ) {
    State state; 
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;
    Light light;

    int index = int(rand() * float(numOfLights)) * 5;

    vec3 position = texelFetch(lightsTex, ivec2(index + 0, 0), 0).xyz;
    vec3 emission = texelFetch(lightsTex, ivec2(index + 1, 0), 0).xyz;
    vec3 u        = texelFetch(lightsTex, ivec2(index + 2, 0), 0).xyz; 
    vec3 v        = texelFetch(lightsTex, ivec2(index + 3, 0), 0).xyz; 
    vec3 params   = texelFetch(lightsTex, ivec2(index + 4, 0), 0).xyz;
    float radius  = params.x;
    float area    = params.y;
    float type    = params.z; // 0->Rect, 1->Sphere, 2->Distant
    
    light = Light(position, emission, u, v, radius, area, type);

    vec3 ro = position;
    if(type == 0.0) {
        ro += light.u * rand() + light.v * rand(); 
    } 
    vec3 rd = randomSphereDirection( seed );
    vec3 color = emission;
    vec3 throughput = vec3(1.0);
 
    for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
        lpNodes[i].position = lpNodes[i].color = lpNodes[i].normal = vec3(0.);
    }
    
    float w = 0.;
    bool hit = false; 
    for( int i=0; i<LIGHTPATHLENGTH; i++ ) {

        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 
        if(hit){
            if(state.isEmitter == true) {
                break;
            }
            GetMaterial(state, r);
            Material mat = state.mat;
            ro = ro + rd*state.hitDist + eps * state.normal;            
            
            vec3 rdi = rd;
            scatterSample.f = DisneySample(state,  -rdi, state.ffnormal, scatterSample.L, scatterSample.pdf);
            color *=mat.baseColor;
            // if(scatterSample.pdf>0)
            // color *= scatterSample.f/scatterSample.pdf; //state.mat.baseColor;//TODO:
            // else break;
            lpNodes[i].position = ro;
            lpNodes[i].color = color;//TODO:
            lpNodes[i].normal = state.normal;
            
            // if (scatterSample.pdf > 0.0)
                // throughput *= scatterSample.f / scatterSample.pdf;
            
            rd = scatterSample.L; 
        } else {
            break;
        }
    }


}

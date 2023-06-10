struct LightPathNode {
    bool avaliable;
    vec3 radiance;
    vec3 position;
    vec3 normal;
    vec3 direction; 
    // for the first node
    // x is the area of the light

    Material mat;
};
LightPathNode lightVertices[10];

vec3 SampleCosWeightedHemisphereDirection(out float pdf){
    float cdf = rand(); // theta in [0, pi/2]
    float theta = acos(1 - cdf);
    float phi = rand() * 2 * PI;
    pdf = sin(theta)*INV_TWO_PI;
    return vec3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));
}



vec3 SampleSphereLightVertex(in Light light, inout LightSampleRec lightSample, out bool hit, inout State state)
{
    float r1=rand();
    float r2=rand();
    float directpdf;

    vec3 sampledDir = UniformSampleHemisphere(r1, r2);
    vec3 lightSurfacePos = light.position + light.radius * sampledDir;
    vec3 lightDirection = SampleCosWeightedHemisphereDirection(directpdf);
    vec3 lightNormal = normalize(lightSurfacePos - light.position);

    vec3 T, B;
    Onb(lightNormal, T, B);
    lightDirection = ToWorld(T, B, lightNormal, lightDirection);

    lightSample.normal = lightNormal;
    lightSample.emission = light.emission*float(numOfLights);
    lightSample.direction = lightDirection;

    // hit point
    Ray r=Ray(lightSurfacePos, lightDirection);
    LightSampleRec tmpLightSample;
    // if hit point is emitter, we should not count it
    hit = ClosestHit(r, state, tmpLightSample);
    if(!hit){
        return vec3(0.0);
    }
    vec3 fhp = state.fhp;
    lightSample.dist = length(fhp - lightSurfacePos);
    lightSample.pdf = lightSample.dist*lightSample.dist*directpdf / (light.area*abs(dot(lightNormal, lightDirection)));
    return lightSurfacePos;
}

vec3 SampleRectLightVertex(in Light light, inout LightSampleRec lightSample, out bool hit, inout State state)
{
    float r1=rand();
    float r2=rand();
    float directpdf;

    vec3 lightSurfacePos = light.position + light.u * r1 + light.v * r2;
    vec3 lightDirection = SampleCosWeightedHemisphereDirection(directpdf);
    vec3 lightNormal = normalize(cross(light.u, light.v));
    
    vec3 T, B;
    Onb(lightNormal, T, B);
    lightDirection = ToWorld(T, B, lightNormal, lightDirection);
    // lightDirection = T*lightDirection.x + B*lightDirection.y + lightNormal*lightDirection.z;

    lightSample.normal = lightNormal;
    lightSample.emission = light.emission*float(numOfLights);
    lightSample.direction = normalize(lightDirection);

   // hit point
    Ray r=Ray(lightSurfacePos, lightSample.direction);
    LightSampleRec tmpLightSample;
    // if hit point is emitter, we should not count it
    hit = ClosestHit(r, state, tmpLightSample);
    if(!hit){
        return lightSurfacePos;
    }
    vec3 fhp = state.fhp; // new node
    lightSample.dist = length(fhp - lightSurfacePos);
    lightSample.pdf = lightSample.dist*lightSample.dist/ (light.area*abs(dot(lightNormal, lightDirection)));
    return lightSurfacePos;
}
vec3 SampleRectLightVertexUniform(in Light light, inout LightSampleRec lightSample, out bool hit, inout State state)
{
    float r1=rand();
    float r2=rand();

    vec3 lightSurfacePos = light.position + light.u * r1 + light.v * r2;
    vec3 lightDirection = UniformSampleHemisphere(rand(), rand());
    vec3 lightNormal = normalize(cross(light.u, light.v));
    
    vec3 T, B;
    Onb(lightNormal, T, B);
    lightDirection = ToWorld(T, B, lightNormal, lightDirection);

    lightSample.normal = lightNormal;
    lightSample.emission = light.emission*float(numOfLights);
    lightSample.direction = normalize(lightDirection);

   // hit point
    Ray r=Ray(lightSurfacePos, lightSample.direction);
    LightSampleRec tmpLightSample;
    // if hit point is emitter, we should not count it
    hit = ClosestHit(r, state, tmpLightSample);
    if(!hit){
        return lightSurfacePos;
    }
    vec3 fhp = state.fhp;
    lightSample.dist = length(fhp - lightSurfacePos);
    lightSample.pdf = lightSample.dist*lightSample.dist / (light.area*abs(dot(lightNormal,lightSample.direction)));
    lightSample.dist = light.area;
    return lightSurfacePos;
}

vec3 SampleDistantLightVertex(in Light light, inout LightSampleRec lightSample, out bool hit, inout State  state)
{
    return vec3(0.0);
}

void sc_constructLightPath(in float seed ) {
    State state; 
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;
    Light light;

    // 1. sample the light
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
    
    // 2. sample the x0 and Theta_x0 (Ray)
    // 2.1. because the light intensity is uniform, we can sample the x0 uniformly
    // 2.2. the Theta_x0 will determine the intensity of the light beam, so we sample it with the cosine distribution
    bool hit;
    vec3 x0;

    if(type == 0)
        x0 = SampleRectLightVertex(light, lightSample, hit, state);
    else if(type == 1)
        x0 = SampleSphereLightVertex(light, lightSample, hit, state);
    else if(type == 2)
        x0 = SampleDistantLightVertex(light, lightSample, hit, state);

    
    vec3 throughput=lightSample.emission;
    // x0 is record as light vertex
    Ray r = Ray(x0, normalize(lightSample.direction));
    lightVertices[0].avaliable = true;
    lightVertices[0].position = x0;
    lightVertices[0].normal = lightSample.normal;
    lightVertices[0].direction.x = params.y; //
    lightVertices[0].radiance = throughput;  // emission is the radiance it received


    if(!hit||lightSample.pdf<=0.0){
        lightVertices[1].avaliable = false;
        return;
    }
    throughput /= lightSample.pdf;
    scatterSample.L = lightSample.direction;
    
    for(int i=1; i<LIGHTPATHLENGTH; i++){
        GetMaterial(state, r);
        vec3 fdirection = r.direction;
        scatterSample.f = DisneySample(state, -r.direction, state.ffnormal, scatterSample.L, scatterSample.pdf);
        r.origin = state.fhp+normalize(scatterSample.L)*EPS;
        r.direction = scatterSample.L;
        lightVertices[i].avaliable = true;
        lightVertices[i].position = r.origin;
        lightVertices[i].normal = state.ffnormal;
        lightVertices[i].direction = fdirection;
        lightVertices[i].radiance = throughput;  // emission is the radiance it received
        lightVertices[i].mat = state.mat;
        vec3 dis = lightVertices[i].position - lightVertices[i-1].position;
        float invDist2 = 1.0/length(dis);
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f*invDist2/ (scatterSample.pdf);
        else
        {
            if(i+1!=LIGHTPATHLENGTH)
                lightVertices[i+1].avaliable = false;
            break;
        }
        if(i+1!=LIGHTPATHLENGTH){
            if(!ClosestHit(r, state, lightSample)){
                    lightVertices[i+1].avaliable = false;
                break;
            }
        }
        // lightSample.direction = scatterSample.L;
    }

}

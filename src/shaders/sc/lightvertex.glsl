
struct LightPathNode {
    vec3 position;
    vec3 radiance;
    vec3 normal;
    vec3 ffnormal;
    vec3 direction; 
    float eta; 
    int matID; 
    int avaliable;
    vec2 texCoord; 
    float matroughness;
    
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

void GetLightPathNodeInfo(inout LightPathNode node, int index){
    int ind = index * 7; 
    vec3 param1 = vec3(texelFetch(lightPathTex, ind + 0).xyz);
    vec3 param2 = vec3(texelFetch(lightPathTex, ind + 1).xyz);
    vec3 param3 = vec3(texelFetch(lightPathTex, ind + 2).xyz);
    vec3 param4 = vec3(texelFetch(lightPathTex, ind + 3).xyz);
    vec3 param5 = vec3(texelFetch(lightPathTex, ind + 4).xyz);
    vec3 param6 = vec3(texelFetch(lightPathTex, ind + 5).xyz);
    vec3 param7 = vec3(texelFetch(lightPathTex, ind + 6).xyz);
    node.position = param1.xyz;
    node.radiance = param2.xyz;
    node.normal = param3.xyz;
    node.ffnormal = param4.xyz;
    node.direction = param5.xyz;
    node.eta = param6.x;
    node.matID = int(param6.y);
    node.avaliable = int(param6.z);
    node.texCoord = param7.xy;
    float matroughness = param7.z;


    int matind = node.matID * 8;
    
    vec4 matparam1 = texelFetch(materialsTex, ivec2(index + 0, 0), 0);
    vec4 matparam2 = texelFetch(materialsTex, ivec2(index + 1, 0), 0);
    vec4 matparam3 = texelFetch(materialsTex, ivec2(index + 2, 0), 0);
    vec4 matparam4 = texelFetch(materialsTex, ivec2(index + 3, 0), 0);
    vec4 matparam5 = texelFetch(materialsTex, ivec2(index + 4, 0), 0);
    vec4 matparam6 = texelFetch(materialsTex, ivec2(index + 5, 0), 0);
    vec4 matparam7 = texelFetch(materialsTex, ivec2(index + 6, 0), 0);
    vec4 matparam8 = texelFetch(materialsTex, ivec2(index + 7, 0), 0);

    node.mat.baseColor          = matparam1.rgb;
    node.mat.anisotropic        = matparam1.w;

    node.mat.emission           = matparam2.rgb;

    node.mat.metallic           = matparam3.x;
    node.mat.roughness          = max(matparam3.y, 0.001);
    node.mat.subsurface         = matparam3.z;
    node.mat.specularTint       = matparam3.w;

    node.mat.sheen              = matparam4.x;
    node.mat.sheenTint          = matparam4.y;
    node.mat.clearcoat          = matparam4.z;
    node.mat.clearcoatRoughness = mix(0.1, 0.001, matparam4.w); // Remapping from gloss to roughness

    node.mat.specTrans          = matparam5.x;
    node.mat.ior                = matparam5.y;
    node.mat.medium.type        = int(matparam5.z);
    node.mat.medium.density     = matparam5.w;

    node.mat.medium.color       = matparam6.rgb;
    node.mat.medium.anisotropy  = clamp(matparam6.w, -0.9, 0.9);

    ivec4 texIDs           = ivec4(matparam7);

    node.mat.opacity            = matparam8.x;
    node.mat.alphaMode          = int(matparam8.y);
    node.mat.alphaCutoff        = matparam8.z;

    if (texIDs.x >= 0)
    {
        vec4 col = texture(textureMapsArrayTex, vec3(node.texCoord, texIDs.x));
        node.mat.baseColor.rgb *= pow(col.rgb, vec3(2.2));
        node.mat.opacity *= col.a;
    }

    // Metallic Roughness Map
    if (texIDs.y >= 0)
    {
        vec2 matRgh = texture(textureMapsArrayTex, vec3(node.texCoord, texIDs.y)).bg;
        node.mat.metallic = matRgh.x;
        node.mat.roughness = max(matRgh.y * matRgh.y, 0.001);
    }

    // Normal Map
    if (texIDs.z >= 0)
    {
        vec3 texNormal = texture(textureMapsArrayTex, vec3(node.texCoord, texIDs.z)).rgb;

#ifdef OPT_OPENGL_NORMALMAP
        texNormal.y = 1.0 - texNormal.y;
#endif
        texNormal = normalize(texNormal * 2.0 - 1.0);

    }

#ifdef OPT_ROUGHNESS_MOLLIFICATION
    if(state.depth > 0)
        node.mat.roughness = max(mix(0.0, matroughness, roughnessMollificationAmt), node.mat.roughness);
#endif

    // Emission Map
    if (texIDs.w >= 0)
        node.mat.emission = pow(texture(textureMapsArrayTex, vec3(node.texCoord, texIDs.w)).rgb, vec3(2.2));

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
    lightSample.dist = light.area;
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
    lightVertices[0].avaliable = 1;
    lightVertices[0].position = x0;
    lightVertices[0].normal = lightSample.normal;
    lightVertices[0].direction.x = params.y; //
    lightVertices[0].radiance = throughput;  // emission is the radiance it received
    lightVertices[0].matID = -1;
    lightVertices[0].eta = 1.0;
    lightVertices[0].avaliable = 1;
    lightVertices[0].ffnormal = lightSample.normal;
    lightVertices[0].texCoord = vec2(0.0);
    lightVertices[0].matroughness = 0.0;

    if(!hit||lightSample.pdf<=0.0){
        lightVertices[1].avaliable = 0;
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
        lightVertices[i].avaliable = 1;
        lightVertices[i].position = r.origin;

        lightVertices[i].normal = state.ffnormal;
        lightVertices[i].direction = fdirection;
        lightVertices[i].radiance = throughput;  // emission is the radiance it received
        lightVertices[i].mat = state.mat;
        lightVertices[i].matID = state.matID;
        lightVertices[i].eta = state.eta;
        lightVertices[i].ffnormal = state.ffnormal;
        lightVertices[i].texCoord = state.texCoord;
        lightVertices[i].matroughness = state.mat.roughness;

        vec3 dis = lightVertices[i].position - lightVertices[i-1].position;
        float invDist2 = 1.0/length(dis);
        if (scatterSample.pdf > 0.0){
            throughput *= scatterSample.f/scatterSample.pdf;
        }
        else
        {
            if(i+1!=LIGHTPATHLENGTH)
                lightVertices[i+1].avaliable = 0;
            break;
        }
        if(i+1!=LIGHTPATHLENGTH){
            if(!ClosestHit(r, state, lightSample)){
                    lightVertices[i+1].avaliable = 0;
                break;
            }
        }
        // lightSample.direction = scatterSample.L;
    }
}



struct LinearBVHNode{
    vec3 pmin; 
    vec3 pmax;
    int primitivesOffsetOrSecondChildOffset; // leaf or interior
    int nPrimitives; // 0 -> interior node
    int axis; // interior node: xyz
};

float IntersectPD(in vec3 ro, in vec3 rd, in vec3 invDir, in ivec3 dirIsNeg, in float scale, in vec3 boundmin, in vec3 boundmax){
    float tMin = (boundmin.x - ro.x) * invDir.x; //2603 line
    float tMax = (boundmax.x - ro.x) * invDir.x;
    float tyMin = (boundmin.y - ro.y) * invDir.y;
    float tyMax = (boundmax.y - ro.y) * invDir.y;

    tMax *= scale;
    tyMax *= scale;
    if (tMin > tyMax || tyMin > tMax)
        return -1.0;
    if (tyMin > tMin)
        tMin = tyMin;
    if (tyMax < tMax)
        tMax = tyMax;

    // Check for ray intersection against $z$ slab
    float tzMin = (boundmin.z - ro.z) * invDir.z;
    float tzMax = (boundmax.z - ro.z) * invDir.z;

    // Update _tzMax_ to ensure robust bounds intersection
    // tzMax *= 1 + 2. * gamma(3);
    tzMax *= scale;
    if (tMin > tzMax || tzMin > tMax)
        return -1.0;
    if (tzMin > tMin)
        tMin = tzMin;
    if (tzMax < tMax)
        tMax = tzMax;
    return tMax;
}

//2632
float gamma(in int n){
    return (n * EPS_GAMMA ) / (1 - n * EPS_GAMMA);
}

void fetchLightBVHnode(inout LinearBVHNode node, in int index){
    node.pmin = texelFetch(lightPathBVHTex, index * 3 + 0).xyz;
    node.pmax = texelFetch(lightPathBVHTex, index * 3 + 1).xyz;
    node.primitivesOffsetOrSecondChildOffset = int(texelFetch(lightPathBVHTex, index * 3 + 2).x);
    node.nPrimitives = int(texelFetch(lightPathBVHTex, index * 3 + 2).y);
    node.axis = int(texelFetch(lightPathBVHTex, index * 3 + 2).z);
}
// lightPathBVHTex
// vec3 boundpmin = texelFetch(lightPathBVHTex, leftIndex * 3 + 0).xyz
// bool IntersectPB(in vec3 ro, in vec3 rd,  int depth = 1, float scale = 1 + 2 * gamma(3)) 
bool IntersectPB(in vec3 ro, in vec3 rd, in int depth, in float scale) {
    
    vec3 invDir = vec3(1.0 / rd.x, 1.0 / rd.y, 1.0 / rd.z);
    ivec3 dirIsNeg = ivec3(
        int(invDir.x < 0),
        int(invDir.y < 0),
        int(invDir.z < 0)
    );

    int nodesToVisit[1024]; //stack
    for(int i = 0; i < 1024; i++){
        nodesToVisit[i] = 0;
    }

    nodesToVisit[0] = 0;
    int toVisitOffset = 1;
    int currentNodeIndex = 0;
    int leftnode_index = 1;
    int rightnode_index;
    int currentdepth = 0;
    while (toVisitOffset != 0){
        LinearBVHNode bvhnode; 
        fetchLightBVHnode(bvhnode, currentNodeIndex); 
        if(bvhnode.nPrimitives > 0)// 
        {
            currentdepth += 1; 
            if (currentdepth == depth)
            {
                break;
            }
        }
        else{
            leftnode_index = currentNodeIndex + 1;
            rightnode_index = bvhnode.primitivesOffsetOrSecondChildOffset;

            LinearBVHNode leftnode; 
            LinearBVHNode rightnode;
            fetchLightBVHnode(leftnode, leftnode_index);
            fetchLightBVHnode(rightnode, rightnode_index);
            float leftInsect_ = IntersectPD(ro, rd, invDir, dirIsNeg, scale, leftnode.pmin, leftnode.pmax);
            float rightInsect_ = IntersectPD(ro, rd, invDir, dirIsNeg, scale, rightnode.pmin, rightnode.pmax);
            bool leftInsect = bool(leftInsect_ > 0 ? 1 : 0);
            bool rightInsect = bool(rightInsect_ > 0 ? 1 : 0);
            if(leftInsect && !rightInsect){
                nodesToVisit[++toVisitOffset] = leftnode_index;
            }
            else if(!leftInsect && rightInsect){
                nodesToVisit[++toVisitOffset] = rightnode_index;
            }
            else if(leftInsect && rightInsect){
                if (leftInsect_ < rightInsect_)
                {
                    nodesToVisit[++toVisitOffset] = rightnode_index;
                    nodesToVisit[++toVisitOffset] = leftnode_index;
                }
                else
                {
                    nodesToVisit[++toVisitOffset] = leftnode_index;
                    nodesToVisit[++toVisitOffset] = rightnode_index;
                }
            }
        }
        currentNodeIndex = nodesToVisit[toVisitOffset--];
    }
    return false; 
}


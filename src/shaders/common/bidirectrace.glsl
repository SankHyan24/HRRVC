
#define eps 0.00001
// #define LIGHTPATHLENGTH 3
// #define EYEPATHLENGTH 3


vec3 cosWeightedRandomHemisphereDirection( const vec3 n) {
  	vec2 r = vec2(rand(), rand());
    
	vec3  uu = normalize( cross( n, vec3(0.0,1.0,1.0) ) );
	vec3  vv = cross( uu, n );
	
	float ra = sqrt(r.y);
	float rx = ra*cos(6.2831*r.x); 
	float ry = ra*sin(6.2831*r.x);
	float rz = sqrt( 1.0-r.y );
	vec3  rr = vec3( rx*uu + ry*vv + rz*n );
    
    return normalize( rr );
}

vec3 randomSphereDirection(inout float seed) {
    vec2 h = vec2(rand(), rand());
    float phi = h.y;
	return vec3(sqrt(1.-h.x*h.x)*vec2(sin(phi),cos(phi)),h.x);
}

vec3 randomHemisphereDirection( const vec3 n, inout float seed ) {
	vec3 dr = randomSphereDirection(seed);
	return dot(dr,n) * dr;
}



//-----------------------------------------------------
// eyepath
//-----------------------------------------------------
float misWeightCRecord[100];
float misWeightLRecord[100];
bool if_pos_near(vec3 a, vec3 b){
    return (abs(a.x-b.x)<0.01 && abs(a.y-b.y)<0.01 && abs(a.z-b.z)<0.01);
}

// naive bidirectional path tracing
vec4 traceEyePath( in Ray ray_) {
    vec3 ro = ray_.origin;
    vec3 rd = ray_.direction;

    State state; 
    vec3 radiance = vec3(0.);
    vec3 throughput = vec3(1.); 
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;
    Light light;


    bool hit = false; 
    bool surfaceScatter = false;// if it is from a surface scatter
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        
        vec3 curnormal;
        Material mat; 

        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 

        // if not hit, return background color
        if(!hit){
            return vec4(radiance * throughput, 1.0);
        }

        // if hit light, return light color
        if(state.isEmitter){
            float misWeight = 1.0;
            if (j > 0){
                misWeight = PowerHeuristic(scatterSample.pdf, lightSample.pdf);
                misWeightCRecord[j] = misWeight;
            }
            radiance +=misWeight* throughput * lightSample.emission;
        }
        
         // 2794
        GetMaterial(state, r);
        mat = state.mat;
        curnormal = state.ffnormal;
        // Bidirectional path tracing
#ifdef OPT_BDPT
        {
            // Vertex connection
            State shadowState;
            Material eyeMat = mat;
            vec3 eyePos = ro;
            vec3 eyeNormal = curnormal;
            vec3 radianceBidirectional = vec3(0.0);
            int sampleCounter = 0;
            for( int i=1; i<LIGHTPATHLENGTH; ++i ) {
                if(lightVertices[i].avaliable == 0) break;
                // if(if_pos_near(lightVertices[i].position, eyePos))
                // {
                //     radiance = lightVertices[i].radiance;
                //     return vec4(radiance*10, 1.0);
                // }
                vec3 lightPos = lightVertices[i].position;
                vec3 lightNormal = lightVertices[i].normal;
                vec3 lightRadiance = lightVertices[i].radiance;
                vec3 lightDirection = lightVertices[i].direction;
                Material lightMat = lightVertices[i].mat;
                // eye vertex information

                // cosAtLight, cosAtEye
                float eyelightDist = length(lightPos - eyePos);
                vec3 eye2lightDir = normalize(lightPos - eyePos);
                vec3 light2eyeDir = -eye2lightDir;

                float cosAtLight = dot(lightNormal, light2eyeDir);
                float cosAtEye = dot(eyeNormal, eye2lightDir);

                if(cosAtEye < 0.0 || cosAtLight < 0.0)
                     continue; // culling invisible light
                // shadow ray
                bool shadowHit = true;
                Ray shadowRay = Ray(eyePos, eye2lightDir);
                bool inShadow = AnyHit(shadowRay, eyelightDist- eps);
                shadowHit = !inShadow;

                if(!shadowHit)continue;
                // calculate weight
                shadowState.mat = lightMat;
                shadowState.eta = lightMat.ior;
                float lightPdf, eyePdf;
                vec3 lightBRDF = DisneyEval(shadowState, -lightDirection, lightNormal, light2eyeDir, lightPdf);
                vec3 eyeBRDF = DisneyEval(state, -r.direction, curnormal, eye2lightDir, eyePdf);
                if(lightPdf < 0.0 || eyePdf < 0.0) continue;
                vec3 connectionRadiance = throughput * lightRadiance * eyeBRDF * lightBRDF  * cosAtLight * cosAtEye /(lightPdf*eyePdf);

#ifdef OPT_MIS_BDPT
                float localWeight = eyePdf * lightPdf * invDist2 * cosAtEye * cosAtLight;
                float misWeight = PowerHeuristic(localWeight, lightSample.pdf);
#else
                float misWeight = 1.0/(2.0+i+j);
#endif
                if(connectionRadiance.x > 0.0 && connectionRadiance.y > 0.0 && connectionRadiance.z > 0.0)
                {
                    sampleCounter++;
                    radianceBidirectional+=connectionRadiance*misWeight;
                }
            }
            if(sampleCounter!=0)
                radiance += radianceBidirectional;
        }
#endif
        radiance += DirectLight(r,state,true)*throughput;


        scatterSample.f = DisneySample(state,  -r.direction, curnormal, scatterSample.L, scatterSample.pdf);
        rd = scatterSample.L;
        ro = state.fhp + rd*EPS;
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;
        else break; 
        // break;
#ifdef OPT_RR
        // Russian roulette
        // if (state.depth >= OPT_RR_DEPTH)
        // {
        //     float q = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001, 0.95);
        //     if (rand() > q)
        //         break;
        //     throughput /= q;
        // }
#endif
    }  
    
    return vec4(radiance, 1.0);
}


vec4 sc_traceEyePath( in Ray ray_) {
    vec3 ro = ray_.origin;
    vec3 rd = ray_.direction;

    State state; 
    vec3 radiance = vec3(0.);
    vec3 throughput = vec3(1.); 
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;
    Light light;
    

    bool hit = false; 
    vec3 curnormal = rd;
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        
        Material mat; 

        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 

        // if not hit, return background color
        if(!hit){
            break;
        }

        // if hit light, return light color
        if(state.isEmitter){
            float misWeight = 1.0;
            if (j > 0){
                misWeight = PowerHeuristic(scatterSample.pdf, lightSample.pdf);
            }
            radiance +=misWeight* throughput * lightSample.emission;
            break;
        }



        GetMaterial(state, r);
        mat = state.mat;
        curnormal = state.ffnormal;
        // Bidirectional path tracing

        scatterSample.f = DisneySample(state,  -r.direction, curnormal, scatterSample.L, scatterSample.pdf);
        rd = scatterSample.L;
        ro = state.fhp + normalize(rd)*EPS;
        
#ifdef OPT_BDPT
        {
            // Vertex connection
            Material eyeMat = mat;
            vec3 eyeNormal = curnormal;
            // vec3 eyePos = state.fhp - normalize(rd)*EPS;
            vec3 eyePos = ro;
            vec3 radianceBidirectional = vec3(0.0);
            int sampleCounter = 0;

                for( int i=1; i<LIGHTPATHLENGTH; ++i ) {
                if(lightVertices[i].avaliable == 0) break;
                // if(if_pos_near(lightVertices[i].position, eyePos))
                // {
                //     radiance += lightVertices[i].radiance*10;
                // }

                vec3 lightPos = lightVertices[i].position;
                vec3 lightNormal = normalize(lightVertices[i].normal);
                vec3 lightRadiance = lightVertices[i].radiance;
                vec3 lightDirection = lightVertices[i].direction;
                Material lightMat = lightVertices[i].mat;
                // eye vertex information

                // cosAtLight, cosAtEye
                float eyelightDist = length(lightPos - eyePos);
                vec3 eye2lightDir = normalize(lightPos - eyePos);
                vec3 light2eyeDir = -eye2lightDir;

                float cosAtLight = dot(lightNormal, light2eyeDir);
                float cosAtEye = dot(eyeNormal, eye2lightDir);

                if(cosAtEye < 0.0 || cosAtLight < 0.0) continue;

                // shadow ray
                Ray shadowRay = Ray(eyePos, eye2lightDir);
                if(AnyHit(shadowRay, eyelightDist- EPS))continue;

                // calculate weight
                float lightPdf, eyePdf, Dist2=(eyelightDist*eyelightDist);
                State shadowState;
                shadowState.mat = lightMat;
                shadowState.eta = lightMat.ior;
                vec3 lightBRDF = DisneyEval(shadowState, -lightDirection, lightNormal, light2eyeDir, lightPdf);
                vec3 eyeBRDF = DisneyEval(state, -r.direction, eyeNormal, eye2lightDir, eyePdf);
                if(i==0){
                    float lightArea = lightVertices[i].direction.x;
                    lightPdf = 1.0/Dist2;
                    // lightPdf = 1.0;
                    lightBRDF = vec3(1.0)*lightArea;
                }
                if(lightPdf <= 0.0 ) continue; 
                if( eyePdf <= 0.0) continue;
                // if(eyeBRDF.x <= 0.0 || eyeBRDF.y <= 0.0 || eyeBRDF.z <= 0.0) continue; // lp=3没问题
                // if(lightBRDF.x <= 0.0 || lightBRDF.y <= 0.0 || lightBRDF.z <= 0.0) continue; 
                // vec3 connectionRadiance = throughput * lightRadiance ;
                vec3 connectionRadiance = throughput * lightRadiance * eyeBRDF * lightBRDF * cosAtLight * cosAtEye *lightPdf /(eyePdf) ;
                
#ifdef OPT_MIS_BDPT
                float localWeight = eyePdf * lightPdf * cosAtEye * cosAtLight;
                float misWeight = PowerHeuristic(localWeight, lightSample.pdf);
#else
                float misWeight = 1.0/(2.0+i+j)/LIGHTPATHLENGTH;
#endif
                if(connectionRadiance.x > 0.0 && connectionRadiance.y > 0.0 && connectionRadiance.z > 0.0)
                {
                    sampleCounter++;
                    radianceBidirectional+=connectionRadiance*misWeight;
                }
            }
            // if(sampleCounter!=0)
            // radiance += radianceBidirectional/sampleCounter; ;
            radiance += radianceBidirectional;
        }
#endif

        radiance += DirectLight(r,state,true)*throughput;

        
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;
        else break; 
        // break;
#ifdef OPT_RR
        if (state.depth >= OPT_RR_DEPTH)
        {
            float q = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001, 0.95);
            if (rand() > q)
                break;
            throughput /= q;
        }
#endif
    }  
    
    return vec4(radiance, 1.0);
}

// int depth = 1;
// float scale = 1 + 2 * gamma(3);

bool sc_intersectBB(in vec3 ro, in vec3 rd, in float range, in LinearBVHNode bvh,inout float dist){
    vec3 invDir = vec3(1.0 / rd.x, 1.0 / rd.y, 1.0 / rd.z);
    ivec3 dirIsNeg = ivec3(
        int(invDir.x < 0),
        int(invDir.y < 0),
        int(invDir.z < 0)
    );
    vec3 boundmin = bvh.pmin; 
    vec3 boundmax = bvh.pmax;

    float txMin = (boundmin.x - ro.x) * invDir.x;
    float txMax = (boundmax.x - ro.x) * invDir.x;

    for(int i=0;i<3;i++){
        if(abs(rd[i])<0.0001){
            if(ro[i]<boundmin[i] || ro[i]>boundmax[i]) 
            // continue;
            return false;
        }
        else{
            float ood = 1.0 / rd[i];
            float t1 = (boundmin[i] - ro[i]) * ood;
            float t2 = (boundmax[i] - ro[i]) * ood;
            if(t1>t2){
                float temp = t1;
                t1 = t2;
                t2 = temp;
            }
            txMin = max(txMin, t1);
            txMax = min(txMax, t2);
            if(txMin>txMax) return false;
        }
    }
    vec3 center;
    center.x = (boundmin.x + boundmax.x) / 2.0;
    center.y = (boundmin.y + boundmax.y) / 2.0;
    center.z = (boundmin.z + boundmax.z) / 2.0;
    dist = length(center - ro);
    return true;
}


bool intersectBB(in vec3 ro, in vec3 rd, in float range, in LinearBVHNode bvh){
    vec3 invDir = vec3(1.0 / rd.x, 1.0 / rd.y, 1.0 / rd.z);
    ivec3 dirIsNeg = ivec3(
        int(invDir.x < 0),
        int(invDir.y < 0),
        int(invDir.z < 0)
    );
    vec3 boundmin = bvh.pmin; 
    vec3 boundmax = bvh.pmax;

    float tMin = (boundmin.x - ro.x) * invDir.x; //2603 line
    float tMax = (boundmax.x - ro.x) * invDir.x;
    float tyMin = (boundmin.y - ro.y) * invDir.y;
    float tyMax = (boundmax.y - ro.y) * invDir.y;

    float scale = 1 + 2 * gamma(3);
    tMax *= scale;
    tyMax *= scale;

    if (tMin > tyMax || tyMin > tMax)
        return false;
    if (tyMin > tMin)
        tMin = tyMin;
    if (tyMax < tMax)
        tMax = tyMax;

    // Check for ray intersection against $z$ slab
    float tzMin = (boundmin.z - ro.z) * invDir.z;
    float tzMax = (boundmax.z - ro.z) * invDir.z;

    tzMax *= scale;
    if (tMin > tzMax || tzMin > tMax)
        return false;
    if (tzMin > tMin)
        tMin = tzMin;
    if (tzMax < tMax)
        tMax = tzMax;

    return (tMax > 0) && (tMin < range);
}

struct BVHNodeRecord{
    int nodeIndex;
    float randomNumberMin;
    float infimum;
};

struct EyeNode{
    vec3 Pos;
    vec3 Dir;
    vec3 Normal;
    Material mat;
};

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
    
    vec4 matparam1 = texelFetch(materialsTex, ivec2(matind + 0, 0), 0);
    vec4 matparam2 = texelFetch(materialsTex, ivec2(matind + 1, 0), 0);
    vec4 matparam3 = texelFetch(materialsTex, ivec2(matind + 2, 0), 0);
    vec4 matparam4 = texelFetch(materialsTex, ivec2(matind + 3, 0), 0);
    vec4 matparam5 = texelFetch(materialsTex, ivec2(matind + 4, 0), 0);
    vec4 matparam6 = texelFetch(materialsTex, ivec2(matind + 5, 0), 0);
    vec4 matparam7 = texelFetch(materialsTex, ivec2(matind + 6, 0), 0);
    vec4 matparam8 = texelFetch(materialsTex, ivec2(matind + 7, 0), 0);

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


#ifdef OPT_ROUGHNESS_MOLLIFICATION
    if(state.depth > 0)
        node.mat.roughness = max(mix(0.0, matroughness, roughnessMollificationAmt), node.mat.roughness);
#endif

    // Emission Map
    if (texIDs.w >= 0)
        node.mat.emission = pow(texture(textureMapsArrayTex, vec3(node.texCoord, texIDs.w)).rgb, vec3(2.2));

}

void fetchLightBVHnode(inout LinearBVHNode node, in int index){
    node.pmin = texelFetch(lightPathBVHTex, index * 3 + 0).xyz;// 2649
    node.pmax = texelFetch(lightPathBVHTex, index * 3 + 1).xyz;
    node.primitivesOffsetOrSecondChildOffset = int(texelFetch(lightPathBVHTex, index * 3 + 2).x);
    node.nPrimitives = int(texelFetch(lightPathBVHTex, index * 3 + 2).y);
    node.axis = int(texelFetch(lightPathBVHTex, index * 3 + 2).z);
}

void fetchLightBVHnodeIndex(inout int indexout, in int index){
    int offset  =   index / 3; 
    int rem     =   index % 3;
    if(rem == 0){
        indexout = int(texelFetch(lightPathBVHIndexTex, offset).x);
    }
    else if(rem == 1){
        indexout = int(texelFetch(lightPathBVHIndexTex, offset).y);
    }
    else if(rem == 2){
        indexout = int(texelFetch(lightPathBVHIndexTex, offset).z);
    }
}

vec3 VertexConnect(LightPathNode lightnode, EyeNode eyenode){
    vec3 connectionRadiance = vec3(0.0);
    if(lightnode.avaliable == 0) return connectionRadiance;
    vec3 lightRadiance = lightnode.radiance;
    vec3 lightPos = lightnode.position  ;
    vec3 lightNormal = normalize(lightnode.normal);
    vec3 lightDirection = lightnode.direction;
    Material lightMat = lightnode.mat;
    // eye vertex information
    vec3 eyePos = eyenode.Pos;
    vec3 eyeNormal = eyenode.Normal;
    vec3 eyeDirection = eyenode.Dir;
    Material eyeMat = eyenode.mat;
    // return lightRadiance;


    vec3 eye2lightDir = normalize(lightPos - eyePos);
    vec3 light2eyeDir = -eye2lightDir;

    // cosine detection
    float cosAtLight = dot(lightNormal, light2eyeDir);
    float cosAtEye = dot(eyeNormal, eye2lightDir);
    if(cosAtEye<0.0||cosAtLight<0.0) return connectionRadiance;
    if(cosAtEye*cosAtLight<EPS) return connectionRadiance;

    // shadow ray test
    Ray shadowRay = Ray(eyePos, eye2lightDir);
    float dist = length (lightPos - eyePos);
    // if(AnyHit(shadowRay, dist- EPS))return connectionRadiance;

    State shadowState;
    shadowState.mat = lightMat;
    shadowState.eta = lightMat.ior;
    State eyeState;
    eyeState.mat = eyeMat;
    eyeState.eta = eyeMat.ior;

    // get brdf
    float lightPdf, eyePdf, Dist2 = dist * dist;
    vec3 lightBRDF = DisneyEval(shadowState, -lightDirection, lightNormal, light2eyeDir, lightPdf);
    vec3 eyeBRDF = DisneyEval(eyeState, -eyeDirection, eyeNormal, eye2lightDir, eyePdf);

    // the first light cannot be the vertex!
    if(lightnode.matID == -1){
        float lightArea = lightnode.direction.x;
        lightPdf = 1.0/Dist2;
        lightBRDF = vec3(1.0)*lightArea;
    }

    if( eyePdf <= 0.0) return connectionRadiance;
    connectionRadiance += lightRadiance *lightBRDF*eyeBRDF*lightPdf*cosAtEye*cosAtLight/eyePdf ;

    return connectionRadiance;
    return lightRadiance;

}

vec4 HRRVC( in Ray ray_) { 
    vec3 ro = ray_.origin; 
    vec3 rd = ray_.direction;

    State state; 
    vec3 radiance = vec3(0.);
    vec3 throughput = vec3(1.); 
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;
    Light light;
    
    bool hit = false; 
    vec3 curnormal = rd;
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        

        Material mat; 
        
        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 

        // if not hit, return background color
        if(!hit){
            break;
        }

        // if hit light, return light color
        if(state.isEmitter){
            float misWeight = 1.0;
            if (j > 0){
                misWeight = PowerHeuristic(scatterSample.pdf, lightSample.pdf);
            }
            radiance += misWeight * throughput * lightSample.emission;
            break;
        }

        GetMaterial(state, r);
        mat = state.mat;
        curnormal = state.ffnormal;
        // Sample BRDF
        scatterSample.f = DisneySample(state, -r.direction, curnormal, scatterSample.L, scatterSample.pdf);
        rd = scatterSample.L;
        ro = state.fhp + normalize(rd)*EPS;

        EyeNode eye_;
        eye_.Dir = rd;
        eye_.Pos = ro;
        eye_.Normal = curnormal;
        eye_.mat = mat;



        vec3 invDir = vec3(1.0 / rd.x, 1.0 / rd.y, 1.0 / rd.z);
        ivec3 dirIsNeg = ivec3(
            int(invDir.x < 0),
            int(invDir.y < 0),
            int(invDir.z < 0)
        );
        
        // intersect bvh node

        BVHNodeRecord nodesToVisit[1024]; //stack
        for(int i = 0; i < 1024; i++){
            nodesToVisit[i].nodeIndex = -1;
            nodesToVisit[i].randomNumberMin = -1.0;
            nodesToVisit[i].infimum = -1.0;
        }

        int stackLevel = 0;
        int currentNodeIndex = 0;
        int leftnode_index = 1;
        int rightnode_index;
        int currentdepth = 0;

        // root node
        LinearBVHNode bvhnode; 
        fetchLightBVHnode(bvhnode, currentNodeIndex); 


        float randomNumberMin = rand()/ bvhnode.nPrimitives ;
        float infimum = 1.0f / bvhnode.nPrimitives;

        vec3 result = vec3(0.0);

        // constant value in R(omega; z. xi)
        float ConstantValInGenRange = 0.001; 

        
        int counter=0;
        int test_lvl=2;
        while(true){
            counter+=1;

            // LinearBVHNode bvhnode; 
            fetchLightBVHnode(bvhnode, currentNodeIndex); 
            float dist_y_z_L;
            float dist_y_z_R;
            int use_L;
            
            if(bvhnode.axis != 3) // bvh node is internal node
            {
                // test pass
                LinearBVHNode childL;
                LinearBVHNode childR;
                leftnode_index = currentNodeIndex + 1; 
                rightnode_index = bvhnode.primitivesOffsetOrSecondChildOffset; 
                fetchLightBVHnode(childL, leftnode_index); 
                fetchLightBVHnode(childR, rightnode_index);
                

                float rfloat = rand(); 
                uint ruint = randint(); 
                int totalLeafCount = bvhnode.nPrimitives; // in first level is 6000
                
                bool transmitToLeft = ruint % uint(totalLeafCount) < uint(childL.nPrimitives);
                int leafCount = transmitToLeft ? childR.nPrimitives: childL.nPrimitives; 
                float stratumSize = (1.0f - infimum ) / leafCount ;
                float supremum = infimum + stratumSize ;
                float newRandomNumberMin = infimum + stratumSize * rfloat ;
                
                float randomNumberMinL = transmitToLeft ? randomNumberMin : newRandomNumberMin ;
                float randomNumberMinR = transmitToLeft ? newRandomNumberMin : randomNumberMin ;

                // TODO 
                float AcceptRangeL = sqrt(ConstantValInGenRange * sqrt(dot(scatterSample.f, scatterSample.f)) / randomNumberMinL);
                float AcceptRangeR = sqrt(ConstantValInGenRange * sqrt(dot(scatterSample.f, scatterSample.f)) / randomNumberMinR);

                bool hitL = sc_intersectBB(ro, rd, AcceptRangeL, childL, dist_y_z_L);
                bool hitR = sc_intersectBB(ro, rd, AcceptRangeR, childR, dist_y_z_R);
                if(hitL && hitR) {
                    currentNodeIndex = transmitToLeft ? leftnode_index : rightnode_index ;
                    use_L = transmitToLeft ? 1 : 0 ;
                    nodesToVisit[ stackLevel ].nodeIndex = transmitToLeft ? rightnode_index : leftnode_index  ;
                    nodesToVisit[ stackLevel ].randomNumberMin = newRandomNumberMin ;
                    nodesToVisit[ stackLevel ].infimum = supremum ;
                    ++ stackLevel ;
                    continue ;
                } else if(hitL) {
                    currentNodeIndex = leftnode_index ;
                    use_L = 1 ;
                    if(! transmitToLeft ) {
                        randomNumberMin = newRandomNumberMin ;
                        infimum = supremum ;
                    }
                    continue ;
                } 
                else if(hitR) {
                    currentNodeIndex = rightnode_index ;
                    use_L = 0 ;
                    if( transmitToLeft ) {
                        randomNumberMin = newRandomNumberMin ;
                        infimum = supremum ;
                    }
                    continue ;
                } 
            }
            else // bvh node is leaf node
            {   
                // sc :cannot enter this block
                // RR
                #ifdef OPT_RR
                float dist_=use_L==1?dist_y_z_L:dist_y_z_R;
                float p_y_z = min(1.0f, ConstantValInGenRange * sqrt(dot(scatterSample.f, scatterSample.f)) /dist_ );
                if(randomNumberMin > p_y_z) break;
                #endif

                int leafIndex = currentNodeIndex; 
                int firstPrimOffset = bvhnode.primitivesOffsetOrSecondChildOffset;
                int primCount = bvhnode.nPrimitives;

                // current bvh node = bvhnode
                int index; 
                
                for(int i = 0; i < primCount; i++){
                    LightPathNode node; 
                    fetchLightBVHnodeIndex(index, firstPrimOffset + i); 
                    GetLightPathNodeInfo(node, index); 
                    // if(index%LIGHTPATHLENGTH==0)
                    // continue;

                    float misWeight=1.0/(2.0+j+(index)%LIGHTPATHLENGTH)/12000.0;

                    #ifdef OPT_RR
                    float weight=misWeight/(p_y_z*sqrt(dot(scatterSample.f, scatterSample.f)));
                    #else
                    float weight=misWeight;
                    #endif

                    vec3 connect_radiance = VertexConnect(node, eye_)*weight*throughput;

                    if(connect_radiance.x>0.0&&connect_radiance.y>0.0&&connect_radiance.z>0.0)
                        radiance +=  connect_radiance ;
                }
                // radiance /= sqrt(float(primCount));
            }
            if(stackLevel == 0) break;
            
            stackLevel--;
            BVHNodeRecord stackElement = nodesToVisit[ stackLevel ];
            
            currentNodeIndex = stackElement.nodeIndex;
            randomNumberMin = stackElement.randomNumberMin;
            infimum = stackElement.infimum;
            // out result 
        }
        radiance += DirectLight(r,state,true)*throughput;

        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;
        else break; 
#ifdef OPT_RR
        // Russian roulette

        // if (j >= OPT_RR_DEPTH)
        // {
        //     float q = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001, 0.95);
        //     if (rand() > q)
        //         break;
        //     throughput /= q;
        // }
#endif
    }
    return vec4(radiance, 1.0); 
}


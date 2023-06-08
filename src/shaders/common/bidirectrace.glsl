
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
int light_index = 0;
void recordLWeight(float weight)
{
    misWeightLRecord[light_index] = weight;
    light_index++;
}

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
            for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
                if(lightVertices[i].avaliable == false) break;
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
                float lightPdf, eyePdf, invDist2=1.0/(eyelightDist*eyelightDist);
                vec3 lightBRDF = DisneyEval(shadowState, -lightDirection, lightNormal, light2eyeDir, lightPdf);
                vec3 eyeBRDF = DisneyEval(state, -r.direction, curnormal, eye2lightDir, eyePdf);
                if(lightPdf < 0.0 || eyePdf < 0.0) continue;
                vec3 connectionRadiance = throughput * lightRadiance * eyeBRDF * lightBRDF  * cosAtLight * cosAtEye * invDist2;

#ifdef OPT_MIS_BDPT
                float localWeight = eyePdf * lightPdf * invDist2 * cosAtEye * cosAtLight;
                float misWeight = PowerHeuristic(localWeight, lightSample.pdf);
#else
                float misWeight = 1.0/(2.0+i+j);
#endif
                sampleCounter++;
                radianceBidirectional+=connectionRadiance*misWeight;
            }
            if(sampleCounter!=0)
            radiance += radianceBidirectional ;
        }
#endif
        radiance += DirectLight(r,state,true)*throughput;
        // if(light_index!=j){//sc
        //     return vec4(vec3(100.0), 1.0);
        // }

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


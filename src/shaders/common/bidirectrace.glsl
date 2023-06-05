#define eps 0.00001
#define LIGHTPATHLENGTH 10
#define EYEPATHLENGTH 2


vec3 cosWeightedRandomHemisphereDirection( const vec3 n, inout float seed ) {
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

struct LightPathNode {
    vec3 color;
    vec3 position;
    vec3 normal;
};

LightPathNode lpNodes[LIGHTPATHLENGTH];

void constructLightPath( inout float seed ) {
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

//-----------------------------------------------------
// eyepath
//-----------------------------------------------------

float getWeightForPath( int e, int l ) {
    return float(e + l + 2);
}

vec4 traceEyePath( in Ray ray_, const in bool bidirectTrace ) {
    vec3 ro = ray_.origin;
    vec3 rd = ray_.direction;

    State state; 
    vec3 radiance = vec3(0.);
    vec3 throughput = vec3(1.); 
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

    bool hit = false; 
    bool surfaceScatter = false;// if it is from a surface scatter
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        
        vec3 curnormal;

        Ray r = Ray(ro, rd); 
        vec3 nrd = normalize(rd); 
        hit = ClosestHit(r, state, lightSample); 
        Material mat; 

        // if not hit, return background color
        if(!hit){
            return vec4(radiance * throughput, 1.0);
        }

        // if hit light, return light color
        if(state.isEmitter){
            float misWeight = 1.0;
            if (j > 0)
                misWeight = PowerHeuristic(scatterSample.pdf, lightSample.pdf);
            radiance +=misWeight* throughput * lightSample.emission;
        }
        

        GetMaterial(state, r);
        mat = state.mat;
        curnormal = state.ffnormal;
        // update current position
        if( bidirectTrace  ) {
                for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
                    float throughputForOneLight = 1.0; 
                    // path of (j+1) eyepath-nodes, and i+2 lightpath-nodes.
                    vec3 lp = lpNodes[i].position - ro;
                    float lenlp = length(lp);
                    vec3 lpn = normalize( lp );
                    vec3 lc = lpNodes[i].color;

                    float pass = 
                        clamp( dot( lpn, curnormal ), 0.0, 1.) 
                        * clamp( dot( -lpn, lpNodes[i].normal ), 0., 1.)
                        * clamp(1. / dot(lp, lp) * 0.01, 0., 1.); 
                    
                    if(i > 0){
                        if(pass < 0.01){
                            continue; 
                        }
                    }
                
                    if(true) {
                        float weight = 
                                 clamp( dot( lpn, curnormal ), 0.0, 1.) 
                               * clamp( dot( -lpn, lpNodes[i].normal ), 0., 1.)
                               * clamp(1. / dot(lp, lp), 0., 1.)

                            ;
                        radiance += lc * (1-state.mat.metallic) *weight / getWeightForPath(j,i) * throughput / LIGHTPATHLENGTH; 
                    }
            }
        }
        radiance += DirectLight(r,state,true)*throughput;

        scatterSample.f = DisneySample(state,  -r.direction, curnormal, scatterSample.L, scatterSample.pdf);
        rd = scatterSample.L;
        ro = state.fhp + rd*EPS;
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;
        else break; 

        //RR 
        // if (j >= 2) {
        //     float rr = rand();
        //     float p = 1.1 - 0.1 * j; 
        //     if (rr > p) {
        //         break;
        //     }
        //     throughput *= 1.0 / p;
        // }

    }  
    
    return vec4(radiance, 1.0);
}


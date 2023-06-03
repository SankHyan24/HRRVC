#define eps 0.00001
#define LIGHTPATHLENGTH 4
#define EYEPATHLENGTH 3
#define SAMPLES 10

#define SHOWSPLITLINE
#define FULLBOX

#define DOF
#define ANIMATENOISE
#define MOTIONBLUR

#define MOTIONBLURFPS 12.

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
    vec3 rd = cosWeightedRandomHemisphereDirection( ro, seed );
    vec3 color = emission;
 
    for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
        lpNodes[i].position = lpNodes[i].color = lpNodes[i].normal = vec3(0.);
    }
    
    float w = 0.;
    bool hit = false; 
    for( int i=0; i<LIGHTPATHLENGTH; i++ ) {
		vec3 normal;

        // vec2 res = intersect( ro, rd, normal ); 
        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 
        if(hit){
            if(state.isEmitter == true) {
                break;
            }
            GetMaterial(state, r);
            Material mat = state.mat;
            ro = ro + rd*state.hitDist + eps * state.normal;            
            color *= mat.baseColor;
            
            lpNodes[i].position = ro;
            lpNodes[i].color = color;
            lpNodes[i].normal = state.normal;
            vec3 rdi = rd;
            scatterSample.f = DisneySample(state,  -rdi, state.ffnormal, scatterSample.L, scatterSample.pdf);
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

vec4 traceEyePath( in vec3 ro, in vec3 rd, const in bool bidirectTrace, inout float seed ) {
    State state; 
    vec3 tcol = vec3(0.);
    vec3 fcol  = vec3(1.);
    vec3 throughput = vec3(1.); 
    float alpha = 1.0; 
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

	int jdiff = 0;
    
    bool hit = false; 
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        float pdf = 0.0; 
        vec3 normal;
           
        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 
        Material mat; 
        if(!hit){
            return vec4(tcol * throughput, 1.0);
        }
        
        GetMaterial(state, r);
        mat = state.mat;

        if(hit && state.isEmitter){
            tcol += fcol * lightSample.emission;
            return vec4(tcol * throughput, 1.0) ;
        }
        
        
        ro = ro + state.hitDist * rd + eps * state.normal;  
        vec3 rdi = rd;

        scatterSample.f = DisneySample(state,  -rdi, state.ffnormal, scatterSample.L, scatterSample.pdf);
        if (scatterSample.pdf > 0.0)
            throughput *= scatterSample.f / scatterSample.pdf;

        rd = scatterSample.L; 
        

        if(dot(rd,state.normal) < 0.) {  
        	fcol *= mat.baseColor;
        }
        
        SampleOneLight(light, ro, lightSample); 
        vec3 ld = lightSample.direction; 
        

        vec3 nld = normalize(ld);

        Ray r2 = Ray(ro, ld);
        hit = ClosestHit(r2, state, lightSample);
        bool isEmitter = state.isEmitter;
        
        if( isEmitter ) {
             tcol += (fcol * lightSample.emission) * clamp(dot( nld, state.normal ), 0., 1.) * (1-state.mat.metallic)
             / lightSample.pdf / getWeightForPath(jdiff,-1) * throughput; 
            
        }

        if( bidirectTrace  ) {
            if( true ) {
                for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
                    // path of (j+1) eyepath-nodes, and i+2 lightpath-nodes.
                    vec3 lp = lpNodes[i].position - ro;
                    vec3 lpn = normalize( lp );
                    vec3 lc = lpNodes[i].color;
                    Ray r3 = Ray(ro, lp);
                    hit = ClosestHit(r3, state, lightSample);
                    bool isEmitter = state.isEmitter;
                    if( isEmitter && hit) {

                        float weight = 
                                 clamp( dot( lpn, state.normal ), 0.0, 1.) 
                               * clamp( dot( -lpn, lpNodes[i].normal ), 0., 1.)
                               * clamp(1. / dot(lp, lp), 0., 1.)
                            ;

                        tcol += lc * fcol * weight / getWeightForPath(jdiff,i) * throughput;
                        return vec4(tcol, 1.0);
                    }
                }
            }
        }
        
        jdiff++;
    }  
    
    return vec4(tcol, 1.0);
}


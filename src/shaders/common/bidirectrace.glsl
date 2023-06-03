#define eps 0.00001
#define LIGHTPATHLENGTH 2
#define EYEPATHLENGTH 3
#define SAMPLES 10

#define SHOWSPLITLINE
#define FULLBOX

#define DOF
#define ANIMATENOISE
#define MOTIONBLUR

#define MOTIONBLURFPS 12.

#define LIGHTCOLOR vec3(16.86, 10.76, 8.2)*200.
#define WHITECOLOR vec3(.7295, .7355, .729)*0.7
#define GREENCOLOR vec3(.117, .4125, .115)*0.7
#define REDCOLOR vec3(.611, .0555, .062)*0.7

//-----------------------------------------------------
// Intersection functions (by iq)
//-----------------------------------------------------

//-----------------------------------------------------
// scene
//-----------------------------------------------------

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

vec3 getBRDFRay( in vec3 n, const in vec3 rd, const in float m, inout bool specularBounce, inout float seed ) {
    specularBounce = false;
    
    vec3 r = cosWeightedRandomHemisphereDirection( n, seed );
    return r; 
    // if(  !matIsSpecular( m ) ) {
    //     return r;
    // } else {
    //     specularBounce = true;
        
    //     float n1, n2, ndotr = dot(rd,n);
        
    //     if( ndotr > 0. ) {
    //         n1 = 1./1.5; n2 = 1.;
    //         n = -n;
    //     } else {
    //         n2 = 1./1.5; n1 = 1.;
    //     }
                
    //     float r0 = (n1-n2)/(n1+n2); r0 *= r0;
	// 	float fresnel = r0 + (1.-r0) * pow(1.0-abs(ndotr),5.);
        
    //     vec3 ref = refract( rd, n, n2/n1 );        
    //     if( ref == vec3(0) || hash1(seed) < fresnel || m > 6.5 ) {
    //         ref = reflect( rd, n );
    //     }
        
    //     return ref; // normalize( ref + 0.1 * r );
	// }
}

//-----------------------------------------------------
// lightpath
//-----------------------------------------------------

struct LightPathNode {
    vec3 color;
    vec3 position;
    vec3 normal;
};

LightPathNode lpNodes[LIGHTPATHLENGTH];

void constructLightPath( inout float seed ) {
    State state; 
    LightSampleRec lightSample;
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
    
    bool specularBounce;
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
            ro = ro + rd*state.hitDist;            
            color *= mat.baseColor;
            
            lpNodes[i].position = ro;
            lpNodes[i].color = color;
            lpNodes[i].normal = state.normal;

            rd = getBRDFRay(state.normal, rd, 0, specularBounce, seed );
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
    float alpha = 1.0; 
    LightSampleRec lightSample;
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

    bool specularBounce = false; 
	int jdiff = 0;
    
    bool hit = false; 
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        vec3 normal;
           
        Ray r = Ray(ro, rd); 
        hit = ClosestHit(r, state, lightSample); 
        Material mat; 
        if(!hit){
            return vec4(tcol, 1.0);
        }
        
        GetMaterial(state, r);
        mat = state.mat;
        if(hit && state.isEmitter){
            tcol += fcol * lightSample.emission;
            return vec4(tcol, 1.0);
        }
        
        
        ro = ro + state.hitDist * rd + eps * state.normal;  
        vec3 rdi = rd;
        rd = getBRDFRay( state.normal, rd, 0, specularBounce, seed );
        

        if(!specularBounce || dot(rd,state.normal) < 0.) {  
        	fcol *= mat.baseColor;
        }
        
        SampleOneLight(light, ro, lightSample); 
        vec3 ld = lightSample.direction; 
        

        vec3 nld = normalize(ld);

        Ray r2 = Ray(ro, ld);
        hit = ClosestHit(r2, state, lightSample);
        bool isEmitter = state.isEmitter;


        if( !specularBounce && isEmitter ) {
             tcol += (fcol * lightSample.emission) * clamp(dot( nld, state.normal ), 0., 1.) 
             / lightSample.pdf / getWeightForPath(jdiff,-1); 
            
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

                        tcol += lc * fcol * weight / getWeightForPath(jdiff,i);
                        return vec4(tcol, 1.0);
                    }
                }
            }
        }
        
        if( !specularBounce) jdiff++; else jdiff = 0;
    }  
    
    return vec4(tcol, 1.0);
}


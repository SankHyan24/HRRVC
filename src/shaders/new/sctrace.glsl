
struct LightPathNode {
    vec3 color;
    vec3 position;
    vec3 normal;
};

LightPathNode lpNodes[LIGHTPATHLENGTH];

void constructLightPath( inout float seed ) {
    vec3 ro = randomSphereDirection( seed );
    vec3 rd = cosWeightedRandomHemisphereDirection( ro, seed );
    ro = lightSphere.xyz - ro*lightSphere.w;
    vec3 color = LIGHTCOLOR;
 
    for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
        lpNodes[i].position = lpNodes[i].color = lpNodes[i].normal = vec3(0.);
    }
    
    bool specularBounce;
    float w = 0.;
    
    for( int i=0; i<LIGHTPATHLENGTH; i++ ) {
		vec3 normal;
        vec2 res = intersect( ro, rd, normal );
        
        if( res.y > 0.5 && dot( rd, normal ) < 0. ) {
            ro = ro + rd*res.x;            
            color *= matColor( res.y );
            
            lpNodes[i].position = ro;
            if( !matIsSpecular( res.y ) ) lpNodes[i].color = color;// * clamp( dot( normal, -rd ), 0., 1.);
            lpNodes[i].normal = normal;
            
            rd = getBRDFRay( normal, rd, res.y, specularBounce, seed );
        } else break;
    }
}

//-----------------------------------------------------
// eyepath
//-----------------------------------------------------

float getWeightForPath( int e, int l ) {
    return float(e + l + 2);
}

vec3 traceEyePath( in vec3 ro, in vec3 rd, const in bool bidirectTrace, inout float seed ) {
    vec3 tcol = vec3(0.);
    vec3 fcol  = vec3(1.);
    
    bool specularBounce = true; 
	int jdiff = 0;
    
    for( int j=0; j<EYEPATHLENGTH; ++j ) {
        vec3 normal;
        
        vec2 res = intersect( ro, rd, normal );
        if( res.y < -0.5 ) {
            return tcol;
        }
        
        if( matIsLight( res.y ) ) {
            if( bidirectTrace ) {
            	if( specularBounce ) tcol += fcol*LIGHTCOLOR;
            } else {
               tcol += fcol*LIGHTCOLOR;
            }
            return tcol; // the light has no diffuse component, therefore we can return col
        }
        
        ro = ro + res.x * rd;   
        vec3 rdi = rd;
        rd = getBRDFRay( normal, rd, res.y, specularBounce, seed );
            
        if(!specularBounce || dot(rd,normal) < 0.) {  
        	fcol *= matColor( res.y );
        }
        
        if( bidirectTrace  ) {
		    vec3 ld = sampleLight( ro, seed ) - ro;       
            
            // path of (j+1) eyepath-nodes, and 1 lightpath-node ( = direct light sampling )
            vec3 nld = normalize(ld);
            if( !specularBounce &&  !intersectShadow( ro, nld, length(ld)) ) {
                float cos_a_max = sqrt(1. - clamp(lightSphere.w * lightSphere.w / dot(lightSphere.xyz-ro, lightSphere.xyz-ro), 0., 1.));
                float weight = 2. * (1. - cos_a_max);

                tcol += (fcol * LIGHTCOLOR) * (weight * clamp(dot( nld, normal ), 0., 1.))
                    / getWeightForPath(jdiff,-1);
            }

            
            if( !matIsSpecular( res.y ) ) {
                for( int i=0; i<LIGHTPATHLENGTH; ++i ) {
                    // path of (j+1) eyepath-nodes, and i+2 lightpath-nodes.
                    vec3 lp = lpNodes[i].position - ro;
                    vec3 lpn = normalize( lp );
                    vec3 lc = lpNodes[i].color;

                    if( !intersectShadow(ro, lpn, length(lp)) ) {
                        // weight for going from (j+1)th eyepath-node to (i+2)th lightpath-node
                        
                        // IS THIS CORRECT ???
                        
                        float weight = 
                                 clamp( dot( lpn, normal ), 0.0, 1.) 
                               * clamp( dot( -lpn, lpNodes[i].normal ), 0., 1.)
                               * clamp(1. / dot(lp, lp), 0., 1.)
                            ;

                        tcol += lc * fcol * weight / getWeightForPath(jdiff,i);
                    }
                }
            }
        }
        
        if( !specularBounce) jdiff++; else jdiff = 0;
    }  
    
    return tcol;
}

//-----------------------------------------------------
// main
//-----------------------------------------------------

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
	vec2 q = fragCoord.xy / iResolution.xy;
    
	float splitCoord = (iMouse.x == 0.0) ? iResolution.x/2. + iResolution.x*cos(iTime*.5) : iMouse.x;
    bool bidirectTrace = fragCoord.x < splitCoord;
    
    //-----------------------------------------------------
    // camera
    //-----------------------------------------------------

    vec2 p = -1.0 + 2.0 * (fragCoord.xy) / iResolution.xy;
    p.x *= iResolution.x/iResolution.y;

#ifdef ANIMATENOISE
    float seed = p.x + p.y * 3.43121412313 + fract(1.12345314312*iTime);
#else
    float seed = p.x + p.y * 3.43121412313;
#endif
    
    vec3 ro = vec3(2.78, 2.73, -8.00);
    vec3 ta = vec3(2.78, 2.73,  0.00);
    vec3 ww = normalize( ta - ro );
    vec3 uu = normalize( cross(ww,vec3(0.0,1.0,0.0) ) );
    vec3 vv = normalize( cross(uu,ww));

    //-----------------------------------------------------
    // render
    //-----------------------------------------------------

    vec3 col = vec3(0.0);
    vec3 tot = vec3(0.0);
    vec3 uvw = vec3(0.0);
    
    for( int a=0; a<SAMPLES; a++ ) {

        vec2 rpof = 4.*(hash2(seed)-vec2(0.5)) / iResolution.xy;
	    vec3 rd = normalize( (p.x+rpof.x)*uu + (p.y+rpof.y)*vv + 3.0*ww );
        
#ifdef DOF
	    vec3 fp = ro + rd * 12.0;
   		vec3 rof = ro + (uu*(hash1(seed)-0.5) + vv*(hash1(seed)-0.5))*0.125;
    	rd = normalize( fp - rof );
#else
        vec3 rof = ro;
#endif        
        
#ifdef MOTIONBLUR
        initMovingSphere( iTime + hash1(seed) / MOTIONBLURFPS );
#else
        initMovingSphere( iTime );        
#endif
        
        if( bidirectTrace ) {
            constructLightPath( seed );
        }
        
        col = traceEyePath( rof, rd, bidirectTrace, seed );

        tot += col;
        
        seed = mod( seed*1.1234567893490423, 13. );
    }
    
    tot /= float(SAMPLES);
    
#ifdef SHOWSPLITLINE
	if (abs(fragCoord.x - splitCoord) < 1.0) {
		tot.x = 1.0;
	}
#endif
    
	tot = pow( clamp(tot,0.0,1.0), vec3(0.45) );

    fragColor = vec4( tot, 1.0 );
}
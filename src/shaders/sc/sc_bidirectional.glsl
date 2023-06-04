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


vec4 scBDPT(Ray r){
    return vec4(0., 0., 0., 0.);
}
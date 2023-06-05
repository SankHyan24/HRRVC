#define eps 0.00001

#define MOTIONBLURFPS 12.

#define LIGHTCOLOR vec3(16.86, 10.76, 8.2)*200.
#define WHITECOLOR vec3(.7295, .7355, .729)*0.7
#define GREENCOLOR vec3(.117, .4125, .115)*0.7
#define REDCOLOR vec3(.611, .0555, .062)*0.7


vec4 scBDPT(Ray r){
    vec3 ro = r.origin;
    vec3 rd = r.direction;
    return vec4(0., 0., 0., 0.);
}
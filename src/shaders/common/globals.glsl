/*
 * MIT License
 *
 * Copyright(c) 2019 Asif Ali
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#define PI         3.14159265358979323
#define INV_PI     0.31830988618379067
#define TWO_PI     6.28318530717958648
#define INV_TWO_PI 0.15915494309189533
#define INV_4_PI   0.07957747154594766
#define EPS 0.0003
#define EPS_GAMMA 0.00003
#define INF 1000000.0

#define QUAD_LIGHT 0
#define SPHERE_LIGHT 1
#define DISTANT_LIGHT 2

#define ALPHA_MODE_OPAQUE 0
#define ALPHA_MODE_BLEND 1
#define ALPHA_MODE_MASK 2

#define MEDIUM_NONE 0
#define MEDIUM_ABSORB 1
#define MEDIUM_SCATTER 2
#define MEDIUM_EMISSIVE 3

struct Ray
{
    vec3 origin;
    vec3 direction;
};

struct Medium
{
    int type;
    float density;
    vec3 color;
    float anisotropy;
};

/*
    baseColor：表示材质漫反射颜色的 3 分量向量
    opacity：控制材质透明度的标量
    alphaMode：一个整数，指定要使用的 alpha 混合模式
    alphaCutoff：确定 alpha 测试阈值的标量
    emission：一个三分量向量，表示材料的发射颜色
    anisotropic：控制材料反射各向异性水平的标量
    metallic：控制材料中金属反射水平的标量
    roughness：控制材料表面粗糙度水平的标量
    subsurface：控制材料中次表面散射量的标量
    specularTint：控制材质镜面反射高光颜色的标量
    sheen：控制材料光泽度的标量
    sheenTint：控制材质光泽颜色的标量
    clearcoat：控制材料中透明涂层反射水平的标量
    clearcoatRoughness：控制材料透明涂层粗糙度水平的标量
    specTrans：控制材质中镜面反射传输量的标量
    ior：表示材料折射率的标量
    ax, ay：表示材料各向异性方向的标量
    medium：表示观看或传输材料的媒体的结构。
*/
struct Material
{
    vec3 baseColor;
    float opacity;
    int alphaMode;
    float alphaCutoff;
    vec3 emission;
    float anisotropic;
    float metallic;
    float roughness;
    float subsurface;
    float specularTint;
    float sheen;
    float sheenTint;
    float clearcoat;
    float clearcoatRoughness;
    float specTrans;
    float ior;
    float ax;
    float ay;
    Medium medium;
};

struct Camera
{
    vec3 up;
    vec3 right;
    vec3 forward;
    vec3 position;
    float fov;
    float focalDist;
    float aperture;
};

struct Light
{
    vec3 position;
    vec3 emission;
    vec3 u;
    vec3 v;
    float radius;
    float area;
    float type;
};

struct State
{
    int depth;
    float eta;
    float hitDist;

    vec3 fhp;
    vec3 normal;
    vec3 ffnormal;
    vec3 tangent;
    vec3 bitangent;

    bool isEmitter;

    vec2 texCoord;
    int matID;
    Material mat;
    Medium medium;
};

struct ScatterSampleRec
{
    vec3 L;
    vec3 f;
    float pdf;
};

struct LightSampleRec
{
    vec3 normal;
    vec3 emission;
    vec3 direction;
    float dist;
    float pdf;
};

uniform Camera camera;

//RNG from code by Moroz Mykhailo (https://www.shadertoy.com/view/wltcRS)

//internal RNG state 
/*全局变量：一个称为 seed 的 4 分量无符号整数向量和一个称为 pixel 的 2 分量整数向量。*/
uvec4 seed;
ivec2 pixel;
/*
    InitRNG 函数采用一个 2 分量向量 p 和一个整数框架作为参数。 它将 pixel 的值设
    置为 p 的整数部分，并将 seed 的值设置为一个包含 p.x、p.y、frame 以及 p.x 和 
    p.y 之和的 4 分量向量。
*/
void InitRNG(vec2 p, int frame)
{
    pixel = ivec2(p);
    seed = uvec4(p, uint(frame), uint(p.x) + uint(p.y));
}
/*pcg4d 函数将无符号整数向量 v 作为参数并对其进行修改。 它对 v 的组件执行一系列算术和按位运算以生成新的随机值。*/
void pcg4d(inout uvec4 v)
{
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
    v = v ^ (v >> 16u);
    v.x += v.y * v.w; v.y += v.z * v.x; v.z += v.x * v.y; v.w += v.y * v.z;
}
/*rand 函数在全局种子向量上调用 pcg4d 并返回一个介于 0 和 1 之间的随机值，方法是将种子的 x 分量除以无符号 32 位整数的最大值。*/
float rand()
{
    pcg4d(seed); return float(seed.x) / float(0xffffffffu);
}
/*
    FaceForward 函数将两个三分量向量 a 和 b 作为参数，如果 a 和 b 的点积为正则返回 b，否则
    返回 -b。 此函数常用于计算机图形，以确保表面法线朝向观察者。
*/
vec3 FaceForward(vec3 a, vec3 b)
{
    return dot(a, b) < 0.0 ? -b : b;
}
/*Luminance 函数采用表示 RGB 空间中颜色的 3 分量向量 c，并使用标准公式返回其亮度值。 此函数对于将彩色图像转换为灰度图像很有用。*/
float Luminance(vec3 c)
{
    return 0.212671 * c.x + 0.715160 * c.y + 0.072169 * c.z;
}
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

void GetMaterial(inout State state, in Ray r)
{
    int index = state.matID * 8;
    Material mat;
    Medium medium;

    vec4 param1 = texelFetch(materialsTex, ivec2(index + 0, 0), 0);
    vec4 param2 = texelFetch(materialsTex, ivec2(index + 1, 0), 0);
    vec4 param3 = texelFetch(materialsTex, ivec2(index + 2, 0), 0);
    vec4 param4 = texelFetch(materialsTex, ivec2(index + 3, 0), 0);
    vec4 param5 = texelFetch(materialsTex, ivec2(index + 4, 0), 0);
    vec4 param6 = texelFetch(materialsTex, ivec2(index + 5, 0), 0);
    vec4 param7 = texelFetch(materialsTex, ivec2(index + 6, 0), 0);
    vec4 param8 = texelFetch(materialsTex, ivec2(index + 7, 0), 0);

    mat.baseColor          = param1.rgb;
    mat.anisotropic        = param1.w;

    mat.emission           = param2.rgb;

    mat.metallic           = param3.x;
    mat.roughness          = max(param3.y, 0.001);
    mat.subsurface         = param3.z;
    mat.specularTint       = param3.w;

    mat.sheen              = param4.x;
    mat.sheenTint          = param4.y;
    mat.clearcoat          = param4.z;
    mat.clearcoatRoughness = mix(0.1, 0.001, param4.w); // Remapping from gloss to roughness

    mat.specTrans          = param5.x;
    mat.ior                = param5.y;
    mat.medium.type        = int(param5.z);
    mat.medium.density     = param5.w;

    mat.medium.color       = param6.rgb;
    mat.medium.anisotropy  = clamp(param6.w, -0.9, 0.9);

    ivec4 texIDs           = ivec4(param7);

    mat.opacity            = param8.x;
    mat.alphaMode          = int(param8.y);
    mat.alphaCutoff        = param8.z;

    // Base Color Map
    if (texIDs.x >= 0)
    {
        vec4 col = texture(textureMapsArrayTex, vec3(state.texCoord, texIDs.x));
        mat.baseColor.rgb *= pow(col.rgb, vec3(2.2));
        mat.opacity *= col.a;
    }

    // Metallic Roughness Map
    if (texIDs.y >= 0)
    {
        vec2 matRgh = texture(textureMapsArrayTex, vec3(state.texCoord, texIDs.y)).bg;
        mat.metallic = matRgh.x;
        mat.roughness = max(matRgh.y * matRgh.y, 0.001);
    }

    // Normal Map
    if (texIDs.z >= 0)
    {
        vec3 texNormal = texture(textureMapsArrayTex, vec3(state.texCoord, texIDs.z)).rgb;

#ifdef OPT_OPENGL_NORMALMAP
        texNormal.y = 1.0 - texNormal.y;
#endif
        texNormal = normalize(texNormal * 2.0 - 1.0);

        vec3 origNormal = state.normal;
        state.normal = normalize(state.tangent * texNormal.x + state.bitangent * texNormal.y + state.normal * texNormal.z);
        state.ffnormal = dot(origNormal, r.direction) <= 0.0 ? state.normal : -state.normal;
    }

#ifdef OPT_ROUGHNESS_MOLLIFICATION
    if(state.depth > 0)
        mat.roughness = max(mix(0.0, state.mat.roughness, roughnessMollificationAmt), mat.roughness);
#endif

    // Emission Map
    if (texIDs.w >= 0)
        mat.emission = pow(texture(textureMapsArrayTex, vec3(state.texCoord, texIDs.w)).rgb, vec3(2.2));

    float aspect = sqrt(1.0 - mat.anisotropic * 0.9);
    mat.ax = max(0.001, mat.roughness / aspect);
    mat.ay = max(0.001, mat.roughness * aspect);

    state.mat = mat;
    state.eta = dot(r.direction, state.normal) < 0.0 ? (1.0 / mat.ior) : mat.ior;
}

// TODO: Recheck all of this
/*
    此代码定义了一个名为“EvalTransmittance”的函数，该函数将光线作为输入并返回表示光线通过介质的透射率
    的 vec3 值。 该函数使用一个循环来跟踪穿过介质的光线并计算每一步的透射率。
*/
#if defined(OPT_MEDIUM) && defined(OPT_VOL_MIS)
vec3 EvalTransmittance(Ray r)
{
    /*
        该函数首先初始化了一些变量，包括一个LightSampleRec对象，一个State对象，
        以及一个透射率值的vec3（初始化为(1.0, 1.0, 1.0)表示没有衰减）。
    */
    LightSampleRec lightSample;
    State state;
    vec3 transmittance = vec3(1.0);
    /*
        然后该函数进入一个循环，该循环将一直持续到光线达到其最大深度或与发射器（即光源）相交为止。
    */
    for (int depth = 0; depth < maxDepth; depth++)
    {
        bool hit = ClosestHit(r, state, lightSample);

        // If no hit (environment map) or if ray hit a light source then return transmittance
        /*
            如果光线没有击中任何东西或没有击中发射器，则该函数会跳出循环并返回当前的透射率值。
        */
        if (!hit || state.isEmitter)
            break;

        // TODO: Get only parameters that are needed to calculate transmittance

        GetMaterial(state, r);
        /*
            如果光线击中物体，该函数会检查材质是否启用了 alpha 测试或折射。 如果材质具有 alpha
            测试并且光线的不透明度低于截止值，或者如果材质启用了混合并且随机数大于不透明度值，则
            函数返回 (0.0, 0.0, 0.0) 的 vec3 以指示 射线被阻挡。
        */
        bool alphatest = (state.mat.alphaMode == ALPHA_MODE_MASK && state.mat.opacity < state.mat.alphaCutoff) || (state.mat.alphaMode == ALPHA_MODE_BLEND && rand() > state.mat.opacity);
        bool refractive = (1.0 - state.mat.metallic) * state.mat.specTrans > 0.0;

        // Refraction is ignored (Not physically correct but helps with sampling lights from inside refractive objects)
        if(hit && !(alphatest || refractive))
            return vec3(0.0);

        // Evaluate transmittance
        /*
            如果击中未被阻挡，该函数将评估介质在击中点处的透射率。 如果光线方向与表面法线的点积为正
            （表示光线从介质中射出），并且材料具有非零介质密度，函数使用比尔-朗伯定律计算透射率，其中
            透射率降低的量与介质的密度和穿过它的距离成正比。
        */
        if (dot(r.direction, state.normal) > 0 && state.mat.medium.type != MEDIUM_NONE)
        {
            vec3 color = state.mat.medium.type == MEDIUM_ABSORB ? vec3(1.0) - state.mat.medium.color : vec3(1.0);
            transmittance *= exp(-color * state.mat.medium.density * state.hitDist);
        }

        // Move ray origin to hit point
        /*
            最后，该函数将光线的原点更新为命中点，并继续通过介质追踪光线。
        */
        r.origin = state.fhp + r.direction * EPS;
    }

    return transmittance;
}
#endif


/*
    此代码在给定光线和状态的情况下计算对场景中某个点的直接照明贡献。
*/
vec3 DirectLight(in Ray r, in State state, bool isSurface)
{
    /*
    首先将直接照明贡献和间接照明贡献初始化为零。 然后，它通过将光线的命中点添加到表面法线
    乘以一个小的 epsilon 值来计算散射位置。
    */
    vec3 Ld = vec3(0.0);
    vec3 Li = vec3(0.0);
    vec3 scatterPos = state.fhp + state.normal * EPS;

    ScatterSampleRec scatterSample;

    // Environment Light
#ifdef OPT_ENVMAP
#ifndef OPT_UNIFORM_LIGHT
    /*
        接下来，它通过调用函数 SampleEnvMap 对间接照明的环境贴图进行采样，并将结果存储在 Li 中。 
        它还计算光的方向和采样方向的概率密度函数。 如果场景包含体积，它会评估介质的透射率并使用 
        Henyey-Greenstein 相函数计算散射相函数。 然后计算 MIS 权重并添加对直接照明的贡献。 
    */
    {
        vec3 color;
        vec4 dirPdf = SampleEnvMap(Li);
        vec3 lightDir = dirPdf.xyz;
        float lightPdf = dirPdf.w;

        Ray shadowRay = Ray(scatterPos, lightDir);

#if defined(OPT_MEDIUM) && defined(OPT_VOL_MIS)
        // If there are volumes in the scene then evaluate transmittance rather than a binary anyhit test
        Li *= EvalTransmittance(shadowRay);

        if (isSurface)
            scatterSample.f = DisneyEval(state, -r.direction, state.ffnormal, lightDir, scatterSample.pdf);
        else
        {
            float p = PhaseHG(dot(-r.direction, lightDir), state.medium.anisotropy);
            scatterSample.f = vec3(p);
            scatterSample.pdf = p;
        }

        if (scatterSample.pdf > 0.0)
        {
            float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
            if (misWeight > 0.0)
                Ld += misWeight * Li * scatterSample.f * envMapIntensity / lightPdf;
        }
#else
    /*
        如果场景中没有体积，它会使用简单的二进制命中测试来检查阴影并添加对直接照明的贡献。
    */
        // If there are no volumes in the scene then use a simple binary hit test
        bool inShadow = AnyHit(shadowRay, INF - EPS);

        if (!inShadow)
        {
            scatterSample.f = DisneyEval(state, -r.direction, state.ffnormal, lightDir, scatterSample.pdf);

            if (scatterSample.pdf > 0.0)
            {
                float misWeight = PowerHeuristic(lightPdf, scatterSample.pdf);
                if (misWeight > 0.0)
                    Ld += misWeight * Li * scatterSample.f * envMapIntensity / lightPdf;
            }
        }
#endif
    }
#endif
#endif

/*
    检查是否定义了 OPT_LIGHTS 标志，该标志指示场景中是否存在灯。
*/
    // Analytic Lights
#ifdef OPT_LIGHTS
    {
        /*
            从场景中的一组可用灯光中随机采样一个灯光。 它从纹理中获取光数据并创建一个光对象。 
            然后，它使用 SampleOneLight 函数对光进行采样，并将发射存储在 Li 中。 它通过
            计算采样方向和表面法线的点积来检查光线是单侧还是双侧。 如果点积为负，则意味着光
            是单面的，我们需要确保不包括光背面的贡献。
        */
        LightSampleRec lightSample;
        Light light;

        //Pick a light to sample
        int index = int(rand() * float(numOfLights)) * 5;

        // Fetch light Data
        vec3 position = texelFetch(lightsTex, ivec2(index + 0, 0), 0).xyz;
        vec3 emission = texelFetch(lightsTex, ivec2(index + 1, 0), 0).xyz;
        vec3 u        = texelFetch(lightsTex, ivec2(index + 2, 0), 0).xyz; // u vector for rect
        vec3 v        = texelFetch(lightsTex, ivec2(index + 3, 0), 0).xyz; // v vector for rect
        vec3 params   = texelFetch(lightsTex, ivec2(index + 4, 0), 0).xyz;
        float radius  = params.x;
        float area    = params.y;
        float type    = params.z; // 0->Rect, 1->Sphere, 2->Distant

        light = Light(position, emission, u, v, radius, area, type);
        SampleOneLight(light, scatterPos, lightSample);
        Li = lightSample.emission;

        if (dot(lightSample.direction, lightSample.normal) < 0.0) // Required for quad lights with single sided emission
        {
            Ray shadowRay = Ray(scatterPos, lightSample.direction);

            /*
                如果场景包含体积，它会评估介质的透射率并使用 Henyey-Greenstein 相函数计算散射相函数。 
                然后计算 MIS 权重并添加对直接照明的贡献。 如果场景中没有体积，它会使用简单的二进制命中
                测试来检查阴影并添加对直接照明的贡献。总的来说，此代码用于计算分析灯的直接照明贡献，并考
                虑了体积和单面灯的存在。
            */
            // If there are volumes in the scene then evaluate transmittance rather than a binary anyhit test
#if defined(OPT_MEDIUM) && defined(OPT_VOL_MIS)
            Li *= EvalTransmittance(shadowRay);

            if (isSurface)
                scatterSample.f = DisneyEval(state, -r.direction, state.ffnormal, lightSample.direction, scatterSample.pdf);
            else
            {
                float p = PhaseHG(dot(-r.direction, lightSample.direction), state.medium.anisotropy);
                scatterSample.f = vec3(p);
                scatterSample.pdf = p;
            }

            float misWeight = 1.0;
            if(light.area > 0.0) // No MIS for distant light
                misWeight = PowerHeuristic(lightSample.pdf, scatterSample.pdf);

            if (scatterSample.pdf > 0.0)
                Ld += misWeight * scatterSample.f * Li / lightSample.pdf;
#else
            // If there are no volumes in the scene then use a simple binary hit test
            bool inShadow = AnyHit(shadowRay, lightSample.dist - EPS);

            if (!inShadow)
            {
                scatterSample.f = DisneyEval(state, -r.direction, state.ffnormal, lightSample.direction, scatterSample.pdf);

                float misWeight = 1.0;
                if(light.area > 0.0) // No MIS for distant light
                    misWeight = PowerHeuristic(lightSample.pdf, scatterSample.pdf);

                if (scatterSample.pdf > 0.0)
                    Ld += misWeight * Li * scatterSample.f / lightSample.pdf;
            }
#endif
        }
    }
#endif

    return Ld;
}


/*
    这是路径追踪的主要功能，它通过追踪光线和计算每个像素的辐射值来模拟场景中光
    的行为。 它接受一个 Ray 对象作为输入并返回一个 vec4 对象，表示该射线的最
    终辐射值。
*/
vec4 PathTrace(Ray r)
{
    /*
        该函数初始化 radiance、throughput、state、lightSample 和 scatterSample 
        的变量。 它还将 alpha 值设置为 1.0，稍后将用于介质跟踪。
    */
    vec3 radiance = vec3(0.0);
    vec3 throughput = vec3(1.0);
    State state;
    LightSampleRec lightSample;
    ScatterSampleRec scatterSample;

    // FIXME: alpha from material opacity/medium density
    float alpha = 1.0;

    // For medium tracking
    bool inMedium = false;
    bool mediumSampled = false;
    bool surfaceScatter = false;
    /*
        for 循环一直持续到达到最大深度或直到射线没有击中任何东西。 
    */
    for (state.depth = 0;; state.depth++)
    {
        // 判断是否命中，并更新state和lightSample
        // 它首先通过调用 ClosestHit 函数检查光线是否命中任何东西，如果命中发生，该函数会更新 state 和 lightSample 变量。 
        bool hit = ClosestHit(r, state, lightSample);
        // 如果没有命中，该函数将检查当前深度是否为 0，如果定义了 OPT_BACKGROUND 或 
        //OPT_TRANSPARENT_BACKGROUND，则将 alpha 值设置为 0.0。 
        if (!hit)
        {
#if defined(OPT_BACKGROUND) || defined(OPT_TRANSPARENT_BACKGROUND)
            if (state.depth == 0)
                alpha = 0.0;
#endif
        //如果定义了 OPT_HIDE_EMITTERS 并且深度大于 0，则该函数会跳过从发光对象收集辐射。 
        // 否则，它会根据定义的选项从环境贴图或均匀光中收集辐射。

#ifdef OPT_HIDE_EMITTERS
            if(state.depth > 0)
#endif
            {
#ifdef OPT_UNIFORM_LIGHT
                radiance += uniformLightCol * throughput;
#else
#ifdef OPT_ENVMAP
                vec4 envMapColPdf = EvalEnvMap(r);

                float misWeight = 1.0;

                if (state.depth > 0)
                    misWeight = PowerHeuristic(scatterSample.pdf, envMapColPdf.w);

#if defined(OPT_MEDIUM) && !defined(OPT_VOL_MIS)
                if(!surfaceScatter)
                    misWeight = 1.0f;
#endif

                if(misWeight > 0)
                    radiance += misWeight * envMapColPdf.rgb * throughput * envMapIntensity;
#endif
#endif
             }
             break;
        }
        /*
            如果有命中，该函数通过调用 GetMaterial 函数获取命中对象的材料属性。 
            如果定义了 OPT_LIGHTS，它会从发光物体和灯光收集辐射。
        */
        GetMaterial(state, r);

        // Gather radiance from emissive objects. Emission from meshes is not importance sampled
        radiance += state.mat.emission * throughput;
        
#ifdef OPT_LIGHTS

        // Gather radiance from light and use scatterSample.pdf from previous bounce for MIS
        if (state.isEmitter)
        {
            float misWeight = 1.0;

            if (state.depth > 0)
                misWeight = PowerHeuristic(scatterSample.pdf, lightSample.pdf);
        /*
            如果定义了 OPT_LIGHTS 并且当前命中对象是发射器，则该函数收集来自光
            源的辐射度，其中包含来自上一次反弹的 scatterSample.pdf 和来自当前
            命中的 lightSample.pdf然后该函数跳出循环。
        */
#if defined(OPT_MEDIUM) && !defined(OPT_VOL_MIS)
            if(!surfaceScatter)
                misWeight = 1.0f;
#endif

            radiance += misWeight * lightSample.emission * throughput;

            break;
        }
#endif
        // Stop tracing ray if maximum depth was reached
        if(state.depth == maxDepth)
            break;


/*
    如果定义了 OPT_MEDIUM，该函数会初始化媒体跟踪的变量。 如果介质类型是 MEDIUM_SCATTER，函数在介质中采
    样一个距离，更新吞吐量，将光线原点移动到散射位置，评估透射率，根据相位函数选择一
    个新方向，并更新 scatterSample.pdf 和 r.方向变量。
*/
#ifdef OPT_MEDIUM

        mediumSampled = false;
        surfaceScatter = false;

        // Handle absorption/emission/scattering from medium
        // TODO: Handle light sources placed inside medium
        /*如果光线当前在介质内部，则该函数处理介质的吸收、发射和散射*/
        if(inMedium)
        {
            /* 如果介质类型为 MEDIUM_ABSORB，则该函数通过介质的吸收系数降低吞吐量 */
            if(state.medium.type == MEDIUM_ABSORB)
            {
                throughput *= exp(-(1.0 - state.medium.color) * state.hitDist * state.medium.density);
            }
            /*如果介质类型为 MEDIUM_EMISSIVE，则该函数会将介质的辐射度添加到总辐射度中。*/
            else if(state.medium.type == MEDIUM_EMISSIVE)
            {
                radiance += state.medium.color * state.hitDist * state.medium.density * throughput;
            }
            /*
                如果介质类型是 MEDIUM_SCATTER，函数在介质中采样一个距离，更新吞吐量，
                将光线原点移动到散射位置，评估透射率，根据相位函数选择一个新方向，并更新 
                scatterSample.pdf 和 r .方向变量。
            */
            else // MEDIUM_SCATTER 
            {
                // Sample a distance in the medium
                float scatterDist = min(-log(rand()) / state.medium.density, state.hitDist);
                mediumSampled = scatterDist < state.hitDist;

                if (mediumSampled)
                {
                    throughput *= state.medium.color;

                    // Move ray origin to scattering position
                    r.origin += r.direction * scatterDist;
                    state.fhp = r.origin;

                    // Transmittance Evaluation
                    radiance += DirectLight(r, state, false) * throughput;

                    // Pick a new direction based on the phase function
                    vec3 scatterDir = SampleHG(-r.direction, state.medium.anisotropy, rand(), rand());
                    scatterSample.pdf = PhaseHG(dot(-r.direction, scatterDir), state.medium.anisotropy);
                    r.direction = scatterDir;
                }
            }
        }
        /*如果未对介质进行采样，该函数将检查是否定义了 OPT_ALPHA_TEST 以及是否满足 alpha 截止阈值。*/
        // If medium was not sampled then proceed with surface BSDF evaluation
        if (!mediumSampled)
        {
#endif
#ifdef OPT_ALPHA_TEST
            /*如果是这样，该函数将更新 scatterSample.L 并减小深度。*/
            // Ignore intersection and continue ray based on alpha test
            if ((state.mat.alphaMode == ALPHA_MODE_MASK && state.mat.opacity < state.mat.alphaCutoff) ||
                (state.mat.alphaMode == ALPHA_MODE_BLEND && rand() > state.mat.opacity))
            {
                scatterSample.L = r.direction;
                state.depth--;
            }
            /*否则，该函数将 surfaceScatter 变量设置为 true，从直接照明收集辐射，
            对 BSDF 进行颜色和出射方向采样，并更新吞吐量。*/
            else
#endif
            {
                surfaceScatter = true;

                // Next event estimation
                radiance += DirectLight(r, state, true) * throughput;

                // Sample BSDF for color and outgoing direction
                scatterSample.f = DisneySample(state, -r.direction, state.ffnormal, scatterSample.L, scatterSample.pdf);
                if (scatterSample.pdf > 0.0)
                    throughput *= scatterSample.f / scatterSample.pdf;
                else
                    break;
            }

            // Move ray origin to hit point and set direction for next bounce
            r.direction = scatterSample.L;
            r.origin = state.fhp + r.direction * EPS;
/*
    如果定义了 OPT_MEDIUM，该函数还会检查光线是否进入包含介质的表面并更新 inMedium 和 state.medium 变量。
*/
#ifdef OPT_MEDIUM

            // Note: Nesting of volumes isn't supported due to lack of a volume stack for performance reasons
            // Ray is in medium only if it is entering a surface containing a medium
            if (dot(r.direction, state.normal) < 0 && state.mat.medium.type != MEDIUM_NONE)
            {
                inMedium = true;
                // Get medium params from the intersected object
                state.medium = state.mat.medium;
            }
            // FIXME: Objects clipping or inside a medium were shaded incorrectly as inMedium would be set to false.
            // This hack works for now but needs some rethinking
            else if(state.mat.medium.type != MEDIUM_NONE)
                inMedium = false;
        }
#endif
/*
    如果定义了 OPT_RR，该函数将实现俄罗斯轮盘赌以随机终止超过一定深度的光线。
*/
#ifdef OPT_RR
        // Russian roulette
        if (state.depth >= OPT_RR_DEPTH)
        {
            float q = min(max(throughput.x, max(throughput.y, throughput.z)) + 0.001, 0.95);
            if (rand() > q)
                break;
            throughput /= q;
        }
#endif

    }
/*该函数返回一个包含最终辐射值和 alpha 值的 vec4 对象。*/
    return vec4(radiance, alpha);
}
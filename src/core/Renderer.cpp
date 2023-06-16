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

#include "Config.h"
#include "Renderer.h"
#include "ShaderIncludes.h"
#include "Scene.h"
#include "OpenImageDenoise/oidn.hpp"
#include "assert.h"
#include "cstring"
#include "lightbvh.h"
#include <chrono>
// point cloud
#include <pcl/io/pcd_io.h>
#include <pcl/point_types.h>
#include <pcl/visualization/cloud_viewer.h>
#include <pcl/visualization/pcl_visualizer.h>
// #include <boost/thread/thread.hpp>

char* checkLinkErrors(uint32_t prog, int len, char* buffer)
{
    GLint success;
    glGetProgramiv(prog, GL_LINK_STATUS, &success);
    if (!success) {
        glGetProgramInfoLog(prog, len, nullptr, buffer);
        return buffer;
    }
    return nullptr;
}


namespace GLSLPT
{
    Program *LoadShaders(const ShaderInclude::ShaderSource &vertShaderObj, const ShaderInclude::ShaderSource &fragShaderObj)
    {
        std::vector<Shader> shaders;
        shaders.push_back(Shader(vertShaderObj, GL_VERTEX_SHADER));
        shaders.push_back(Shader(fragShaderObj, GL_FRAGMENT_SHADER));
        return new Program(shaders);
    }

    Renderer::Renderer(Scene *scene, const std::string &shadersDirectory)
        : scene(scene), BVHBuffer(0), BVHTex(0), vertexIndicesBuffer(0), vertexIndicesTex(0), verticesBuffer(0), verticesTex(0), normalsBuffer(0), normalsTex(0), materialsTex(0), transformsTex(0), lightsTex(0), textureMapsArrayTex(0), envMapTex(0), envMapCDFTex(0), pathTraceTextureLowRes(0), pathTraceTexture(0), accumTexture(0), tileOutputTexture(), denoisedTexture(0), pathTraceFBO(0), pathTraceFBOLowRes(0), accumFBO(0), outputFBO(0), shadersDirectory(shadersDirectory), pathTraceShader(nullptr), pathTraceShaderLowRes(nullptr), outputShader(nullptr), tonemapShader(nullptr)
    {
        //wyd
        lightInTex = 0;
        lightOutTex = 0;
        lightPathTex = 0; 
        lightPathBVHBuffer = 0;
        lightPathBVHTex = 0;

        if (scene == nullptr)
        {
            printf("No Scene Found\n");
            return;
        }

        if (!scene->initialized)
            scene->ProcessScene();

        InitGPUDataBuffers();
        quad = new Quad();
        pixelRatio = 0.25f;

        InitFBOs();
        InitShaders();
    }

    Renderer::~Renderer()
    {
        delete quad;
        // Delete textures
        glDeleteTextures(1, &BVHTex);
        glDeleteTextures(1, &lightPathBVHTex);
        glDeleteTextures(1, &vertexIndicesTex);
        glDeleteTextures(1, &verticesTex);
        glDeleteTextures(1, &normalsTex);
        glDeleteTextures(1, &materialsTex);
        glDeleteTextures(1, &transformsTex);
        glDeleteTextures(1, &lightsTex);
        glDeleteTextures(1, &textureMapsArrayTex);
        glDeleteTextures(1, &envMapTex);
        glDeleteTextures(1, &envMapCDFTex);
        glDeleteTextures(1, &pathTraceTexture);
        glDeleteTextures(1, &pathTraceTextureLowRes);
        glDeleteTextures(1, &accumTexture);
        glDeleteTextures(1, &tileOutputTexture[0]);
        glDeleteTextures(1, &tileOutputTexture[1]);
        glDeleteTextures(1, &denoisedTexture);
        // wyd: 
        glDeleteTextures(1, &lightInTex);
        glDeleteTextures(1, &lightOutTex );
        glDeleteTextures(1, &lightPathTex);
        
        // Delete buffers
        glDeleteBuffers(1, &BVHBuffer);
        glDeleteBuffers(1, &lightPathBVHBuffer);
        glDeleteBuffers(1, &vertexIndicesBuffer);
        glDeleteBuffers(1, &verticesBuffer);
        glDeleteBuffers(1, &normalsBuffer);

        // Delete FBOs
        glDeleteFramebuffers(1, &pathTraceFBO);
        glDeleteFramebuffers(1, &pathTraceFBOLowRes);
        glDeleteFramebuffers(1, &accumFBO);
        glDeleteFramebuffers(1, &outputFBO);

        // Delete shaders
        delete pathTraceShader;
        delete pathTraceShaderLowRes;
        delete outputShader;
        delete tonemapShader;

        // Delete denoiser data
        delete[] denoiserInputFramePtr;
        delete[] frameOutputPtr;
        for (int i = 0; i < 100; i++) {
            for (int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH; j++) {
                delete[] lightPathNodes[i][j];
            }
            delete[] lightPathNodes[i];
        }
        delete[] lightPathNodes;

        for (int i = 0;i < 100; i++) {
            delete[] lightPathInfos[i];
        }
    }

    void Renderer::InitGPUDataBuffers()
    {
        {
        glPixelStorei(GL_PACK_ALIGNMENT, 1);

        // Create buffer and texture for BVH
        glGenBuffers(1, &BVHBuffer);
        glBindBuffer(GL_TEXTURE_BUFFER, BVHBuffer);
        glBufferData(GL_TEXTURE_BUFFER, sizeof(RadeonRays::BvhTranslator::Node) * scene->bvhTranslator.nodes.size(), &scene->bvhTranslator.nodes[0], GL_STATIC_DRAW);
        glGenTextures(1, &BVHTex);
        glBindTexture(GL_TEXTURE_BUFFER, BVHTex);
        glTexBuffer(GL_TEXTURE_BUFFER, GL_RGB32F, BVHBuffer);

        // Create buffer and texture for vertex indices
        glGenBuffers(1, &vertexIndicesBuffer);
        glBindBuffer(GL_TEXTURE_BUFFER, vertexIndicesBuffer);
        glBufferData(GL_TEXTURE_BUFFER, sizeof(Indices) * scene->vertIndices.size(), &scene->vertIndices[0], GL_STATIC_DRAW);
        glGenTextures(1, &vertexIndicesTex);
        glBindTexture(GL_TEXTURE_BUFFER, vertexIndicesTex);
        glTexBuffer(GL_TEXTURE_BUFFER, GL_RGB32I, vertexIndicesBuffer);

        // Create buffer and texture for vertices
        glGenBuffers(1, &verticesBuffer);
        glBindBuffer(GL_TEXTURE_BUFFER, verticesBuffer);
        glBufferData(GL_TEXTURE_BUFFER, sizeof(Vec4) * scene->verticesUVX.size(), &scene->verticesUVX[0], GL_STATIC_DRAW);
        glGenTextures(1, &verticesTex);
        glBindTexture(GL_TEXTURE_BUFFER, verticesTex);
        glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA32F, verticesBuffer);

        // Create buffer and texture for normals
        glGenBuffers(1, &normalsBuffer);
        glBindBuffer(GL_TEXTURE_BUFFER, normalsBuffer);
        glBufferData(GL_TEXTURE_BUFFER, sizeof(Vec4) * scene->normalsUVY.size(), &scene->normalsUVY[0], GL_STATIC_DRAW);
        glGenTextures(1, &normalsTex);
        glBindTexture(GL_TEXTURE_BUFFER, normalsTex);
        glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA32F, normalsBuffer);

        // Create texture for materials
        glGenTextures(1, &materialsTex);
        glBindTexture(GL_TEXTURE_2D, materialsTex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (sizeof(Material) / sizeof(Vec4)) * scene->materials.size(), 1, 0, GL_RGBA, GL_FLOAT, &scene->materials[0]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glBindTexture(GL_TEXTURE_2D, 0);

        // Create texture for transforms
        glGenTextures(1, &transformsTex);
        glBindTexture(GL_TEXTURE_2D, transformsTex);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (sizeof(Mat4) / sizeof(Vec4)) * scene->transforms.size(), 1, 0, GL_RGBA, GL_FLOAT, &scene->transforms[0]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glBindTexture(GL_TEXTURE_2D, 0);
        }
        // Create texture for lights
        if (!scene->lights.empty())
        {
            // Create texture for lights
            glGenTextures(1, &lightsTex);
            glBindTexture(GL_TEXTURE_2D, lightsTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, (sizeof(Light) / sizeof(Vec3)) * scene->lights.size(), 1, 0, GL_RGB, GL_FLOAT, &scene->lights[0]);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        // Create texture for scene textures
        if (!scene->textures.empty())
        {
            glGenTextures(1, &textureMapsArrayTex);
            glBindTexture(GL_TEXTURE_2D_ARRAY, textureMapsArrayTex);
            glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RGBA8, scene->renderOptions.texArrayWidth, scene->renderOptions.texArrayHeight, scene->textures.size(), 0, GL_RGBA, GL_UNSIGNED_BYTE, &scene->textureMapsArray[0]);
            glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glBindTexture(GL_TEXTURE_2D_ARRAY, 0);
        }

        // Create texture for environment map
        if (scene->envMap != nullptr)
        {
            glGenTextures(1, &envMapTex);
            glBindTexture(GL_TEXTURE_2D, envMapTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, scene->envMap->width, scene->envMap->height, 0, GL_RGB, GL_FLOAT, scene->envMap->img);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glBindTexture(GL_TEXTURE_2D, 0);

            glGenTextures(1, &envMapCDFTex);
            glBindTexture(GL_TEXTURE_2D, envMapCDFTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, scene->envMap->width, scene->envMap->height, 0, GL_RED, GL_FLOAT, scene->envMap->cdf);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        
        // wyd: 
        lightInPixels = new GLfloat[100 * scene->renderOptions.sc_BDPT_LIGHTPATH * 3];

        lightPathNodes = new float**[100];
        for (int i = 0; i < 100; i++) {
            lightPathNodes[i] = new float*[scene->renderOptions.sc_BDPT_LIGHTPATH];
            for (int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH; j++) {
                lightPathNodes[i][j] = new float[3];
            }
        }

        lightPathInfos = new LightInfo*[100];
        for (int i = 0; i < 100; i++) {
            lightPathInfos[i] = new LightInfo[scene->renderOptions.sc_BDPT_LIGHTPATH];
        }
        // wyd: 

        glGenBuffers(1, &lightPathBuffer);
        glBindBuffer(GL_TEXTURE_BUFFER, lightPathBuffer);
        glBufferData(GL_TEXTURE_BUFFER, sizeof(LightInfo) * 100 * scene->renderOptions.sc_BDPT_LIGHTPATH, &lightPathInfos[0][0], GL_STATIC_DRAW);
        glGenTextures(1, &lightPathTex);
        glBindTexture(GL_TEXTURE_BUFFER, lightPathTex);
        glTexBuffer(GL_TEXTURE_BUFFER, GL_RGB32F, lightPathBuffer);

        // glGenTextures(1, &lightPathTex);
        // glBindTexture(GL_TEXTURE_2D, lightPathTex);
        // glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, (sizeof(LightInfo) / sizeof(Vec3)) * 100 * scene->renderOptions.sc_BDPT_LIGHTPATH, 1, 0, GL_RGB, GL_FLOAT, &lightPathInfos[0][0]);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        // glBindTexture(GL_TEXTURE_2D, 0);


        glGenTextures(1, &lightInTex); 
        glBindTexture(GL_TEXTURE_2D, lightInTex); 
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 100 ,scene->renderOptions.sc_BDPT_LIGHTPATH ,0 , GL_RGB, GL_BYTE, lightInPixels); 
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); 
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); 
        glBindTexture(GL_TEXTURE_2D, 0); 


        glGenTextures(1, &lightOutTex);
        glBindTexture(GL_TEXTURE_2D, lightOutTex);
        glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA32F, 100, scene->renderOptions.sc_BDPT_LIGHTPATH * 7); // wyd update light
        glBindTexture(GL_TEXTURE_2D, 0);

        // Bind textures to texture slots as they will not change slots during the lifespan of the renderer
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_BUFFER, BVHTex);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_BUFFER, vertexIndicesTex);
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_BUFFER, verticesTex);
        glActiveTexture(GL_TEXTURE4);
        glBindTexture(GL_TEXTURE_BUFFER, normalsTex);
        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, materialsTex);
        glActiveTexture(GL_TEXTURE6);
        glBindTexture(GL_TEXTURE_2D, transformsTex);
        glActiveTexture(GL_TEXTURE7);
        glBindTexture(GL_TEXTURE_2D, lightsTex);
        glActiveTexture(GL_TEXTURE8);
        glBindTexture(GL_TEXTURE_2D_ARRAY, textureMapsArrayTex);
        glActiveTexture(GL_TEXTURE9);
        glBindTexture(GL_TEXTURE_2D, envMapTex);
        glActiveTexture(GL_TEXTURE10);
        glBindTexture(GL_TEXTURE_2D, envMapCDFTex);

        //wyd: 

        glActiveTexture(GL_TEXTURE11);
        glBindTexture(GL_TEXTURE_2D, lightInTex);
        glActiveTexture(GL_TEXTURE12);
        glBindTexture(GL_TEXTURE_2D, lightOutTex);
        glActiveTexture(GL_TEXTURE13);
        glBindTexture(GL_TEXTURE_BUFFER, lightPathTex);
        glActiveTexture(GL_TEXTURE14);
        glBindTexture(GL_TEXTURE_BUFFER, lightPathBVHTex);
    }

    void Renderer::ResizeRenderer()
    {
        // Delete textures
        glDeleteTextures(1, &pathTraceTexture);
        glDeleteTextures(1, &pathTraceTextureLowRes);
        glDeleteTextures(1, &accumTexture);
        glDeleteTextures(1, &tileOutputTexture[0]);
        glDeleteTextures(1, &tileOutputTexture[1]);
        glDeleteTextures(1, &denoisedTexture);

        // Delete FBOs
        glDeleteFramebuffers(1, &pathTraceFBO);
        glDeleteFramebuffers(1, &pathTraceFBOLowRes);
        glDeleteFramebuffers(1, &accumFBO);
        glDeleteFramebuffers(1, &outputFBO);

        // Delete denoiser data
        delete[] denoiserInputFramePtr;
        delete[] frameOutputPtr;

        // Delete shaders
        delete pathTraceShader;
        delete pathTraceShaderLowRes;
        delete outputShader;
        delete tonemapShader;

        InitFBOs();
        InitShaders();
    }

    void Renderer::InitFBOs()
    {
        sampleCounter = 1;
        currentBuffer = 0;
        frameCounter = 1;

        renderSize = scene->renderOptions.renderResolution;
        windowSize = scene->renderOptions.windowResolution;

        tileWidth = scene->renderOptions.tileWidth;
        tileHeight = scene->renderOptions.tileHeight;

        invNumTiles.x = (float)tileWidth / renderSize.x;
        invNumTiles.y = (float)tileHeight / renderSize.y;

        numTiles.x = ceil((float)renderSize.x / tileWidth);
        numTiles.y = ceil((float)renderSize.y / tileHeight);

        tile.x = -1;
        tile.y = numTiles.y - 1;

        
        
        // Create FBOs for path trace shader
        glGenFramebuffers(1, &pathTraceFBO); 
        glBindFramebuffer(GL_FRAMEBUFFER, pathTraceFBO); 

        // Create Texture for FBO
        glGenTextures(1, &pathTraceTexture); 
        glBindTexture(GL_TEXTURE_2D, pathTraceTexture); 
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, tileWidth, tileHeight, 0, GL_RGBA, GL_FLOAT, 0); 
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR); 
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR); 
        glBindTexture(GL_TEXTURE_2D, 0); 
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pathTraceTexture, 0); 

        // Create FBOs for low res preview shader
        glGenFramebuffers(1, &pathTraceFBOLowRes);
        glBindFramebuffer(GL_FRAMEBUFFER, pathTraceFBOLowRes);

        // Create Texture for FBO
        glGenTextures(1, &pathTraceTextureLowRes);
        glBindTexture(GL_TEXTURE_2D, pathTraceTextureLowRes);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, windowSize.x * pixelRatio, windowSize.y * pixelRatio, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glBindTexture(GL_TEXTURE_2D, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pathTraceTextureLowRes, 0);

        // Create FBOs for accum buffer
        glGenFramebuffers(1, &accumFBO);
        glBindFramebuffer(GL_FRAMEBUFFER, accumFBO);

        // Create Texture for FBO
        glGenTextures(1, &accumTexture);
        glBindTexture(GL_TEXTURE_2D, accumTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, renderSize.x, renderSize.y, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, accumTexture, 0);

        // Create FBOs for tile output shader
        glGenFramebuffers(1, &outputFBO);
        glBindFramebuffer(GL_FRAMEBUFFER, outputFBO);

        // Create Texture for FBO
        glGenTextures(1, &tileOutputTexture[0]);
        glBindTexture(GL_TEXTURE_2D, tileOutputTexture[0]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, renderSize.x, renderSize.y, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);

        glGenTextures(1, &tileOutputTexture[1]);
        glBindTexture(GL_TEXTURE_2D, tileOutputTexture[1]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, renderSize.x, renderSize.y, 0, GL_RGBA, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);

        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tileOutputTexture[currentBuffer], 0);

        // For Denoiser
        denoiserInputFramePtr = new Vec3[renderSize.x * renderSize.y];
        frameOutputPtr = new Vec3[renderSize.x * renderSize.y];

        glGenTextures(1, &denoisedTexture);
        glBindTexture(GL_TEXTURE_2D, denoisedTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, renderSize.x, renderSize.y, 0, GL_RGB, GL_FLOAT, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glBindTexture(GL_TEXTURE_2D, 0);

        printf("Window Resolution : %d %d\n", windowSize.x, windowSize.y);
        printf("Render Resolution : %d %d\n", renderSize.x, renderSize.y);
        printf("Preview Resolution : %d %d\n", (int)((float)windowSize.x * pixelRatio), (int)((float)windowSize.y * pixelRatio));
        printf("Tile Size : %d %d\n", tileWidth, tileHeight);
    }

    void Renderer::ReloadShaders()
    {
        // Delete shaders
        delete pathTraceShader;
        delete pathTraceShaderLowRes;
        delete outputShader;
        delete tonemapShader;

        InitShaders();
    }

    void Renderer::InitShaders()
    {
        ShaderInclude::ShaderSource vertexShaderSrcObj = ShaderInclude::load(shadersDirectory + "common/vertex.glsl");
        ShaderInclude::ShaderSource pathTraceShaderSrcObj = ShaderInclude::load(shadersDirectory + "tile.glsl");
        ShaderInclude::ShaderSource pathTraceShaderLowResSrcObj = ShaderInclude::load(shadersDirectory + "preview.glsl");
        ShaderInclude::ShaderSource outputShaderSrcObj = ShaderInclude::load(shadersDirectory + "output.glsl");
        ShaderInclude::ShaderSource tonemapShaderSrcObj = ShaderInclude::load(shadersDirectory + "tonemap.glsl");
        //wyd: 
        ShaderInclude::ShaderSource lightShaderSrcObj = ShaderInclude::load(shadersDirectory + "lightcompute.glsl");
        
        // Add preprocessor defines for conditional compilation
        std::string pathtraceDefines = "";
        std::string tonemapDefines = "";

        if (scene->renderOptions.enableEnvMap && scene->envMap != nullptr)
            pathtraceDefines += "#define OPT_ENVMAP\n";

        if (!scene->lights.empty())
            pathtraceDefines += "#define OPT_LIGHTS\n";

        if (scene->renderOptions.enableRR)
        {
            pathtraceDefines += "#define OPT_RR\n";
            pathtraceDefines += "#define OPT_RR_DEPTH " + std::to_string(scene->renderOptions.RRDepth) + "\n";
        }

        // sc:
        if (scene->renderOptions.useBidirectionalPathTracing)
        {
            pathtraceDefines += "#define OPT_BDPT\n";
            int lightPathLength = scene->renderOptions.sc_BDPT_LIGHTPATH;
            int eyePathLength = scene->renderOptions.sc_BDPT_EYEPATH;
            // pathtraceDefines += "#define LIGHTPATHLENGTH " + std::to_string(lightPathLength) + "\n";
            // pathtraceDefines += "#define EYEPATHLENGTH " + std::to_string(eyePathLength) + "\n";
        }
        // scend

        if (scene->renderOptions.enableUniformLight)
            pathtraceDefines += "#define OPT_UNIFORM_LIGHT\n";

        if (scene->renderOptions.openglNormalMap)
            pathtraceDefines += "#define OPT_OPENGL_NORMALMAP\n";

        if (scene->renderOptions.hideEmitters)
            pathtraceDefines += "#define OPT_HIDE_EMITTERS\n";

        if (scene->renderOptions.enableBackground)
        {
            pathtraceDefines += "#define OPT_BACKGROUND\n";
            tonemapDefines += "#define OPT_BACKGROUND\n";
        }

        if (scene->renderOptions.transparentBackground)
        {
            pathtraceDefines += "#define OPT_TRANSPARENT_BACKGROUND\n";
            tonemapDefines += "#define OPT_TRANSPARENT_BACKGROUND\n";
        }

        for (int i = 0; i < scene->materials.size(); i++)
        {
            if ((int)scene->materials[i].alphaMode != AlphaMode::Opaque)
            {
                pathtraceDefines += "#define OPT_ALPHA_TEST\n";
                break;
            }
        }

        if (scene->renderOptions.enableRoughnessMollification)
            pathtraceDefines += "#define OPT_ROUGHNESS_MOLLIFICATION\n";

        for (int i = 0; i < scene->materials.size(); i++)
        {
            if ((int)scene->materials[i].mediumType != MediumType::None)
            {
                pathtraceDefines += "#define OPT_MEDIUM\n";
                break;
            }
        }

        if (scene->renderOptions.enableVolumeMIS)
            pathtraceDefines += "#define OPT_VOL_MIS\n";

        if (pathtraceDefines.size() > 0)
        {
            size_t idx = pathTraceShaderSrcObj.src.find("#version");
            if (idx != -1)
                idx = pathTraceShaderSrcObj.src.find("\n", idx);
            else
                idx = 0;
            pathTraceShaderSrcObj.src.insert(idx + 1, pathtraceDefines);

            idx = pathTraceShaderLowResSrcObj.src.find("#version");
            if (idx != -1)
                idx = pathTraceShaderLowResSrcObj.src.find("\n", idx);
            else
                idx = 0;
            pathTraceShaderLowResSrcObj.src.insert(idx + 1, pathtraceDefines);
        }

        if (tonemapDefines.size() > 0)
        {
            size_t idx = tonemapShaderSrcObj.src.find("#version");
            if (idx != -1)
                idx = tonemapShaderSrcObj.src.find("\n", idx);
            else
                idx = 0;
            tonemapShaderSrcObj.src.insert(idx + 1, tonemapDefines);
        }

        pathTraceShader = LoadShaders(vertexShaderSrcObj, pathTraceShaderSrcObj);
        pathTraceShaderLowRes = LoadShaders(vertexShaderSrcObj, pathTraceShaderLowResSrcObj);
        outputShader = LoadShaders(vertexShaderSrcObj, outputShaderSrcObj);
        tonemapShader = LoadShaders(vertexShaderSrcObj, tonemapShaderSrcObj);

        // wyd: 
        lightComputeShader = glCreateShader(GL_COMPUTE_SHADER);
        const char* const srcs[] = { lightShaderSrcObj.src.c_str() };
        // printf("srcs: %s\n", srcs[0]);
        glShaderSource(lightComputeShader, 1, srcs, nullptr);
        glCompileShader(lightComputeShader);


        // Setup shader uniforms
        GLuint shaderObject;
        pathTraceShader->Use();
        shaderObject = pathTraceShader->getObject();

        if (scene->envMap)
        {
            glUniform2f(glGetUniformLocation(shaderObject, "envMapRes"), (float)scene->envMap->width, (float)scene->envMap->height);
            glUniform1f(glGetUniformLocation(shaderObject, "envMapTotalSum"), scene->envMap->totalSum);
        }

        glUniform1i(glGetUniformLocation(shaderObject, "topBVHIndex"), scene->bvhTranslator.topLevelIndex);
        glUniform2f(glGetUniformLocation(shaderObject, "resolution"), float(renderSize.x), float(renderSize.y));
        glUniform2f(glGetUniformLocation(shaderObject, "invNumTiles"), invNumTiles.x, invNumTiles.y);
        glUniform1i(glGetUniformLocation(shaderObject, "numOfLights"), scene->lights.size());
        glUniform1i(glGetUniformLocation(shaderObject, "accumTexture"), 0);
        glUniform1i(glGetUniformLocation(shaderObject, "BVH"), 1);
        glUniform1i(glGetUniformLocation(shaderObject, "vertexIndicesTex"), 2);
        glUniform1i(glGetUniformLocation(shaderObject, "verticesTex"), 3);
        glUniform1i(glGetUniformLocation(shaderObject, "normalsTex"), 4);
        glUniform1i(glGetUniformLocation(shaderObject, "materialsTex"), 5);
        glUniform1i(glGetUniformLocation(shaderObject, "transformsTex"), 6);
        glUniform1i(glGetUniformLocation(shaderObject, "lightsTex"), 7);
        glUniform1i(glGetUniformLocation(shaderObject, "textureMapsArrayTex"), 8);
        glUniform1i(glGetUniformLocation(shaderObject, "envMapTex"), 9);
        glUniform1i(glGetUniformLocation(shaderObject, "envMapCDFTex"), 10);
        // wyd: 
        glUniform1i(glGetUniformLocation(shaderObject, "lightPathTex"), 13); 
        glUniform1i(glGetUniformLocation(shaderObject, "lightPathBVHTex"), 14);
        pathTraceShader->StopUsing();

        pathTraceShaderLowRes->Use();
        shaderObject = pathTraceShaderLowRes->getObject();

        if (scene->envMap)
        {
            glUniform2f(glGetUniformLocation(shaderObject, "envMapRes"), (float)scene->envMap->width, (float)scene->envMap->height);
            glUniform1f(glGetUniformLocation(shaderObject, "envMapTotalSum"), scene->envMap->totalSum);
        }
        glUniform1i(glGetUniformLocation(shaderObject, "topBVHIndex"), scene->bvhTranslator.topLevelIndex);
        glUniform2f(glGetUniformLocation(shaderObject, "resolution"), float(renderSize.x), float(renderSize.y));
        glUniform1i(glGetUniformLocation(shaderObject, "numOfLights"), scene->lights.size());
        glUniform1i(glGetUniformLocation(shaderObject, "accumTexture"), 0);
        glUniform1i(glGetUniformLocation(shaderObject, "BVH"), 1);
        glUniform1i(glGetUniformLocation(shaderObject, "vertexIndicesTex"), 2);
        glUniform1i(glGetUniformLocation(shaderObject, "verticesTex"), 3);
        glUniform1i(glGetUniformLocation(shaderObject, "normalsTex"), 4);
        glUniform1i(glGetUniformLocation(shaderObject, "materialsTex"), 5);
        glUniform1i(glGetUniformLocation(shaderObject, "transformsTex"), 6);
        glUniform1i(glGetUniformLocation(shaderObject, "lightsTex"), 7);
        glUniform1i(glGetUniformLocation(shaderObject, "textureMapsArrayTex"), 8);
        glUniform1i(glGetUniformLocation(shaderObject, "envMapTex"), 9);
        glUniform1i(glGetUniformLocation(shaderObject, "envMapCDFTex"), 10);
        // wyd: 
        glUniform1i(glGetUniformLocation(shaderObject, "lightPathTex"), 13); 
        glUniform1i(glGetUniformLocation(shaderObject, "lightPathBVHTex"), 14);
        pathTraceShaderLowRes->StopUsing();
    }

    void Renderer::Render()
    {
        // If maxSpp was reached then stop rendering.
        // TODO: Tonemapping and denosing still need to be able to run on final image
        if (!scene->dirty && scene->renderOptions.maxSpp != -1 && sampleCounter >= scene->renderOptions.maxSpp)
            return;

        glActiveTexture(GL_TEXTURE0);

        if (scene->dirty)
        {
            // wyd 
            uint32_t compProg = glCreateProgram();

            glAttachShader(compProg, lightComputeShader);
            glLinkProgram(compProg);

            glDetachShader(compProg, lightComputeShader);
            glDeleteShader(lightComputeShader);

            int len = 1005; 
            char buffer[1005]; 
            memset(buffer, 0, len);

            checkLinkErrors(compProg, len, buffer);
            if(strlen(buffer) > 0)
            {
                printf("link error: %s\n", buffer);
                exit(1); 
            }
            {
            glUseProgram(compProg);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, lightInTex);
            glBindImageTexture(0, lightOutTex, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);      
            
            glUniform1i(glGetUniformLocation(compProg, "topBVHIndex"), scene->bvhTranslator.topLevelIndex);
            glUniform2f(glGetUniformLocation(compProg, "resolution"), float(renderSize.x), float(renderSize.y));
            glUniform2f(glGetUniformLocation(compProg, "invNumTiles"), invNumTiles.x, invNumTiles.y);
            glUniform1i(glGetUniformLocation(compProg, "numOfLights"), scene->lights.size());
            glUniform1i(glGetUniformLocation(compProg, "accumTexture"), 0);
            glUniform1i(glGetUniformLocation(compProg, "BVH"), 1);
            glUniform1i(glGetUniformLocation(compProg, "vertexIndicesTex"), 2);
            glUniform1i(glGetUniformLocation(compProg, "verticesTex"), 3);
            glUniform1i(glGetUniformLocation(compProg, "normalsTex"), 4);
            glUniform1i(glGetUniformLocation(compProg, "materialsTex"), 5);
            glUniform1i(glGetUniformLocation(compProg, "transformsTex"), 6);
            glUniform1i(glGetUniformLocation(compProg, "lightsTex"), 7);
            glUniform1i(glGetUniformLocation(compProg, "textureMapsArrayTex"), 8);
            glUniform1i(glGetUniformLocation(compProg, "envMapTex"), 9);
            glUniform1i(glGetUniformLocation(compProg, "envMapCDFTex"), 10);
            //wyd: 
            

            glUniform1i(glGetUniformLocation(compProg, "enableEnvMap"), scene->envMap == nullptr ? false : scene->renderOptions.enableEnvMap);
            glUniform1f(glGetUniformLocation(compProg, "envMapIntensity"), scene->renderOptions.envMapIntensity);
            glUniform1f(glGetUniformLocation(compProg, "envMapRot"), scene->renderOptions.envMapRot / 360.0f);
            glUniform1i(glGetUniformLocation(compProg, "maxDepth"), scene->renderOptions.maxDepth);
            glUniform1i(glGetUniformLocation(compProg, "LIGHTPATHLENGTH"), scene->renderOptions.sc_BDPT_LIGHTPATH); // sc:
            glUniform1i(glGetUniformLocation(compProg, "EYEPATHLENGTH"), scene->renderOptions.sc_BDPT_EYEPATH);     // sc:
            glUniform2f(glGetUniformLocation(compProg, "tileOffset"), (float)tile.x * invNumTiles.x, (float)tile.y * invNumTiles.y);
            glUniform3f(glGetUniformLocation(compProg, "uniformLightCol"), scene->renderOptions.uniformLightCol.x, scene->renderOptions.uniformLightCol.y, scene->renderOptions.uniformLightCol.z);
            glUniform1f(glGetUniformLocation(compProg, "roughnessMollificationAmt"), scene->renderOptions.roughnessMollificationAmt);
            glUniform1i(glGetUniformLocation(compProg, "frameNum"), frameCounter);

            glUniform1i(glGetUniformLocation(compProg, "u_inputTex"), 0); 
            glUniform1i(glGetUniformLocation(compProg, "u_outImg"), 0); 

            
            glDispatchCompute((100+31)/32, (scene->renderOptions.sc_BDPT_LIGHTPATH+31)/32, 1);
            
            glMemoryBarrier(GL_TEXTURE_UPDATE_BARRIER_BIT);
            }
            // wyd:
            GLfloat* img = new GLfloat[100 * scene->renderOptions.sc_BDPT_LIGHTPATH * 4 * 7]; // wyd: update light
            glBindTexture(GL_TEXTURE_2D, lightOutTex);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_FLOAT, img);
            
            /*
                struct LightInfo
                {
                    Vec3 radiance;
                    Vec3 normal;
                    Vec3 ffnormal;
                    Vec3 direction; 
                    float eta; 
                    int matID; 
                    int avaliable;
                };
            */

            for(int i = 0; i < 100;  i++){ 
                for(int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH; j++){

                    lightPathInfos[i][j].position = 
                    Vec3(
                        img[i * 4 + j * 4 *100 + 0],
                        img[i * 4 + j * 4 *100 + 1],
                        img[i * 4 + j * 4 *100 + 2] 
                    );
                    lightPathInfos[i][j].radiance = 
                    Vec3(
                        img[i * 4 + (j + 3) * 4 *100 + 0],
                        img[i * 4 + (j + 3) * 4 *100 + 1],
                        img[i * 4 + (j + 3) * 4 *100 + 2] 
                    );
                    lightPathInfos[i][j].normal = 
                    Vec3(
                        img[i * 4 + (j + 6) * 4 *100 + 0],
                        img[i * 4 + (j + 6) * 4 *100 + 1],
                        img[i * 4 + (j + 6) * 4 *100 + 2] 
                    );
                    lightPathInfos[i][j].ffnormal = 
                    Vec3(
                        img[i * 4 + (j + 9) * 4 *100 + 0],
                        img[i * 4 + (j + 9) * 4 *100 + 1],
                        img[i * 4 + (j + 9) * 4 *100 + 2] 
                    );
                    lightPathInfos[i][j].direction = 
                    Vec3(
                        img[i * 4 + (j + 12) * 4 *100 + 0],
                        img[i * 4 + (j + 12) * 4 *100 + 1],
                        img[i * 4 + (j + 12) * 4 *100 + 2] 
                    );
                    lightPathInfos[i][j].eta = img[i * 4 + (j + 15) * 4 *100 + 0]; 
                    lightPathInfos[i][j].matID = int(img[i * 4 + (j + 15) * 4 *100 + 1]); 
                    lightPathInfos[i][j].avaliable = int(img[i * 4 + (j + 15) * 4 *100 + 2]); 
                    lightPathInfos[i][j].texCoods =
                    Vec2(
                        img[i * 4 + (j + 18) * 4 *100 + 0],
                        img[i * 4 + (j + 18) * 4 *100 + 1]
                    );
                    lightPathInfos[i][j].matroughness = img[i * 4 + (j + 18) * 4 *100 + 2];
                }
            }   
            


            // wyd: 
            // print to check lightPathNodes
            // freopen("out.txt", "w", stdout);
            // for(int i = 0; i < 100; i++){
            //     for(int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH; j++){
            //         printf("lightPathInfos[%d][%d].position = %f %f %f\n", i,j,
            //         lightPathInfos[i][j].position.x, lightPathInfos[i][j].position.y, lightPathInfos[i][j].position.z);
                    // printf("lightPathInfos[%d][%d].radiance = %f %f %f\n", i,j,
                    // lightPathInfos[i][j].radiance.x, lightPathInfos[i][j].radiance.y, lightPathInfos[i][j].radiance.z);
                    // printf("lightPathInfos[%d][%d].normal = %f %f %f\n", i,j,
                    // lightPathInfos[i][j].normal.x, lightPathInfos[i][j].normal.y, lightPathInfos[i][j].normal.z);
                    // printf("lightPathInfos[%d][%d].ffnormal = %f %f %f\n", i,j,
                    // lightPathInfos[i][j].ffnormal.x, lightPathInfos[i][j].ffnormal.y, lightPathInfos[i][j].ffnormal.z);
                    // printf("lightPathInfos[%d][%d].direction = %f %f %f\n", i,j,
                    // lightPathInfos[i][j].direction.x, lightPathInfos[i][j].direction.y, lightPathInfos[i][j].direction.z);
                    // printf("lightPathInfos[%d][%d].eta = %f\n", i,j,lightPathInfos[i][j].eta); 
                    // printf("lightPathInfos[%d][%d].matID = %d\n", i,j,lightPathInfos[i][j].matID); 
                    // printf("lightPathInfos[%d][%d].avaliable = %d\n", i,j,lightPathInfos[i][j].avaliable); 
                    // printf("lightPathInfos[%d][%d].texCoods = %f %f\n", i,j,
                    // lightPathInfos[i][j].texCoods.x, lightPathInfos[i][j].texCoods.y);
                    // printf("lightPathInfos[%d][%d].matroughness = %f\n", i,j,lightPathInfos[i][j].matroughness);
            //     }
            // }
            // freopen("CON","w",stdout);


            // print image to check memory allocation
            // freopen("out.txt", "w", stdout);
            // for(int i = 0; i < 100; i++){
            //     for(int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH * 6; j++){
            //         printf("img[%d][%d] = %f %f %f %f\n", i, j, img[i * 4 + j * 4 *100 + 0], img[i * 4 + j * 4 *100 + 1], img[i * 4 + j * 4 *100 + 2], img[i * 4 + j * 4 *100 + 3]);
            //     }
            // }


            // construct bvh
            std::vector<Point3f> pts; 
            for(int i = 0; i < 100;  i++){
                for(int j = 0; j < scene->renderOptions.sc_BDPT_LIGHTPATH; j++){
                    pts.push_back(Point3f(lightPathInfos[i][j].position.x, 
                                          lightPathInfos[i][j].position.y, 
                                          lightPathInfos[i][j].position.z));
                }
            }

            // output pts value
            // freopen("out.txt", "w", stdout);
            // for(int i = 0; i < pts.size(); i++){
            //     printf("pts[%d] = %f %f %f\n", i, pts[i].x, pts[i].y, pts[i].z);
            // }


            // point cloud visualization
            
            pcl::PointCloud<pcl::PointXYZ> cloud;
            cloud.width = 100 * scene->renderOptions.sc_BDPT_LIGHTPATH;
            cloud.height = 1;
            cloud.is_dense = false;
            cloud.points.resize(cloud.width * cloud.height);
            for (size_t i = 0; i < cloud.points.size(); ++i)
            {
                cloud.points[i].x = pts[i].x;
                cloud.points[i].y = pts[i].y;
                cloud.points[i].z = pts[i].z;
            }

            pcl::io::savePCDFileASCII("selfgen.pcd", cloud);


            pcl::PointCloud<pcl::PointXYZ>::Ptr cloud2(new pcl::PointCloud<pcl::PointXYZ>);
        
            if (pcl::io::loadPCDFile<pcl::PointXYZ>("selfgen.pcd", *cloud2) == -1)//*打开点云文件
            {
                PCL_ERROR("Couldn't read file test_pcd.pcd\n");
            }

            pcl::visualization::PCLVisualizer::Ptr viewer(new pcl::visualization::PCLVisualizer("viewer"));
            viewer->addCoordinateSystem(1); 

            viewer->addPointCloud(cloud2);

            viewer->spin();
            

            auto beforeTime = std::chrono::steady_clock::now();

            BVH_ACC1 bvh_lightpath(pts,0.03,0.07);
            auto afterTime = std::chrono::steady_clock::now();
            double duration_millsecond = std::chrono::duration<double, std::milli>(afterTime - beforeTime).count();
            printf("bvh construction time: %f ms\n", duration_millsecond);
            LinearBVHNode* bvh_nodes = bvh_lightpath.nodes; 

            glGenBuffers(1, &lightPathBVHBuffer);
            glBindBuffer(GL_TEXTURE_BUFFER, lightPathBVHBuffer);
            glBufferData(GL_TEXTURE_BUFFER, sizeof(LinearBVHNode) * bvh_lightpath.totalNodes, &bvh_nodes[0], GL_STATIC_DRAW);
            glGenTextures(1, &lightPathBVHTex);
            glBindTexture(GL_TEXTURE_BUFFER, lightPathBVHTex);
            glTexBuffer(GL_TEXTURE_BUFFER, GL_RGB32F, lightPathBVHBuffer);

            delete[] img;

            glUseProgram(0);

            // Renders a low res preview if camera/instances are modified
            glBindFramebuffer(GL_FRAMEBUFFER, pathTraceFBOLowRes);
            glViewport(0, 0, windowSize.x * pixelRatio, windowSize.y * pixelRatio);
            quad->Draw(pathTraceShaderLowRes);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);

            

            scene->instancesModified = false;
            scene->dirty = false;
            scene->envMapModified = false;
        }
        else
        {
            // Renders to pathTraceTexture while using previously accumulated samples from accumTexture
            // Rendering is done a tile per frame, so if a 500x500 image is rendered with a tileWidth and tileHeight of 250 then, all tiles (for a single sample)
            // get rendered after 4 frames
            glBindFramebuffer(GL_FRAMEBUFFER, pathTraceFBO);
            glViewport(0, 0, tileWidth, tileHeight);
            glBindTexture(GL_TEXTURE_2D, accumTexture);
            quad->Draw(pathTraceShader);

            // pathTraceTexture is copied to accumTexture and re-used as input for the first step.
            glBindFramebuffer(GL_FRAMEBUFFER, accumFBO);
            glViewport(tileWidth * tile.x, tileHeight * tile.y, tileWidth, tileHeight);
            glBindTexture(GL_TEXTURE_2D, pathTraceTexture);
            quad->Draw(outputShader);

            // Here we render to tileOutputTexture[currentBuffer] but display tileOutputTexture[1-currentBuffer] until all tiles are done rendering
            // When all tiles are rendered, we flip the bound texture and start rendering to the other one
            glBindFramebuffer(GL_FRAMEBUFFER, outputFBO);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tileOutputTexture[currentBuffer], 0);
            glViewport(0, 0, renderSize.x, renderSize.y);
            glBindTexture(GL_TEXTURE_2D, accumTexture);
            quad->Draw(tonemapShader);
        }
    }

    void Renderer::Present()
    {
        glActiveTexture(GL_TEXTURE0);

        // For the first sample or if the camera is moving, we do not have an image ready with all the tiles rendered, so we display a low res preview.
        if (scene->dirty || sampleCounter == 1)
        {
            glBindTexture(GL_TEXTURE_2D, pathTraceTextureLowRes);
            quad->Draw(tonemapShader);
        }
        else
        {
            if (scene->renderOptions.enableDenoiser && denoised)
                glBindTexture(GL_TEXTURE_2D, denoisedTexture);
            else
                glBindTexture(GL_TEXTURE_2D, tileOutputTexture[1 - currentBuffer]);

            quad->Draw(outputShader);
        }
    }

    float Renderer::GetProgress()
    {
        int maxSpp = scene->renderOptions.maxSpp;
        return maxSpp <= 0 ? 0.0f : sampleCounter * 100.0f / maxSpp;
    }

    void Renderer::GetOutputBuffer(unsigned char **data, int &w, int &h)
    {
        w = renderSize.x;
        h = renderSize.y;

        *data = new unsigned char[w * h * 4];

        glActiveTexture(GL_TEXTURE0);

        if (scene->renderOptions.enableDenoiser && denoised)
            glBindTexture(GL_TEXTURE_2D, denoisedTexture);
        else
            glBindTexture(GL_TEXTURE_2D, tileOutputTexture[1 - currentBuffer]);

        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, *data);
    }

    int Renderer::GetSampleCount()
    {
        return sampleCounter;
    }

    void Renderer::Update(float secondsElapsed)
    {
        // If maxSpp was reached then stop updates
        // TODO: Tonemapping and denosing still need to be able to run on final image
        if (!scene->dirty && scene->renderOptions.maxSpp != -1 && sampleCounter >= scene->renderOptions.maxSpp)
            return;

        // Update data for instances
        if (scene->instancesModified)
        {
            // Update transforms
            glBindTexture(GL_TEXTURE_2D, transformsTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (sizeof(Mat4) / sizeof(Vec4)) * scene->transforms.size(), 1, 0, GL_RGBA, GL_FLOAT, &scene->transforms[0]);

            // Update materials
            glBindTexture(GL_TEXTURE_2D, materialsTex);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (sizeof(Material) / sizeof(Vec4)) * scene->materials.size(), 1, 0, GL_RGBA, GL_FLOAT, &scene->materials[0]);

            // Update top level BVH
            int index = scene->bvhTranslator.topLevelIndex;
            int offset = sizeof(RadeonRays::BvhTranslator::Node) * index;
            int size = sizeof(RadeonRays::BvhTranslator::Node) * (scene->bvhTranslator.nodes.size() - index);
            glBindBuffer(GL_TEXTURE_BUFFER, BVHBuffer);
            glBufferSubData(GL_TEXTURE_BUFFER, offset, size, &scene->bvhTranslator.nodes[index]);
        }

        // Recreate texture for envmaps
        if (scene->envMapModified)
        {
            // Create texture for environment map
            if (scene->envMap != nullptr)
            {
                glBindTexture(GL_TEXTURE_2D, envMapTex);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, scene->envMap->width, scene->envMap->height, 0, GL_RGB, GL_FLOAT, scene->envMap->img);

                glBindTexture(GL_TEXTURE_2D, envMapCDFTex);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, scene->envMap->width, scene->envMap->height, 0, GL_RED, GL_FLOAT, scene->envMap->cdf);

                GLuint shaderObject;
                pathTraceShader->Use();
                shaderObject = pathTraceShader->getObject();
                glUniform2f(glGetUniformLocation(shaderObject, "envMapRes"), (float)scene->envMap->width, (float)scene->envMap->height);
                glUniform1f(glGetUniformLocation(shaderObject, "envMapTotalSum"), scene->envMap->totalSum);
                pathTraceShader->StopUsing();

                pathTraceShaderLowRes->Use();
                shaderObject = pathTraceShaderLowRes->getObject();
                glUniform2f(glGetUniformLocation(shaderObject, "envMapRes"), (float)scene->envMap->width, (float)scene->envMap->height);
                glUniform1f(glGetUniformLocation(shaderObject, "envMapTotalSum"), scene->envMap->totalSum);
                pathTraceShaderLowRes->StopUsing();
            }
        }

        // Denoise image if requested
        if (scene->renderOptions.enableDenoiser && sampleCounter > 1)
        {
            if (!denoised || (frameCounter % (scene->renderOptions.denoiserFrameCnt * (numTiles.x * numTiles.y)) == 0))
            {
                // FIXME: Figure out a way to have transparency with denoiser
                glBindTexture(GL_TEXTURE_2D, tileOutputTexture[1 - currentBuffer]);
                glGetTexImage(GL_TEXTURE_2D, 0, GL_RGB, GL_FLOAT, denoiserInputFramePtr);

                // Create an Intel Open Image Denoise device
                oidn::DeviceRef device = oidn::newDevice();
                device.commit();

                // Create a denoising filter
                oidn::FilterRef filter = device.newFilter("RT"); // generic ray tracing filter
                filter.setImage("color", denoiserInputFramePtr, oidn::Format::Float3, renderSize.x, renderSize.y, 0, 0, 0);
                filter.setImage("output", frameOutputPtr, oidn::Format::Float3, renderSize.x, renderSize.y, 0, 0, 0);
                filter.set("hdr", false);
                filter.commit();

                // Filter the image
                filter.execute();

                // Check for errors
                const char *errorMessage;
                if (device.getError(errorMessage) != oidn::Error::None)
                    std::cout << "Error: " << errorMessage << std::endl;

                // Copy the denoised data to denoisedTexture
                glBindTexture(GL_TEXTURE_2D, denoisedTexture);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB32F, renderSize.x, renderSize.y, 0, GL_RGB, GL_FLOAT, frameOutputPtr);

                denoised = true;
            }
        }
        else
            denoised = false;

        // If scene was modified then clear out image for re-rendering
        if (scene->dirty)
        {
            tile.x = -1;
            tile.y = numTiles.y - 1;
            sampleCounter = 1;
            denoised = false;
            frameCounter = 1;

            // Clear out the accumulated texture for rendering a new image
            glBindFramebuffer(GL_FRAMEBUFFER, accumFBO);
            glClear(GL_COLOR_BUFFER_BIT);
        }
        else // Update render state
        {
            frameCounter++;
            tile.x++;
            if (tile.x >= numTiles.x)
            {
                tile.x = 0;
                tile.y--;
                if (tile.y < 0)
                {
                    // If we've reached here, it means all the tiles have been rendered (for a single sample) and the image can now be displayed.
                    tile.x = 0;
                    tile.y = numTiles.y - 1;
                    sampleCounter++;
                    currentBuffer = 1 - currentBuffer;
                }
            }
        }

        // Update uniforms

        GLuint shaderObject;
        pathTraceShader->Use();
        shaderObject = pathTraceShader->getObject();
        glUniform3f(glGetUniformLocation(shaderObject, "camera.position"), scene->camera->position.x, scene->camera->position.y, scene->camera->position.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.right"), scene->camera->right.x, scene->camera->right.y, scene->camera->right.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.up"), scene->camera->up.x, scene->camera->up.y, scene->camera->up.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.forward"), scene->camera->forward.x, scene->camera->forward.y, scene->camera->forward.z);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.fov"), scene->camera->fov);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.focalDist"), scene->camera->focalDist);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.aperture"), scene->camera->aperture);
        glUniform1i(glGetUniformLocation(shaderObject, "enableEnvMap"), scene->envMap == nullptr ? false : scene->renderOptions.enableEnvMap);
        glUniform1f(glGetUniformLocation(shaderObject, "envMapIntensity"), scene->renderOptions.envMapIntensity);
        glUniform1f(glGetUniformLocation(shaderObject, "envMapRot"), scene->renderOptions.envMapRot / 360.0f);
        glUniform1i(glGetUniformLocation(shaderObject, "maxDepth"), scene->renderOptions.maxDepth);
        glUniform1i(glGetUniformLocation(shaderObject, "LIGHTPATHLENGTH"), scene->renderOptions.sc_BDPT_LIGHTPATH); // sc:
        glUniform1i(glGetUniformLocation(shaderObject, "EYEPATHLENGTH"), scene->renderOptions.sc_BDPT_EYEPATH);     // sc:
        glUniform2f(glGetUniformLocation(shaderObject, "tileOffset"), (float)tile.x * invNumTiles.x, (float)tile.y * invNumTiles.y);
        glUniform3f(glGetUniformLocation(shaderObject, "uniformLightCol"), scene->renderOptions.uniformLightCol.x, scene->renderOptions.uniformLightCol.y, scene->renderOptions.uniformLightCol.z);
        glUniform1f(glGetUniformLocation(shaderObject, "roughnessMollificationAmt"), scene->renderOptions.roughnessMollificationAmt);
        glUniform1i(glGetUniformLocation(shaderObject, "frameNum"), frameCounter);
        pathTraceShader->StopUsing();

        pathTraceShaderLowRes->Use();
        shaderObject = pathTraceShaderLowRes->getObject();
        glUniform3f(glGetUniformLocation(shaderObject, "camera.position"), scene->camera->position.x, scene->camera->position.y, scene->camera->position.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.right"), scene->camera->right.x, scene->camera->right.y, scene->camera->right.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.up"), scene->camera->up.x, scene->camera->up.y, scene->camera->up.z);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.forward"), scene->camera->forward.x, scene->camera->forward.y, scene->camera->forward.z);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.fov"), scene->camera->fov);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.focalDist"), scene->camera->focalDist);
        glUniform1f(glGetUniformLocation(shaderObject, "camera.aperture"), scene->camera->aperture);
        glUniform1i(glGetUniformLocation(shaderObject, "enableEnvMap"), scene->envMap == nullptr ? false : scene->renderOptions.enableEnvMap);
        glUniform1f(glGetUniformLocation(shaderObject, "envMapIntensity"), scene->renderOptions.envMapIntensity);
        glUniform1f(glGetUniformLocation(shaderObject, "envMapRot"), scene->renderOptions.envMapRot / 360.0f);
        glUniform1i(glGetUniformLocation(shaderObject, "maxDepth"), scene->dirty ? 2 : scene->renderOptions.maxDepth);
        glUniform1i(glGetUniformLocation(shaderObject, "LIGHTPATHLENGTH"), scene->dirty ? 3 : scene->renderOptions.sc_BDPT_LIGHTPATH);
        glUniform1i(glGetUniformLocation(shaderObject, "EYEPATHLENGTH"), scene->dirty ? 3 : scene->renderOptions.sc_BDPT_EYEPATH);
        glUniform3f(glGetUniformLocation(shaderObject, "camera.position"), scene->camera->position.x, scene->camera->position.y, scene->camera->position.z);
        glUniform3f(glGetUniformLocation(shaderObject, "uniformLightCol"), scene->renderOptions.uniformLightCol.x, scene->renderOptions.uniformLightCol.y, scene->renderOptions.uniformLightCol.z);
        glUniform1f(glGetUniformLocation(shaderObject, "roughnessMollificationAmt"), scene->renderOptions.roughnessMollificationAmt);
        pathTraceShaderLowRes->StopUsing();

        tonemapShader->Use();
        shaderObject = tonemapShader->getObject();
        glUniform1f(glGetUniformLocation(shaderObject, "invSampleCounter"), 1.0f / (sampleCounter));
        glUniform1i(glGetUniformLocation(shaderObject, "enableTonemap"), scene->renderOptions.enableTonemap);
        glUniform1i(glGetUniformLocation(shaderObject, "enableAces"), scene->renderOptions.enableAces);
        glUniform1i(glGetUniformLocation(shaderObject, "simpleAcesFit"), scene->renderOptions.simpleAcesFit);
        glUniform3f(glGetUniformLocation(shaderObject, "backgroundCol"), scene->renderOptions.backgroundCol.x, scene->renderOptions.backgroundCol.y, scene->renderOptions.backgroundCol.z);
        tonemapShader->StopUsing();
    }
}
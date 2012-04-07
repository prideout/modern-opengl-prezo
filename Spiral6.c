#include <stdlib.h>
#include "pez.h"
#include "vmath.h"

struct SceneParameters {
    int IndexCount;
    float Theta;
    Matrix4 Projection;
    Matrix4 Modelview;
    Matrix4 ViewMatrix;
    Matrix4 ModelMatrix;
    Matrix3 NormalMatrix;
    GLfloat PackedNormalMatrix[9];
} Scene;

static GLuint LoadProgram(const char* vsKey, const char* tcsKey, const char* tesKey, const char* gsKey, const char* fsKey);
static GLuint CurrentProgram();

#define u(x) glGetUniformLocation(CurrentProgram(), x)
#define a(x) glGetAttribLocation(CurrentProgram(), x)

PezConfig PezGetConfig()
{
    PezConfig config;
    config.Title = __FILE__;
    config.Width = 800*2;
    config.Height = 600*2;
    config.Multisampling = true;
    config.VerticalSync = true;
    return config;
}

// u and v in [0,2π] 
// x(u,v) = α (1-v/(2π)) cos(n v) (1 + cos(u)) + γ cos(n v)
// y(u,v) = α (1-v/(2π)) sin(n v) (1 + cos(u)) + γ sin(n v)
// z(u,v) = α (1-v/(2π)) sin(u) + β v/(2π)
Point3 ParametricHorn(float u, float v, float alpha, float beta, float gamma, float n)
{
    float x = alpha * (1-v/TwoPi) * cos(n*v) * (1+cos(u)) + gamma * cos(n*v);
    float y = alpha * (1-v/TwoPi) * sin(n*v) * (1+cos(u)) + gamma * sin(n*v);
    float z = alpha * (1-v/TwoPi) * sin(u) + beta * v / TwoPi;
    return (Point3){x, y, z};
}

static void CreateTorus(float major, float minor, int slices, int stacks)
{
    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);

    int vertexCount = slices * stacks * 3;
    int vertexStride = sizeof(float) * 3;
    GLsizeiptr size = vertexCount * vertexStride;
    GLfloat* positions = (GLfloat*) malloc(size);

    GLfloat* position = positions;
    for (int slice = 0; slice < slices; slice++) {
        float v = slice * TwoPi / slices;
        for (int stack = 0; stack < stacks; stack++) {
            float u = stack * TwoPi / (stacks - 1);
            
            float alpha = 0.8;   // 0.15 for horn, 1.0 for snail
            float beta = 1;
            float gamma = 0.1; // tightness
            float n = 2;       // twists

            Point3 p = ParametricHorn(u, v, alpha, beta, gamma, n);
            *position++ = u;//p.x;
            *position++ = v;//p.y;
            *position++ = 0;//p.z;
        }
    }

    GLuint handle;
    glGenBuffers(1, &handle);
    glBindBuffer(GL_ARRAY_BUFFER, handle);
    glBufferData(GL_ARRAY_BUFFER, size, positions, GL_STATIC_DRAW);
    glEnableVertexAttribArray(a("Position"));
    glVertexAttribPointer(a("Position"), 3, GL_FLOAT, GL_FALSE,
                          vertexStride, 0);

    free(positions);

    Scene.IndexCount = (slices-1) * (stacks-1) * 6;
    size = Scene.IndexCount * sizeof(GLushort);
    GLushort* indices = (GLushort*) malloc(size);
    GLushort* index = indices;
    int v = 0;
    for (int i = 0; i < slices - 1; i++) {
        for (int j = 0; j < stacks - 1; j++) {
            int next = j + 1;
            *index++ = v+next+stacks; *index++ = v+next; *index++ = v+j;
            *index++ = v+j; *index++ = v+j+stacks; *index++ = v+next+stacks;
        }
        v += stacks;
    }

    glGenBuffers(1, &handle);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, handle);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, size, indices, GL_STATIC_DRAW);

    free(indices);
}

void PezInitialize()
{
    LoadProgram("VS", "TCS", "TES", "GS", "FS");

    PezConfig cfg = PezGetConfig();
    const float h = 1.5f;
    const float w = h * cfg.Width / cfg.Height;
    const float z[2] = {65, 90};
    Scene.Projection = M4MakeFrustum(-w, w, -h, h, z[0], z[1]);

    const float MajorRadius = 8.0f, MinorRadius = 2.0f;
    const int Slices = 80, Stacks = 20;
    CreateTorus(MajorRadius, MinorRadius, Slices, Stacks);
    Scene.Theta = 0;

    glEnable(GL_DEPTH_TEST);
    glClearColor(0.2f, 0.2f, 0.2f, 1.0f);
}

void PezUpdate(float seconds)
{
    const float RadiansPerSecond = 0.75f;
    Scene.Theta += seconds * RadiansPerSecond;
    
    // Create the model-view matrix:
    Scene.ModelMatrix = M4MakeRotationZ(Scene.Theta);
    Point3 eye = {0, -50, 50};
    Point3 target = {0, 0, 0};
    Vector3 up = {0, 1, 0};
    Scene.ViewMatrix = M4MakeLookAt(eye, target, up);
    Scene.Modelview = M4Mul(Scene.ViewMatrix, Scene.ModelMatrix);
    Scene.NormalMatrix = M4GetUpper3x3(Scene.Modelview);
    for (int i = 0; i < 9; ++i)
        Scene.PackedNormalMatrix[i] = M3GetElem(Scene.NormalMatrix, i/3, i%3);
}

void PezRender()
{
    float* pModel = (float*) &Scene.ModelMatrix;
    float* pView = (float*) &Scene.ViewMatrix;
    float* pModelview = (float*) &Scene.Modelview;
    float* pProjection = (float*) &Scene.Projection;
    float* pNormalMatrix = &Scene.PackedNormalMatrix[0];
    glUniformMatrix4fv(u("ViewMatrix"), 1, 0, pView);
    glUniformMatrix4fv(u("ModelMatrix"), 1, 0, pModel);
    glUniformMatrix4fv(u("Modelview"), 1, 0, pModelview);
    glUniformMatrix4fv(u("Projection"), 1, 0, pProjection);
    glUniformMatrix3fv(u("NormalMatrix"), 1, 0, pNormalMatrix);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glPatchParameteri(GL_PATCH_VERTICES, 3);
    glDrawElements(GL_PATCHES, Scene.IndexCount, GL_UNSIGNED_SHORT, 0);
}

static GLuint CurrentProgram()
{
    GLuint p;
    glGetIntegerv(GL_CURRENT_PROGRAM, (GLint*) &p);
    return p;
}

static GLuint LoadProgram(const char* vsKey, const char* tcsKey, const char* tesKey, const char* gsKey, const char* fsKey)
{
    GLchar spew[256];
    GLint compileSuccess;
    GLuint programHandle = glCreateProgram();

    const char* vsSource = pezGetShader(vsKey);
    pezCheck(vsSource != 0, "Can't find vshader: %s\n", vsKey);
    GLuint vsHandle = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vsHandle, 1, &vsSource, 0);
    glCompileShader(vsHandle);
    glGetShaderiv(vsHandle, GL_COMPILE_STATUS, &compileSuccess);
    glGetShaderInfoLog(vsHandle, sizeof(spew), 0, spew);
    pezCheck(compileSuccess, "Can't compile vshader:\n%s", spew);
    glAttachShader(programHandle, vsHandle);

    if (tcsKey) {
        const char* tcsSource = pezGetShader(tcsKey);
        pezCheck(tcsSource != 0, "Can't find tcshader: %s\n", tcsKey);
        GLuint tcsHandle = glCreateShader(GL_TESS_CONTROL_SHADER);
        glShaderSource(tcsHandle, 1, &tcsSource, 0);
        glCompileShader(tcsHandle);
        glGetShaderiv(tcsHandle, GL_COMPILE_STATUS, &compileSuccess);
        glGetShaderInfoLog(tcsHandle, sizeof(spew), 0, spew);
        pezCheck(compileSuccess, "Can't compile tcshader:\n%s", spew);
        glAttachShader(programHandle, tcsHandle);
    }

    if (tesKey) {
        const char* tesSource = pezGetShader(tesKey);
        pezCheck(tesSource != 0, "Can't find teshader: %s\n", tesKey);
        GLuint tesHandle = glCreateShader(GL_TESS_EVALUATION_SHADER);
        glShaderSource(tesHandle, 1, &tesSource, 0);
        glCompileShader(tesHandle);
        glGetShaderiv(tesHandle, GL_COMPILE_STATUS, &compileSuccess);
        glGetShaderInfoLog(tesHandle, sizeof(spew), 0, spew);
        pezCheck(compileSuccess, "Can't compile teshader:\n%s", spew);
        glAttachShader(programHandle, tesHandle);
    }

    if (gsKey) {
        const char* gsSource = pezGetShader(gsKey);
        pezCheck(gsSource != 0, "Can't find gshader: %s\n", gsKey);
        GLuint gsHandle = glCreateShader(GL_GEOMETRY_SHADER);
        glShaderSource(gsHandle, 1, &gsSource, 0);
        glCompileShader(gsHandle);
        glGetShaderiv(gsHandle, GL_COMPILE_STATUS, &compileSuccess);
        glGetShaderInfoLog(gsHandle, sizeof(spew), 0, spew);
        pezCheck(compileSuccess, "Can't compile gshader:\n%s", spew);
        glAttachShader(programHandle, gsHandle);
    }

    if (fsKey) {
        const char* fsSource = pezGetShader(fsKey);
        pezCheck(fsSource != 0, "Can't find fshader: %s\n", fsKey);
        GLuint fsHandle = glCreateShader(GL_FRAGMENT_SHADER);
        glShaderSource(fsHandle, 1, &fsSource, 0);
        glCompileShader(fsHandle);
        glGetShaderiv(fsHandle, GL_COMPILE_STATUS, &compileSuccess);
        glGetShaderInfoLog(fsHandle, sizeof(spew), 0, spew);
        pezCheck(compileSuccess, "Can't compile fshader:\n%s", spew);
        glAttachShader(programHandle, fsHandle);
    }

    glLinkProgram(programHandle);
    GLint linkSuccess;
    glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
    glGetProgramInfoLog(programHandle, sizeof(spew), 0, spew);
    pezCheck(linkSuccess, "Can't link shaders:\n%s", spew);
    glUseProgram(programHandle);
    return programHandle;
}

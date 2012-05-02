-- VS

out vec2 vGridCoord;

void main()
{
    int i = gl_VertexID / 4;
    vGridCoord = vec2(i / 16, i % 16);
}

-- TCS

in vec2 vGridCoord[];

layout(vertices = 4) out;

patch out vec2 tcGridCoord;

void main()
{
    tcGridCoord = vGridCoord[gl_InvocationID];
    gl_TessLevelInner[0] = gl_TessLevelInner[1] =
    gl_TessLevelOuter[0] = gl_TessLevelOuter[1] = 
    gl_TessLevelOuter[2] = gl_TessLevelOuter[3] = 32;
}

-- TES

layout(quads, equal_spacing, ccw) in;

uniform sampler2D DispMap;

patch in vec2 tcGridCoord;

layout(std140) uniform Transform {
    mat4 Projection;
    mat4 Modelview;
    float Time;
};

const float Pi = 4*atan(1);
const float Pi2 = Pi*Pi;
const float Deform = abs(0.25 * sin(1.5 * Time));
const float Alpha = 0.8 - 2.0 * Deform;
const float Scale = 1.25 + Deform * 1.0;

subroutine vec3 ComputeNormalFunc(float u, float v, vec3 A);
subroutine uniform ComputeNormalFunc ComputeNormal;

subroutine vec3 EvalParametricFunc(float u, float v);
subroutine uniform EvalParametricFunc EvalParametric;

// u and v in [0,2π] 
subroutine(EvalParametricFunc)
vec3 Spiral(float u, float v)
{
    float x = Alpha*(-v/(2*Pi) + 1)*(cos(u) + 1)*cos(2*v) + 0.1*cos(2*v);
    float y = Alpha*(-v/(2*Pi) + 1)*(cos(u) + 1)*sin(2*v) + 0.1*sin(2*v);
    float z = Alpha*(-v/(2*Pi) + 1)*sin(u) + v/(2*Pi);
    return vec3(x, y, z);
}

// u and v in [0,2π] 
subroutine(EvalParametricFunc)
vec3 KleinBottle(float u, float v)
{
    float x, y, z;
    if (v < Pi) {
        x = 3 * cos(v) * (1 + sin(v)) + (2 * (1 - cos(v) / 2)) * cos(v) * cos(u);
        z = -8 * sin(v) - 2 * (1 - cos(v) / 2) * sin(v) * cos(u);
    } else {
        x = 3 * cos(v) * (1 + sin(v)) + (2 * (1 - cos(v) / 2)) * cos(u + Pi);
        z = -8 * sin(v);
    }
    y = -2 * (1 - cos(v) / 2) * sin(u);
    return 0.125 * vec3(x, y, z);
}

subroutine(ComputeNormalFunc)
vec3 ForwardDifference(float u, float v, vec3 A)
{
    float du = 0.0001; float dv = 0.0001;
    vec3 C = EvalParametric(u + du, v);
    vec3 B = EvalParametric(u, v + dv);
    return normalize(cross(B - A, C - A));
}

subroutine(ComputeNormalFunc)
vec3 AnalyticNormal(float u, float v, vec3 A)
{
    float v2 = v*v;
    float su = sin(u); float s2v = sin(2*v);
    float cu = cos(u); float c2v = cos(2*v);
    float x = -Alpha*(-v/(2*Pi) + 1)*(-Alpha*su/(2*Pi) + 1/(2*Pi))*su*s2v - Alpha*(-v/(2*Pi) + 1)*(2*Alpha*(-v/(2*Pi) + 1)*(cu + 1)*c2v - Alpha*(cu + 1)*s2v/(2*Pi) + 0.2*c2v)*cu;
    float y = Alpha*(-v/(2*Pi) + 1)*(-Alpha*su/(2*Pi) + 1/(2*Pi))*su*c2v + Alpha*(-v/(2*Pi) + 1)*(-2*Alpha*(-v/(2*Pi) + 1)*(cu + 1)*s2v - Alpha*(cu + 1)*c2v/(2*Pi) - 0.2*s2v)*cu;
    float z = Alpha*(-0.5*Alpha*v2*cu - 0.5*Alpha*v2 + 2.0*Pi*Alpha*v*cu + 2.0*Pi*Alpha*v - 2.0*Pi2*Alpha*cu - 2.0*Pi2*Alpha + 0.1*Pi*v - 0.2*Pi2)*su/Pi2;
    return normalize(vec3(x, y, z));
}

out PatchBundle {
    vec3 GridCoord;
    vec3 Normal;
    float Disp;
} Out;

void main()
{
    vec2 uv = (tcGridCoord + gl_TessCoord.xy) / 16.0;
    uv.y = 1 - uv.y;
    vec2 p = uv * 2 * Pi;

    Out.GridCoord = EvalParametric(p.x, p.y);
    Out.Normal = ComputeNormal(p.x, p.y, Out.GridCoord);

    const float DispPresence = 0.05;
    vec2 tc = vec2(1,5) * uv;
    Out.Disp = texture(DispMap, tc).r;
    Out.GridCoord += (1-uv.y) * DispPresence * Out.Disp * Out.Normal;

    gl_Position = Projection * Modelview * vec4(Scale * Out.GridCoord, 1);
}

-- GS

out vec3 gNormal;
out float gDisp;

in PatchBundle {
    vec3 GridCoord;
    vec3 Normal;
    float Disp;
} In[3];

uniform mat3 NormalMatrix;
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

void main()
{
    vec3 A = In[0].GridCoord;
    vec3 B = In[1].GridCoord;
    vec3 C = In[2].GridCoord;
    gNormal = NormalMatrix * normalize(cross(B - A, C - A));

    for (int i = 0; i < 3; i++) {
        gDisp = In[i].Disp;
        gl_Position = gl_in[i].gl_Position;
        EmitVertex();
    }

    EndPrimitive();
}

-- FS

in vec3 gNormal;
in float gDisp;
out vec4 FragColor;

uniform vec3 LightPosition = vec3(0.25, 0.25, 1.0);
uniform vec3 AmbientMaterial = vec3(0.04, 0.04, 0.04);
uniform vec3 SpecularMaterial = vec3(0.5, 0.5, 0.5);
uniform vec3 FrontMaterial = vec3(0.25, 0.5, 0.75);
uniform vec3 BackMaterial = vec3(0.75, 0.75, 0.7);
uniform float Shininess = 50;

void main()
{
    vec3 N = normalize(gNormal);
    if (!gl_FrontFacing)
        N = -N;
        
    vec3 L = normalize(LightPosition);
    vec3 Eye = vec3(0, 0, 1);
    vec3 H = normalize(L + Eye);
    
    float df = max(0.0, dot(N, L));
    float sf = max(0.0, dot(N, H));
    sf = pow(sf, Shininess);

    float t = 0.4 + 0.6 * (1-gDisp);
    vec3 color = mix(FrontMaterial, BackMaterial, t);
    if (!gl_FrontFacing)
        color = 0.5 * color.grb;

    vec3 lighting = AmbientMaterial + df * color;
    lighting += sf * SpecularMaterial;

    FragColor = vec4(lighting,1);
}

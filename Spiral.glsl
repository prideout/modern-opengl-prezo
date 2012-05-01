-- VS

in vec2 Position;
out vec2 vPosition;

uniform mat4 Projection;
uniform mat4 Modelview;
uniform mat4 ViewMatrix;
uniform mat4 ModelMatrix;

void main()
{
    vPosition = Position;
}

-- TCS

uniform float TessLevel = 16;

layout(vertices = 3) out;
in vec2 vPosition[];
out vec2 tcPosition[];

void main()
{
    tcPosition[gl_InvocationID] = vPosition[gl_InvocationID];
    gl_TessLevelInner[0] = gl_TessLevelOuter[0] =
    gl_TessLevelOuter[1] = gl_TessLevelOuter[2] = TessLevel;
}

-- TES

layout(triangles, equal_spacing, ccw) in;
uniform sampler2D DispMap;

in vec2 tcPosition[];
out vec3 tePosition;
out vec3 teNormal;
out float teDisp;
uniform mat4 Projection;
uniform mat4 Modelview;
const float pi = atan(1) * 4;

uniform float Alpha = 0.8;

// u and v in [0,2π] 
// x(u,v) = α (1-v/(2π)) cos(n v) (1 + cos(u)) + γ cos(n v)
// y(u,v) = α (1-v/(2π)) sin(n v) (1 + cos(u)) + γ sin(n v)
// z(u,v) = α (1-v/(2π)) sin(u) + β v/(2π)
vec3 ParametricHorn(float u, float v)
{
    float x = Alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*cos(2*v) + 0.1*cos(2*v);
    float y = Alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*sin(2*v) + 0.1*sin(2*v);
    float z = Alpha*(-v/(2*pi) + 1)*sin(u) + v/(2*pi);
    return vec3(x, y, z);
}

subroutine vec3 ComputeNormal(float u, float v, vec3 A);

vec3 ForwardDifference(float u, float v, vec3 A)
{
    float du = 0.0001; float dv = 0.0001;
    vec3 C = ParametricHorn(u + du, v);
    vec3 B = ParametricHorn(u, v + dv);
    return normalize(cross(B - A, C - A));
}

vec3 AnalyticNormal(float u, float v, vec3 A)
{
    float v2 = v*v;
    float pi2 = pi*pi;
    float x = -Alpha*(-v/(2*pi) + 1)*(-Alpha*sin(u)/(2*pi) + 1/(2*pi))*sin(u)*sin(2*v) - Alpha*(-v/(2*pi) + 1)*(2*Alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*cos(2*v) - Alpha*(cos(u) + 1)*sin(2*v)/(2*pi) + 0.2*cos(2*v))*cos(u);
    float y = Alpha*(-v/(2*pi) + 1)*(-Alpha*sin(u)/(2*pi) + 1/(2*pi))*sin(u)*cos(2*v) + Alpha*(-v/(2*pi) + 1)*(-2*Alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*sin(2*v) - Alpha*(cos(u) + 1)*cos(2*v)/(2*pi) - 0.2*sin(2*v))*cos(u);
    float z = Alpha*(-0.5*Alpha*v2*cos(u) - 0.5*Alpha*v2 + 2.0*pi*Alpha*v*cos(u) + 2.0*pi*Alpha*v - 2.0*pi2*Alpha*cos(u) - 2.0*pi2*Alpha + 0.1*pi*v - 0.2*pi2)*sin(u)/pi2;
    return normalize(vec3(x, y, z));
}

vec3 HornNormal(float u, float v, vec3 A)
{
    //return ForwardDifference(u, v, A);
    return AnalyticNormal(u, v, A);
}

const float Scale = 1.25;

void main()
{
    vec2 p0 = gl_TessCoord.x * tcPosition[0];
    vec2 p1 = gl_TessCoord.y * tcPosition[1];
    vec2 p2 = gl_TessCoord.z * tcPosition[2];
    vec2 p = (p0 + p1 + p2);

    tePosition = ParametricHorn(p.x, p.y);
    teNormal = HornNormal(p.x, p.y, tePosition);

    const float DispPresence = 0.05;
    vec2 uv = vec2(p.x/(2*pi), p.y/(2*pi));
    vec2 tc = vec2(1,5) * uv;
    teDisp = texture(DispMap, tc).r;
    tePosition += (1-uv.y) * DispPresence * teDisp * teNormal;

    gl_Position = Projection * Modelview * vec4(Scale * tePosition, 1);
}

-- GS

out vec3 gNormal;
out float gDisp;

in vec3 tePosition[3];
in vec3 teNormal[3];
in float teDisp[3];

uniform mat3 NormalMatrix;
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

void main()
{
    vec3 A = tePosition[0];
    vec3 B = tePosition[1];
    vec3 C = tePosition[2];
    gNormal = NormalMatrix * normalize(cross(B - A, C - A));

    for (int i = 0; i < 3; i++) {
        gDisp = teDisp[i];
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

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

uniform float TessLevel = 2;

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

in vec2 tcPosition[];
out vec3 tePosition;
out vec2 teDistance;
uniform mat4 Projection;
uniform mat4 Modelview;
const float pi = atan(1) * 4;

#if PYTHON
from sympy import *
from sympy.matrices import *
from sympy.functions import sin,cos
u, v, alpha = symbols('u v alpha')
f, twopi = Matrix([None]*3), 2*pi
twopi = 2*pi
f[0] = alpha * (1-v/twopi) * cos(2*v) * (1+cos(u)) + 0.1 * cos(2*v)
f[1] = alpha * (1-v/twopi) * sin(2*v) * (1+cos(u)) + 0.1 * sin(2*v)
f[2] = alpha * (1-v/twopi) * sin(u) + v / twopi
print f
#endif

// u and v in [0,2π] 
// x(u,v) = α (1-v/(2π)) cos(n v) (1 + cos(u)) + γ cos(n v)
// y(u,v) = α (1-v/(2π)) sin(n v) (1 + cos(u)) + γ sin(n v)
// z(u,v) = α (1-v/(2π)) sin(u) + β v/(2π)
vec3 ParametricHorn(float u, float v, float alpha)
{
    float x = alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*cos(2*v) + 0.1*cos(2*v);
    float y = alpha*(-v/(2*pi) + 1)*(cos(u) + 1)*sin(2*v) + 0.1*sin(2*v);
    float z = alpha*(-v/(2*pi) + 1)*sin(u) + v/(2*pi);
    return vec3(x, y, z);
}

void main()
{
    float alpha = 0.8;   // 0.15 for horn, 1.0 for snail

    vec2 p0 = gl_TessCoord.x * tcPosition[0];
    vec2 p1 = gl_TessCoord.y * tcPosition[1];
    vec2 p2 = gl_TessCoord.z * tcPosition[2];
    vec2 p = (p0 + p1 + p2);

    tePosition = ParametricHorn(p.x, p.y, alpha);

    teDistance = gl_TessCoord.xz;
    gl_Position = Projection * Modelview * vec4(tePosition, 1);
}

-- GS

out vec2 gDistance;
out vec3 gNormal;
in vec3 tePosition[3];
in vec2 teDistance[3];

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
        gDistance = teDistance[i];
        gl_Position = gl_in[i].gl_Position;
        EmitVertex();
    }

    EndPrimitive();
}

-- FS

in vec2 gDistance;
in vec3 gNormal;
out vec4 FragColor;

const float Scale = 20.0;
const float Offset = -1.0;

uniform vec3 LightPosition = vec3(0.25, 0.25, 1.0);
uniform vec3 AmbientMaterial = vec3(0.04, 0.04, 0.04);
uniform vec3 SpecularMaterial = vec3(0.5, 0.5, 0.5);
uniform vec3 FrontMaterial = vec3(0.25, 0.5, 0.75);
uniform vec3 BackMaterial = vec3(0.75, 0.75, 0.7);
uniform float Shininess = 50;

vec4 amplify(float d, vec3 color)
{
    float T = 0.025; // <-- thickness
    float E = fwidth(d);
    if (d < T) {
        d = 0;
    } else if (d < T + E) {
        d = (d - T) / E;
    } else {
        d = 1;
    }
    return vec4(d*color, 1);
}

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

    vec3 color = gl_FrontFacing ? FrontMaterial : BackMaterial;
    vec3 lighting = AmbientMaterial + df * color;
    if (gl_FrontFacing)
        lighting += sf * SpecularMaterial;

    float d = min(gDistance.x, gDistance.y);
    FragColor = amplify(d, lighting);

    //FragColor = vec4(0,0,0,0.5);
    //FragColor.a = 0.5;
}

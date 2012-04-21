-- VS

in vec4 Position;
out vec3 vPosition;

uniform mat4 Projection;
uniform mat4 Modelview;
uniform mat4 ViewMatrix;
uniform mat4 ModelMatrix;

void main()
{
    vPosition = Position.xyz;
}

-- TCS

uniform float TessLevel = 2;

layout(vertices = 4) out;
in vec3 vPosition[];
out vec3 tcPosition[];

void main()
{
    tcPosition[gl_InvocationID] = vPosition[gl_InvocationID];
    gl_TessLevelInner[0] = gl_TessLevelInner[0] = TessLevel;
    gl_TessLevelOuter[0] = gl_TessLevelOuter[1] = TessLevel;
    gl_TessLevelOuter[2] = gl_TessLevelOuter[3] = TessLevel;
}

-- TES

layout(quads, equal_spacing, ccw) in;

in vec3 tcPosition[];
out vec3 tePosition;
out vec2 teDistance;
uniform mat4 Projection;
uniform mat4 Modelview;

void main()
{
    float u = gl_TessCoord.x, v = gl_TessCoord.y;
    vec3 a = mix(tcPosition[0], tcPosition[1], u);
    vec3 b = mix(tcPosition[2], tcPosition[3], u);
    tePosition = mix(a, b, v);
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

    float d = 1;//min(gDistance.x, gDistance.y);
    FragColor = amplify(d, lighting);
}

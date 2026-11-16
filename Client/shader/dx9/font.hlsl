// font.hlsl — 3D-текст и клип. Профиль: vs_3_0.
//
// Из вершины читается только BLENDWEIGHT: 0, 2, 4, 6.
// c0..c3 World, c4..c7 ViewProj, c8 цвет.
// С c9 пары Pos, UV. Data[12] покрывает запись Draw3DText до c20.

float4x4 World    : register(c0);
float4x4 ViewProj : register(c4);
float4   Color    : register(c8);
float4   Data[12] : register(c9);

struct VS_IN {
    float index : BLENDWEIGHT;
};

struct VS_OUT {
    float4 pos     : POSITION;
    float4 diffuse : COLOR0;
    float2 uv      : TEXCOORD0;
};

VS_OUT main(VS_IN i) {
    VS_OUT o;
    int idx = (int)i.index;
    float4 localPos = Data[idx];
    o.pos     = mul(mul(localPos, World), ViewProj);
    o.diffuse = Color;
    o.uv      = Data[idx + 1].xy;
    return o;
}

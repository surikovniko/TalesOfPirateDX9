// minimap.hlsl — иконки миникарты. Профиль: vs_3_0.
//
// Индекс 0..3 в BLENDWEIGHT. Позиция из Positions[4] на c9..c12.
// UV из TEXCOORD0.
// c0..c3 World, c4..c7 ViewProj, c8 цвет.

float4x4 World        : register(c0);
float4x4 ViewProj     : register(c4);
float4   Color        : register(c8);
float4   Positions[4] : register(c9);

struct VS_IN {
    float  posIndex : BLENDWEIGHT;
    float2 uv       : TEXCOORD0;
};

struct VS_OUT {
    float4 pos     : POSITION;
    float4 diffuse : COLOR0;
    float2 uv      : TEXCOORD0;
};

VS_OUT main(VS_IN i) {
    VS_OUT o;
    float4 localPos = Positions[(int)i.posIndex];
    float4 worldPos = mul(localPos, World);
    o.pos     = mul(worldPos, ViewProj);
    o.diffuse = Color;
    o.uv      = i.uv;
    return o;
}

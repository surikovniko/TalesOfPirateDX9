// shadeeff.hlsl — тень на земле. Профиль: vs_3_0.
//
// Позиция и UV не в вершине. TEXCOORD1 хранит абсолютные номера регистров:
//   .x — UV  (9, 11, 13, ...)
//   .y — Pos (10, 12, 14, ...)
// Массив Data с c9, индекс = регистр - 9. 240 слотов не увеличивать.
// World (c0) в ASM закомментирован: позиция сразу умножается на ViewProj.

float4x4 ViewProj : register(c4);
float4   Color    : register(c8);
float4   Data[240] : register(c9);

struct VS_IN {
    float2 indices : TEXCOORD1;
};

struct VS_OUT {
    float4 pos     : POSITION;
    float4 diffuse : COLOR0;
    float2 uv      : TEXCOORD0;
};

VS_OUT main(VS_IN i) {
    VS_OUT o;
    int posIdx = (int)i.indices.y - 9;
    int uvIdx  = (int)i.indices.x - 9;
    float4 pos = Data[posIdx];
    o.pos      = mul(pos, ViewProj);
    o.diffuse  = Color;
    o.uv       = Data[uvIdx].xy;
    return o;
}

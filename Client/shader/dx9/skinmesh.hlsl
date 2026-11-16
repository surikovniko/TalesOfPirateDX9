// skinmesh.hlsl — мастер-исходник animated skinning VS.
// Профиль: vs_3_0.
//
// NUM_SKIN_WEIGHTS = 1 | 2. Слоты на 3 и 4 веса загрузчик не заполняет.
//   1 вес: одна кость, boneIndices.x * c0.w. Веса во входе нет.
//   2 веса: w1 = weight.x, w2 = c0.x - weight.x - weight.y.
//           Индексы .x и .y (в ASM v2.xyyw), не свизл zyxw статического скина.
// TT_MODE = 1 | 2 | 3:
//   1 → oT0 = uv, oT1 = Texture * uvh,  матрица c12..c15
//   2 → oT0 = uv, oT1 = uv, oT2 = Texture2 * uvh, матрица c16..c19
//   3 → как 2, плюс oT3 = uv
// uvh = (u, v, 1, v)
//
// Constant registers:
//   c0      — Base (.x = 1, .z = specular, .w = 765.01 = 3 * 255 + epsilon)
//   c1..c4  — World * ViewProj, CPU пишет транспонированной
//   c5      — LightDirection
//   c6      — Ambient
//   c7      — Diffuse
//   c12..c15 — Texture   (TT_MODE = 1)
//   c16..c19 — Texture2  (TT_MODE = 2 или 3)
//   c21     — BV[234], 78 костей × 3 строки (c21..c254). Дальше один draw не адресует.

#ifndef NUM_SKIN_WEIGHTS
#define NUM_SKIN_WEIGHTS 1
#endif

#ifndef TT_MODE
#define TT_MODE 1
#endif

float4 Base : register(c0);
float4x4 World : register(c1);
float3 LightDirection : register(c5);
float4 Ambient : register(c6);
float4 Diffuse : register(c7);

#if TT_MODE == 1
float4 Tex_Row0 : register(c12);
float4 Tex_Row1 : register(c13);
float4 Tex_Row2 : register(c14);
float4 Tex_Row3 : register(c15);
#else
float4 Tex_Row0 : register(c16);
float4 Tex_Row1 : register(c17);
float4 Tex_Row2 : register(c18);
float4 Tex_Row3 : register(c19);
#endif

float4 BV[234] : register(c21); // LW_VS30_BONE_PALETTE * 3

struct VS_IN {
    float4 pos : POSITION;
#if NUM_SKIN_WEIGHTS == 2
    float2 weight : BLENDWEIGHT;
#endif
    float4 boneIndices : BLENDINDICES;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct VS_OUT {
    float4 pos : POSITION;
    float4 diffuse : COLOR0;
    float4 specular : COLOR1;
    float2 t0 : TEXCOORD0;
#if TT_MODE == 1
    float4 t1 : TEXCOORD1;
#else
    float2 t1 : TEXCOORD1;
    float4 t2 : TEXCOORD2;
#endif
#if TT_MODE == 3
    float2 t3 : TEXCOORD3;
#endif
};

float3 SkinPos(float4 pos, int idx) {
    return float3(dot(pos, BV[idx + 0]),
                  dot(pos, BV[idx + 1]),
                  dot(pos, BV[idx + 2]));
}

float3 SkinNormal(float3 n, int idx) {
    return float3(dot(n, BV[idx + 0].xyz),
                  dot(n, BV[idx + 1].xyz),
                  dot(n, BV[idx + 2].xyz));
}

VS_OUT main(VS_IN i) {
    VS_OUT o;

    int idx1 = (int)(i.boneIndices.x * Base.w);

#if NUM_SKIN_WEIGHTS == 1
    float3 skinned = SkinPos(i.pos, idx1);
    float3 skinnedN = SkinNormal(i.normal, idx1);
#else
    int idx2 = (int)(i.boneIndices.y * Base.w);
    float w1 = i.weight.x;
    float w2 = Base.x - i.weight.x - i.weight.y;
    float3 skinned = w1 * SkinPos(i.pos, idx1) + w2 * SkinPos(i.pos, idx2);
    float3 skinnedN = w1 * SkinNormal(i.normal, idx1) + w2 * SkinNormal(i.normal, idx2);
#endif

    // mul(v, World) matches the transposed rows the CPU writes to c1..c4.
    float4 skinnedH = float4(skinned, 1.0);
    o.pos = mul(skinnedH, World);

    float3 nrm = normalize(skinnedN);
    float NdotL = dot(nrm, LightDirection);
    float4 L = lit(NdotL, 0, 0);
    o.diffuse = min(L.y * Diffuse + Ambient, Base.x);
    o.specular = Base.z;

    o.t0 = i.uv;
    float4 uvh = float4(i.uv.x, i.uv.y, Base.x, i.uv.y);
#if TT_MODE == 1
    o.t1.x = dot(uvh, Tex_Row0);
    o.t1.y = dot(uvh, Tex_Row1);
    o.t1.z = dot(uvh, Tex_Row2);
    o.t1.w = dot(uvh, Tex_Row3);
#else
    o.t1 = i.uv;
    o.t2.x = dot(uvh, Tex_Row0);
    o.t2.y = dot(uvh, Tex_Row1);
    o.t2.z = dot(uvh, Tex_Row2);
    o.t2.w = dot(uvh, Tex_Row3);
#endif
#if TT_MODE == 3
    o.t3 = i.uv;
#endif

    return o;
}

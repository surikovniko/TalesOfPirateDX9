// static_skin.hlsl — мастер-исходник static-mesh skinning VS.
// Профиль: vs_3_0.
//
// Семейство pu4/pbN_u4nt0_ld (без texture transform, UV passthrough):
//   NUM_EXPLICIT_WEIGHTS = 0 → single-bone (pu4nt0_ld)
//   NUM_EXPLICIT_WEIGHTS = 1 → 2-bone blend (pb1u4nt0_ld)
//   NUM_EXPLICIT_WEIGHTS = 2 → 3-bone blend (pb2u4nt0_ld)
//   NUM_EXPLICIT_WEIGHTS = 3 → 4-bone blend (pb3u4nt0_ld)
//
// Для blend: последний weight (остаточный) = c0.x - sum(explicit).
//
// Constant registers (runtime SetVertexShaderConstantF):
//   c0      — Base (.x = 1.0, .z = specular, .w = 765.01 = 3 * 255 + epsilon)
//   c1..c4  — World * ViewProj (combined, transposed by the CPU)
//   c5      — LightDirection
//   c6      — Ambient
//   c7      — Diffuse
//   c21..   — BV[234] matrix palette (78 bones * 3 rows, c21..c254)
//
// BLENDINDICES — D3DCOLOR, в шейдер приходит как float 0..1.
// ASM читает v2.zyxw: первая кость — .z, затем .y, .x, .w.
// idx = (int)(component * c0.w). Не подставлять литерал 3.

#ifndef NUM_EXPLICIT_WEIGHTS
#define NUM_EXPLICIT_WEIGHTS 0
#endif

float4 Base : register(c0);
float4x4 World : register(c1);
float3 LightDirection : register(c5);
float4 Ambient : register(c6);
float4 Diffuse : register(c7);
float4 BV[234] : register(c21); // LW_VS30_BONE_PALETTE * 3

struct VS_IN {
    float4 pos : POSITION;
#if NUM_EXPLICIT_WEIGHTS >= 1
    float4 weight : BLENDWEIGHT;
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

    int idx0 = (int)(i.boneIndices.z * Base.w);
#if NUM_EXPLICIT_WEIGHTS >= 1
    int idx1 = (int)(i.boneIndices.y * Base.w);
#endif
#if NUM_EXPLICIT_WEIGHTS >= 2
    int idx2 = (int)(i.boneIndices.x * Base.w);
#endif
#if NUM_EXPLICIT_WEIGHTS >= 3
    int idx3 = (int)(i.boneIndices.w * Base.w);
#endif

#if NUM_EXPLICIT_WEIGHTS == 0
    float3 p = SkinPos(i.pos, idx0);
    float3 n = SkinNormal(i.normal, idx0);
#elif NUM_EXPLICIT_WEIGHTS == 1
    float w0 = i.weight.x;
    float w1 = Base.x - w0;
    float3 p = w0 * SkinPos(i.pos, idx0) + w1 * SkinPos(i.pos, idx1);
    float3 n = w0 * SkinNormal(i.normal, idx0) + w1 * SkinNormal(i.normal, idx1);
#elif NUM_EXPLICIT_WEIGHTS == 2
    float w0 = i.weight.x, w1 = i.weight.y;
    float w2 = Base.x - (w0 + w1);
    float3 p = w0 * SkinPos(i.pos, idx0) + w1 * SkinPos(i.pos, idx1) + w2 * SkinPos(i.pos, idx2);
    float3 n = w0 * SkinNormal(i.normal, idx0) + w1 * SkinNormal(i.normal, idx1) + w2 * SkinNormal(i.normal, idx2);
#elif NUM_EXPLICIT_WEIGHTS == 3
    float w0 = i.weight.x, w1 = i.weight.y, w2 = i.weight.z;
    float w3 = Base.x - (w0 + w1 + w2);
    float3 p = w0 * SkinPos(i.pos, idx0) + w1 * SkinPos(i.pos, idx1) + w2 * SkinPos(i.pos, idx2) + w3 * SkinPos(i.pos, idx3);
    float3 n = w0 * SkinNormal(i.normal, idx0) + w1 * SkinNormal(i.normal, idx1) + w2 * SkinNormal(i.normal, idx2) + w3 * SkinNormal(i.normal, idx3);
#endif

    // Column-major HLSL: mul(v, World) matches dp4 against rows c1..c4.
    float4 pH = float4(p, 1.0);
    o.pos = mul(pH, World);

    float3 nrm = normalize(n);
    float NdotL = dot(nrm, LightDirection);
    float4 L = lit(NdotL, 0, 0);
    o.diffuse = min(L.y * Diffuse + Ambient, Base.x);
    o.specular = Base.z;
    o.t0 = i.uv;

    return o;
}

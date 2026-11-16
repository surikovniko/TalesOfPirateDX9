// vs_pndt0.hlsl — мастер-исходник семейства static-mesh VS.
// Профиль: vs_3_0.
//
// define            | effect
// ------------------|------------------------------------------------
// NO_LIGHTING       | нет normal и нет Lambertian; diffuse из COLOR0
// NO_DIFFUSE        | во входе нет COLOR0
// USE_TEX_TRANSFORM | UV через float4x3 на c7..c8
//
// 7 permutations:
//   VST_PNDT0        NO_LIGHTING
//   VST_PNDT0_LD     (none)
//   VST_PNDT0_TT0    NO_LIGHTING + USE_TEX_TRANSFORM
//   VST_PNDT0_LD_TT0 USE_TEX_TRANSFORM
//   VST_PNT0_LD      NO_DIFFUSE
//   VST_PNT0_TT0     NO_LIGHTING + USE_TEX_TRANSFORM + NO_DIFFUSE
//   VST_PNT0_LD_TT0  USE_TEX_TRANSFORM + NO_DIFFUSE
//
// Constant registers:
//   c0..c3 — World * ViewProj
//   c4     — LightDir            [only if !NO_LIGHTING]
//   c5     — Ambient             [only if !NO_LIGHTING]
//   c7..c8 — UVMatrix0, float4x3 [only if USE_TEX_TRANSFORM]
// CPU для UV-анимации пишет 4 регистра с c8. Шейдер читает c7 и c8,
// как текущий листинг vs_2_x. Сдвиг не выравнивать.

float4x4 World : register(c0);

#ifndef NO_LIGHTING
float3 LightDir : register(c4);
float4 Ambient : register(c5);
#endif

#ifdef USE_TEX_TRANSFORM
float4 UVMatrix0_Row0 : register(c7);
float4 UVMatrix0_Row1 : register(c8);
#endif

struct VS_IN {
    float4 pos : POSITION;
#ifndef NO_LIGHTING
    float3 normal : NORMAL;
#endif
#ifndef NO_DIFFUSE
    float4 color : COLOR0;
#endif
    float2 uv : TEXCOORD0;
};

struct VS_OUT {
    float4 pos : POSITION;
    float4 diffuse : COLOR0;
    float4 specular : COLOR1;
    float2 uv : TEXCOORD0;
};

VS_OUT main(VS_IN i) {
    VS_OUT o;
    o.pos = mul(i.pos, World);

#ifdef NO_LIGHTING
#ifndef NO_DIFFUSE
    o.diffuse = i.color;
#else
    // vs_pnt0_t0uvmat.vsh: def c4, 1, 0, 0, 0 / mov oD0, c4.x
    // c4 — литерал шейдера, не свет. .x реплицируется во все компоненты.
    o.diffuse = float4(1, 1, 1, 1);
#endif
#else
    float NdotL = dot(i.normal, LightDir);
    float4 lit_out = lit(NdotL, 0, 0);
#ifndef NO_DIFFUSE
    float4 light = lit_out.y * i.color + Ambient;
#else
    float4 light = lit_out.y + Ambient;
#endif
    o.diffuse = saturate(light);
#endif

    o.specular = 0;

#ifdef USE_TEX_TRANSFORM
    float3 uv3 = float3(i.uv.xy, 1);
    o.uv.x = dot(uv3, UVMatrix0_Row0.xyz);
    o.uv.y = dot(uv3, UVMatrix0_Row1.xyz);
#else
    o.uv = i.uv;
#endif

    return o;
}

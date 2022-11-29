
/*
	Description: Renders objects with leaf-like characteristics
*/

#include "shaders/RealityGraphics.fxh"
#include "shaders/RaCommon.fxh"

// [Debug data]
// #define OVERGROWTH
// #define _POINTLIGHT_
// #define _HASSHADOW_ 1
// #define HASALPHA2MASK 1
// [Debug data]

// Speed to always add to wind, decrease for less movement
#define WIND_ADD 5

#define LEAF_MOVEMENT 1024

#if !defined(_HASSHADOW_)
	#define _HASSHADOW_ 0
#endif

// float3 TreeSkyColor;
uniform float4 OverGrowthAmbient;
uniform float4 PosUnpack;
uniform float2 NormalUnpack;
uniform float TexUnpack;
uniform float4 ObjectSpaceCamPos;
uniform float ObjRadius = 2;
Light Lights[1];

uniform texture DiffuseMap;
sampler SampleDiffuseMap = sampler_state
{
	Texture = (DiffuseMap);
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
	SRGBTexture = FALSE;
};

string GlobalParameters[] =
{
	#if _HASSHADOW_
		"ShadowMap",
	#endif
	"GlobalTime",
	"FogRange",
	#if !defined(_POINTLIGHT_)
		"FogColor"
	#endif
};

string InstanceParameters[] =
{
	#if _HASSHADOW_
		"ShadowProjMat",
		"ShadowTrapMat",
	#endif
	"WorldViewProjection",
	"Transparency",
	"WindSpeed",
	"Lights",
	"ObjectSpaceCamPos",
	#if !defined(_POINTLIGHT_)
		"OverGrowthAmbient"
	#endif
};

string TemplateParameters[] =
{
	"DiffuseMap",
	"PosUnpack",
	"NormalUnpack",
	"TexUnpack"
};

// INPUTS TO THE VERTEX SHADER FROM THE APP
string reqVertexElement[] =
{
	#if defined(OVERGROWTH) // tl: TODO - Compress overgrowth patches as well.
		"Position",
		"Normal",
		"TBase2D"
	#else
		"PositionPacked",
		"NormalPacked8",
		"TBasePacked2D"
	#endif
};

struct APP2VS
{
	float4 Pos : POSITION0;
	float3 Normal : NORMAL;
	float2 Tex0 : TEXCOORD0;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float4 Tex0 : TEXCOORD1;
	#if _HASSHADOW_
		float4 TexShadow : TEXCOORD2;
	#endif
};

struct PS2FB
{
	float4 Color : COLOR;
	float Depth : DEPTH;
};

VS2PS Leaf_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	#if !defined(OVERGROWTH)
		Input.Pos *= PosUnpack;
		float Wind = WindSpeed + WIND_ADD;
		float ObjRadii = ObjRadius + Input.Pos.y;
		Input.Pos.xyz += sin((GlobalTime / ObjRadii) * Wind) * ObjRadii * ObjRadii / LEAF_MOVEMENT;
	#endif

	Output.HPos = mul(float4(Input.Pos.xyz, 1.0), WorldViewProjection);

	#if defined(OVERGROWTH)
		float3 LocalPos = Input.Pos.xyz * PosUnpack.xyz;
	#else
		float3 LocalPos = Input.Pos.xyz;
	#endif

	Output.Pos.xyz = LocalPos.xyz;
	Output.Pos.w = Output.HPos.w; // Output depth

	Output.Tex0.xy = Input.Tex0;
	#if defined(OVERGROWTH)
		Input.Normal = normalize((Input.Normal * 2.0) - 1.0);
		Output.Tex0.xy /= 32767.0;
	#else
		Input.Normal = normalize(Input.Normal * NormalUnpack.x + NormalUnpack.y);
		Output.Tex0.xy *= TexUnpack;
	#endif

	#if defined(_POINTLIGHT_)
		float3 LightVec = normalize(Lights[0].pos.xyz - Input.Pos.xyz);
		Output.Tex0.z = saturate(dot(Input.Normal.xyz, LightVec));
	#else
		float3 LightVec = normalize(-Lights[0].dir.xyz);
		Output.Tex0.z = saturate((dot(Input.Normal.xyz, LightVec) * 0.5) + 0.5);
	#endif

	Output.Tex0.w = Input.Pos.w / 32767.0;

	#if _HASSHADOW_
		Output.TexShadow = GetShadowProjection(float4(Input.Pos.xyz, 1.0));
	#endif

	return Output;
}

PS2FB Leaf_PS(VS2PS Input)
{
	PS2FB Output;

	float DotLN = Input.Tex0.z;
	float LodScale = Input.Tex0.w;
	float3 ObjectPos = Input.Pos.xyz;
	float3 LightVec = Lights[0].pos.xyz - ObjectPos;
	float4 DiffuseMap = tex2D(SampleDiffuseMap, Input.Tex0.xy);

	#if defined(OVERGROWTH)
		float3 Diffuse = (DotLN * LodScale) * (Lights[0].color * LodScale);
		OverGrowthAmbient *= LodScale;
	#else
		float3 Diffuse = DotLN * Lights[0].color;
	#endif

	#if _HASSHADOW_
		float4 Shadow = GetShadowFactor(SampleShadowMap, Input.TexShadow);
		Diffuse.rgb *= Shadow.rgb;
	#endif

	float3 VertexColor = OverGrowthAmbient.rgb + Diffuse;
	float4 OutputColor = DiffuseMap * float4(VertexColor, Transparency.a * 2.0);

	#if defined(OVERGROWTH) && HASALPHA2MASK
		OutputColor.a *= 2.0 * DiffuseMap.a;
	#endif

	#if defined(_POINTLIGHT_)
		OutputColor.rgb *= GetLightAttenuation(LightVec, Lights[0].attenuation);
		OutputColor.rgb *= GetFogValue(ObjectPos, ObjectSpaceCamPos);
	#else
		ApplyFog(OutputColor.rgb, GetFogValue(ObjectPos, ObjectSpaceCamPos));
	#endif

	Output.Color = OutputColor;
	Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);

	return Output;
};

technique defaultTechnique
{
	pass Pass0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		AlphaTestEnable = TRUE;
		AlphaRef = 127;

		SrcBlend = (srcBlend);
		DestBlend = (destBlend);

		#if defined(_POINTLIGHT_)
			AlphaBlendEnable = TRUE;
			SrcBlend = ONE;
			DestBlend = ONE;
		#else
			AlphaBlendEnable = FALSE;
		#endif

		CullMode = NONE;

		SRGBWriteEnable = FALSE;

		VertexShader = compile vs_3_0 Leaf_VS();
		PixelShader = compile ps_3_0 Leaf_PS();
	}
}

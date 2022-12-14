
/*
	Description: Renders lighting for tree-trunk overgrowth
*/

#include "shaders/RealityGraphics.fxh"
#include "shaders/RaCommon.fxh"

uniform float4 OverGrowthAmbient;
uniform float4 ObjectSpaceCamPos;
uniform float4 PosUnpack;
Light Lights[1];

string GlobalParameters[] =
{
	"GlobalTime",
	"FogRange",
	"FogColor",
};

string TemplateParameters[] =
{
	"PosUnpack",
	"DiffuseMap",
};

string InstanceParameters[] =
{
	"WorldViewProjection",
	"Lights",
	"ObjectSpaceCamPos",
	"OverGrowthAmbient",
	"Transparency",
};

// INPUTS TO THE VERTEX SHADER FROM THE APP
string reqVertexElement[] =
{
	"Position",
	"Normal",
	"TBase2D"
};

uniform texture DiffuseMap;
sampler SampleDiffuseMap = sampler_state
{
	Texture = (DiffuseMap);
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
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
	float3 Tex0 : TEXCOORD1; // .xy = Tex0; .z = LodScale;
	float3 Normal : TEXCOORD2;
};

struct PS2FB
{
	float4 Color : COLOR;
};

VS2PS TrunkOG_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	Output.HPos = mul(float4(Input.Pos.xyz, 1.0), WorldViewProjection);
	Output.Pos = Input.Pos * PosUnpack;

	Output.Tex0.xy = Input.Tex0 / 32767.0;
	Output.Tex0.z = Input.Pos.w / 32767.0;
	Output.Normal = normalize((Input.Normal * 2.0) - 1.0);

	#if defined(LOG_DEPTH)
		// Output depth (VS)
		Output.HPos.z = ApplyLogarithmicDepth(Output.HPos.w + 1.0) * Output.HPos.w;
	#endif

	return Output;
}

// There will be small differences between this lighting and the one produced by the static mesh shader,
// not enough to worry about, ambient is added here and lerped in the static mesh, etc
// NOTE: could be an issue at some point.
PS2FB TrunkOG_PS(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	float3 ObjectPos = Input.Pos.xyz;
	float LodScale = Input.Tex0.z;
	float3 Normals = normalize(Input.Normal.xyz);

	float4 DiffuseMap = tex2D(SampleDiffuseMap, Input.Tex0.xy) * 2.0;
	float DotLN = LambertLighting(Normals, -Lights[0].dir);

	float3 Color = (DotLN * LodScale) * (Lights[0].color * LodScale);
	Color += (OverGrowthAmbient.rgb * LodScale);

	float4 OutputColor = 0.0;
	OutputColor.rgb = DiffuseMap.rgb * Color.rgb;
	OutputColor.a = Transparency.a;

	Output.Color = OutputColor;

	ApplyFog(Output.Color.rgb, GetFogValue(ObjectPos, ObjectSpaceCamPos));

	return Output;
};

technique defaultTechnique
{
	pass Pass0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		VertexShader = compile vs_3_0 TrunkOG_VS();
		PixelShader = compile ps_3_0 TrunkOG_PS();
	}
}

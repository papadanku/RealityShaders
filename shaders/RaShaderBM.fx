
/*
	Description:
	- Renders lighting for bundledmesh (objects that are dynamic, nonhuman)
	- Calculates world-space lighting
*/

#include "shaders/RealityGraphics.fxh"
#include "shaders/RaCommon.fxh"
#include "shaders/RaDefines.fx"
#include "shaders/RaShaderBMCommon.fxh"

// Dependencies and sanity checks

// Tmp
#if !defined(_HASUVANIMATION_)
	#define _HASUVANIMATION_ 0
#endif

#if !defined(_HASNORMALMAP_)
	#define _HASNORMALMAP_ 0
#endif

#if !defined(_HASGIMAP_)
	#define _HASGIMAP_ 0
#endif

#if !defined(_HASENVMAP_)
	#define _HASENVMAP_ 0
#endif

#if !defined(_USEHEMIMAP_)
	#define _USEHEMIMAP_ 0
#endif

#if !defined(_HASSHADOW_)
	#define _HASSHADOW_ 0
#endif

#if !defined(_HASCOLORMAPGLOSS_)
	#define _HASCOLORMAPGLOSS_ 0
#endif

#if !defined(_HASDOT3ALPHATEST_)
	#define _HASDOT3ALPHATEST_ 0
#endif

// resolve illegal combo GI + ENVMAP
#if _HASGIMAP_ && _HASENVMAP_
	#define _HASENVMAP_ 0
#endif

#if _POINTLIGHT_
	// Disable these code portions for point lights
	#define _HASGIMAP_ 0
	#define _HASENVMAP_ 0
	#define _USEHEMIMAP_ 0
	#define _HASSHADOW_ 0
#endif

/*
	// #define _DEBUG_
	#if defined(_DEBUG_)
		#define _HASUVANIMATION_ 1
		#define _USEHEMIMAP_ 1
		#define _HASSHADOW_ 1
		#define _HASSHADOWOCCLUSION_ 1
		#define _HASNORMALMAP_ 1
		#define _HASGIMAP_ 1
	#endif
*/

struct APP2VS
{
	float4 Pos : POSITION;
	float3 Normal : NORMAL;
	float4 BlendIndices : BLENDINDICES;
	float2 TexDiffuse : TEXCOORD0;
	float2 TexUVRotCenter : TEXCOORD1;
	float3 Tan : TANGENT;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;

	float3 WorldTangent : TEXCOORD1;
	float3 WorldBinormal : TEXCOORD2;
	float3 WorldNormal : TEXCOORD3;

	float2 Tex0 : TEXCOORD4;
	float4 ShadowTex : TEXCOORD5;
	float4 OccShadowTex : TEXCOORD6;
};

struct PS2FB
{
	float4 Color : COLOR;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

float4x3 GetSkinnedWorldMatrix(APP2VS Input)
{
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;
	return GeomBones[IndexArray[0]];
}

float3x3 GetSkinnedUVMatrix(APP2VS Input)
{
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;
	return (float3x3)UserData.uvMatrix[IndexArray[3]];
}

float GetBinormalFlipping(APP2VS Input)
{
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;
	return 1.0 + IndexArray[2] * -2.0;
}

float4 GetUVRotation(APP2VS Input)
{
	// TODO: (ROD) Gotta rotate the tangent space as well as the uv
	float2 UV = mul(float3(Input.TexUVRotCenter * TexUnpack, 1.0), GetSkinnedUVMatrix(Input)).xy;
	return float4(UV.xy + (Input.TexDiffuse * TexUnpack), 0.0, 1.0);
}

VS2PS BundledMesh_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	// Get object-space properties
	float4 ObjectPos = Input.Pos * PosUnpack; // Unpack object-space position
	float3 ObjectTangent = Input.Tan * NormalUnpack.x + NormalUnpack.y; // Unpack object-space tangent
	float3 ObjectNormal = Input.Normal * NormalUnpack.x + NormalUnpack.y; // Unpack object-space normal
	float3x3 ObjectTBN = GetTangentBasis(ObjectTangent, ObjectNormal, GetBinormalFlipping(Input));

	// Get world-space properties
	float4x3 SkinnedWorldMatrix = GetSkinnedWorldMatrix(Input);
	float4 WorldPos = float4(mul(ObjectPos, SkinnedWorldMatrix), 1.0);
	float3x3 WorldTBN = mul(ObjectTBN, (float3x3)SkinnedWorldMatrix);

	// Output HPos
	Output.HPos = mul(WorldPos, ViewProjection);

	// Output world-space properties
	Output.Pos.xyz = WorldPos.xyz;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.WorldTangent = WorldTBN[0];
	Output.WorldBinormal = WorldTBN[1];
	Output.WorldNormal = WorldTBN[2];

	#if _HASUVANIMATION_
		Output.Tex0 = GetUVRotation(Input); // pass-through rotate coords
	#else
		Output.Tex0 = Input.TexDiffuse * TexUnpack; // pass-through texcoord
	#endif

	#if _HASSHADOW_
		Output.ShadowTex = GetShadowProjection(WorldPos);
	#endif

	#if _HASSHADOWOCCLUSION_
		Output.OccShadowTex = GetShadowProjection(WorldPos, true);
	#endif

	return Output;
}

// NOTE: This returns un-normalized for point, because point needs to be attenuated.
float3 GetLightVec(float3 WorldPos)
{
	#if _POINTLIGHT_
		return Lights[0].pos - WorldPos;
	#else
		return -Lights[0].dir;
	#endif
}

float2 GetGroundUV(float3 WorldPos, float3 WorldNormal)
{
	// HemiMapConstants: Offset x/y heightmapsize z / hemilerpbias w
	float2 GroundUV = 0.0;
	GroundUV.xy = ((WorldPos + (HemiMapConstants.z / 2.0) + WorldNormal).xz - HemiMapConstants.xy) / HemiMapConstants.z;
	GroundUV.y = 1.0 - GroundUV.y;
	return GroundUV;
}

float GetHemiLerp(float3 WorldPos, float3 WorldNormal)
{
	// LocalHeight scale, 1 for top and 0 for bottom
	float LocalHeight = (WorldPos.y - GeomBones[0][3][1]) * InvHemiHeightScale;
	float Offset = ((LocalHeight * 2.0) - 1.0) + HeightOverTerrain;
	Offset = clamp(Offset, (1.0 - HeightOverTerrain) * -2.0, 0.8);
	return saturate(((WorldNormal.y + Offset) * 0.5) + 0.5);
}

PS2FB BundledMesh_PS(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	// Get world-space properties
	float3 WorldPos = Input.Pos;
	float3 WorldTangent = normalize(Input.WorldTangent);
	float3 WorldBinormal = normalize(Input.WorldBinormal);
	float3 WorldNormal = normalize(Input.WorldNormal);
	float3x3 WorldTBN = float3x3(WorldTangent, WorldBinormal, WorldNormal);

	// Get world-space vectors
	float3 WorldLightVec = GetLightVec(WorldPos.xyz);
	float3 LightVec = normalize(WorldLightVec);
	float3 ViewVec = normalize(WorldSpaceCamPos - WorldPos);

	float4 ColorMap = tex2D(SampleDiffuseMap, Input.Tex0);

	#if _HASNORMALMAP_
		// Transform from tangent-space to world-space
		float4 NormalMap = tex2D(SampleNormalMap, Input.Tex0);
		float3 NormalVec = normalize((NormalMap.xyz * 2.0) - 1.0);
		NormalVec = normalize(mul(NormalVec, WorldTBN));
	#else
		float3 NormalVec = normalize(WorldNormal);
	#endif

	#if _HASSHADOW_
		float ShadowDir = GetShadowFactor(SampleShadowMap, Input.ShadowTex);
	#else
		float ShadowDir = 1.0;
	#endif

	#if _HASSHADOWOCCLUSION_
		float ShadowOccDir = GetShadowFactor(SampleShadowOccluderMap, Input.OccShadowTex);
	#else
		float ShadowOccDir = 1.0;
	#endif

	/*
		Calculate diffuse + specular lighting
	*/

	#if _POINTLIGHT_
		float3 Ambient = 0.0;
	#else
		#if _USEHEMIMAP_
			// GoundColor.a has an occlusion factor that we can use for static shadowing
			float2 GroundUV = GetGroundUV(WorldPos, NormalVec);
			float4 GroundColor = tex2D(SampleHemiMap, GroundUV);
			float HemiLerp = GetHemiLerp(WorldPos, NormalVec);
			float3 Ambient = lerp(GroundColor, HemiMapSkyColor, HemiLerp);
		#else
			float3 Ambient = Lights[0].color.w;
		#endif
	#endif

	#if _HASCOLORMAPGLOSS_
		float Gloss = ColorMap.a;
	#elif !_HASSTATICGLOSS_ && _HASNORMALMAP_
		float Gloss = NormalMap.a;
	#else
		float Gloss = StaticGloss;
	#endif

	#if _HASENVMAP_
		float3 Reflection = -reflect(ViewVec, NormalVec);
		float3 EnvMapColor = texCUBE(SampleCubeMap, Reflection);
		ColorMap.rgb = lerp(ColorMap, EnvMapColor, Gloss / 4.0);
	#endif

	#if _HASGIMAP_
		float4 GI = tex2D(SampleGIMap, Input.Tex0);
		float4 GI_TIS = GI; // M
		if (GI_TIS.a < 0.01)
		{
			GI = 1.0;
		}
	#else
		const float4 GI = 1.0;
	#endif

	#if _POINTLIGHT_
		float Attenuation = GetLightAttenuation(WorldLightVec, Lights[0].attenuation);
	#else
		const float Attenuation = 1.0;
	#endif

	ColorPair Light = ComputeLights(NormalVec, LightVec, ViewVec, SpecularPower);
	Light.Diffuse = (Light.Diffuse * Lights[0].color);
	Light.Specular = ((Light.Specular * Gloss) * Lights[0].color);

	float3 LightFactors = Attenuation * (ShadowDir * ShadowOccDir);
	Light.Diffuse = Light.Diffuse * LightFactors;
	Light.Specular = Light.Specular * LightFactors;

	// there is no Gloss map so alpha means transparency
	#if _POINTLIGHT_ && !_HASCOLORMAPGLOSS_
		Light.Diffuse *= ColorMap.a;
	#endif

	// Only add specular to bundledmesh with a glossmap (.a channel in NormalMap or ColorMap)
	// Prevents non-detailed bundledmesh from looking shiny
	#if !_HASCOLORMAPGLOSS_ && !_HASNORMALMAP_
		Light.Specular = 0.0;
	#endif
	float4 OutputColor = 1.0;
	OutputColor.rgb = ((ColorMap.rgb * (Ambient + Light.Diffuse)) + Light.Specular) * GI.rgb;

	/*
		Calculate fogging and other occluders
	*/

	#if _POINTLIGHT_
		OutputColor.rgb *= GetFogValue(WorldPos, WorldSpaceCamPos);
	#endif

	// Thermals
	if (FogColor.r < 0.01)
	{
		#if _HASGIMAP_
			if (GI_TIS.a < 0.01)
			{
				if (GI_TIS.g < 0.01)
				{
					OutputColor.rgb = float3(lerp(0.43, 0.17, ColorMap.b), 1.0, 0.0);
				}
				else
				{
					OutputColor.rgb = float3(GI_TIS.g, 1.0, 0.0);
				}
			}
			else
			{
				// Normal Wrecks also cold
				OutputColor.rgb = float3(lerp(0.43, 0.17, ColorMap.b), 1.0, 0.0);
			}
		#else
			OutputColor.rgb = float3(lerp(0.64, 0.3, ColorMap.b), 1.0, 0.0); // M // 0.61, 0.25
		#endif
	}

	/*
		Calculate alpha transparency
	*/

	float Alpha = 1.0;

	#if _HASENVMAP_
		float FresnelFactor = ComputeFresnelFactor(NormalVec, ViewVec);
		Alpha = lerp(ColorMap.a, 1.0, FresnelFactor);
	#endif

	#if _HASDOT3ALPHATEST_
		Alpha = dot(ColorMap.rgb, 1.0);
	#else
		#if _HASCOLORMAPGLOSS_
			Alpha = 1.0;
		#else
			Alpha = ColorMap.a;
		#endif
	#endif

	Output.Color.rgb = OutputColor.rgb;
	Output.Color.a = Alpha * Transparency.a;

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	#if !_POINTLIGHT_
		ApplyFog(Output.Color.rgb, GetFogValue(WorldPos, WorldSpaceCamPos));
	#endif

	return Output;
}

technique Variable
{
	pass Pass0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		AlphaTestEnable = (AlphaTest);
		AlphaRef = (AlphaTestRef);

		#if _POINTLIGHT_
			AlphaBlendEnable = TRUE;
			SrcBlend = SRCALPHA;
			DestBlend = ONE;
		#else
			AlphaBlendEnable = (AlphaBlendEnable);
			SrcBlend = SRCALPHA;
			DestBlend = INVSRCALPHA;
			ZWriteEnable = (DepthWrite);
		#endif

		VertexShader = compile vs_3_0 BundledMesh_VS();
		PixelShader = compile ps_3_0 BundledMesh_PS();
	}
}
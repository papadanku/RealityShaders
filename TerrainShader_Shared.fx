
/*
	Description: Shared functions for terrain shader
*/

#include "shaders/RealityGraphics.fxh"


struct APP2VS_Shared
{
	float4 Pos0 : POSITION0;
	float4 Pos1 : POSITION1;
	float4 MorphDelta : POSITION2;
	float3 Normal : NORMAL;
};

struct PS2FB
{
	float4 Color : COLOR;
	// float Depth : DEPTH;
};

/*
	Basic morphed technique
*/

float GetAdjustedNear()
{
	float NoLOD = _NearFarMorphLimits.x * 62500.0; // No-Lod: 250x normal -> 62500x
	#if HIGHTERRAIN
		float LOD = _NearFarMorphLimits.x * 16.0; // High-Lod: 4x normal -> 16x
	#else
		float LOD = _NearFarMorphLimits.x * 9.0; // Med-Lod: 3x normal -> 9x
	#endif

	// Only the near distance changes due to increased LOD distance. This needs to be multiplied by
	// the square of the factor by which we increased. Assuming 200m base lod this turns out to
	// If no-lods is enabled, then near limit is really low
	float AdjustedNear = (_NearFarMorphLimits.x < 0.00000001) ? NoLOD : LOD;
	return AdjustedNear;
}

void MorphPosition
(
	inout float4 WorldPos,
	in float4 MorphDelta,
	in float MorphDeltaAdderSelector,
	out float YDelta,
	out float InterpVal
)
{
	// tl: This is now based on squared values (besides camPos)
	// tl: This assumes that input WorldPos.w == 1 to work correctly! (it always is)
	// tl: This all works out because camera height is set to height+1 so
	//     CameraVec becomes (cx, cheight+1, cz) - (vx, 1, vz)
	// tl: YScale is now pre-multiplied into morphselector
	float3 CameraVec = _CameraPos.xwz - WorldPos.xwz;
	float CameraDist = dot(CameraVec, CameraVec);

	InterpVal = saturate(CameraDist * _NearFarMorphLimits.x - _NearFarMorphLimits.y);
	YDelta = dot(_MorphDeltaSelector, MorphDelta) * InterpVal;
	YDelta += dot(_MorphDeltaAdder[MorphDeltaAdderSelector * 256], MorphDelta);

	float AdjustedNear = GetAdjustedNear();
	InterpVal = saturate(CameraDist * AdjustedNear - _NearFarMorphLimits.y);
	WorldPos.y = WorldPos.y - YDelta;
}

float4 ProjToLighting(float4 HPos)
{
	// tl: This has been rearranged optimally (I believe) into 1 MUL and 1 MAD,
	//     don't change this without thinking twice.
	//     ProjOffset now includes screen->texture bias as well as half-texel offset
	//     ProjScale is screen->texture scale/invert operation
	// Tex = (HPos.x * 0.5 + 0.5 + HTexel, HPos.y * -0.5 + 0.5 + HTexel, HPos.z, HPos.w)
	return HPos * _TexProjScale + (_TexProjOffset * HPos.w);
}

/*
	Fill lightmapping
*/

struct VS2PS_Shared_ZFillLightMap
{
	float4 HPos : POSITION;
	float2 Tex0 : TEXCOORD0;
};

VS2PS_Shared_ZFillLightMap Shared_ZFillLightMap_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_ZFillLightMap Output = (VS2PS_Shared_ZFillLightMap)0;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	float YDelta, InterpVal;
	MorphPosition(WorldPos, Input.MorphDelta, Input.Pos0.z, YDelta, InterpVal);

	Output.HPos = mul(WorldPos, _ViewProj);
	Output.Tex0 = (Input.Pos0.xy * _ScaleBaseUV * _ColorLightTex.x) + _ColorLightTex.y;

	return Output;
}

float4 ZFillLightMapColor : register(c0);

float4 Shared_ZFillLightMap_1_PS(VS2PS_Shared_ZFillLightMap Input) : COLOR
{
	float4 Color = tex2D(SampleTex0_Clamp, Input.Tex0);
	float4 OutputColor;
	OutputColor.rgb = _GIColor * Color.b;
	OutputColor.a = saturate(Color.g);
	return OutputColor;
}

float4 Shared_ZFillLightMap_2_PS(VS2PS_Shared_ZFillLightMap Input) : COLOR
{
	return ZFillLightMapColor;
}

/*
	Pointlight
*/

struct VS2PS_Shared_PointLight
{
	float4 HPos : POSITION;
	float3 WorldPos : TEXCOORD0;
	float3 WorldNormal : TEXCOORD1;
};

VS2PS_Shared_PointLight Shared_PointLight_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_PointLight Output = (VS2PS_Shared_PointLight)0;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	float YDelta, InterpVal;
	MorphPosition(WorldPos, Input.MorphDelta, Input.Pos0.z, YDelta, InterpVal);

	Output.HPos = mul(WorldPos, _ViewProj);

	Output.WorldPos = WorldPos.xyz;
	Output.WorldNormal = normalize((Input.Normal * 2.0) - 1.0);

	return Output;
}

float4 Shared_PointLight_PS(VS2PS_Shared_PointLight Input) : COLOR
{
	return float4(GetTerrainLighting(Input.WorldPos, Input.WorldNormal), 0.0);
}

/*
	Low detail
*/

struct VS2PS_Shared_LowDetail
{
	float4 HPos : POSITION;
	float3 WorldPos : TEXCOORD0;
	float2 ColorTex : TEXCOORD1;
	float4 LightTex : TEXCOORD2;
	float2 CompTex : TEXCOORD3;
	float2 YPlaneTex : TEXCOORD4;
	float2 XPlaneTex : TEXCOORD5;
	float2 ZPlaneTex : TEXCOORD6;
	float3 WorldNormal : TEXCOORD7;
};

VS2PS_Shared_LowDetail Shared_LowDetail_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_LowDetail Output = (VS2PS_Shared_LowDetail)0;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	float YDelta, InterpVal;
	MorphPosition(WorldPos, Input.MorphDelta, Input.Pos0.z, YDelta, InterpVal);

	Output.HPos = mul(WorldPos, _ViewProj);
	Output.WorldPos = WorldPos.xyz;

	Output.ColorTex = (Input.Pos0.xy * _ScaleBaseUV *_ColorLightTex.x) + _ColorLightTex.y;

	float3 Tex = 0.0;
	Tex.x = Input.Pos0.x * _TexScale.x;
	Tex.y = WorldPos.y * _TexScale.y;
	Tex.z = Input.Pos0.y * _TexScale.z;

	float2 YPlaneTexCoord = Tex.xz;
	float2 XPlaneTexCoord = Tex.zy;
	float2 ZPlaneTexCoord = Tex.xy;

	Output.CompTex = (YPlaneTexCoord * _DetailTex.x) + _DetailTex.y;
	Output.YPlaneTex = (YPlaneTexCoord * _FarTexTiling.z);
	Output.XPlaneTex = (XPlaneTexCoord * _FarTexTiling.xy) + float2(0.0, _FarTexTiling.w);
	Output.ZPlaneTex = (ZPlaneTexCoord * _FarTexTiling.xy) + float2(0.0, _FarTexTiling.w);

	Output.LightTex = ProjToLighting(Output.HPos);

	Output.WorldNormal = normalize((Input.Normal * 2.0) - 1.0);

	return Output;
}

float4 Shared_LowDetail_PS(VS2PS_Shared_LowDetail Input) : COLOR
{
	float3 WorldPos = Input.WorldPos;
	float3 Normals = normalize(Input.WorldNormal);
	
	float3 BlendValue = saturate(abs(Normals) - _BlendMod);
	BlendValue = saturate(BlendValue / dot(1.0, BlendValue));

	float4 AccumLights = tex2Dproj(SampleTex1_Clamp, Input.LightTex);
	float4 Light = 2.0 * AccumLights.w * _SunColor + AccumLights;
	float4 ColorMap = tex2D(SampleTex0_Clamp, Input.ColorTex);

	// If thermals assume no shadows and gray color
	if (FogColor.r < 0.01)
	{
		Light.rgb = 2.0 * _SunColor + AccumLights;
		ColorMap.rgb = 1.0 / 3.0;
	}

	#if LIGHTONLY
		ApplyFog(Light.rgb, GetFogValue(WorldPos, _CameraPos));
		return Light;
	#endif

	float4 LowComponent = tex2D(SampleTex5_Clamp, Input.CompTex);
	float4 YPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.YPlaneTex);
	float4 XPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.XPlaneTex);
	float4 ZPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.ZPlaneTex);
	float Mounten = (XPlaneLowDetailmap.y * BlendValue.x) +
					(YPlaneLowDetailmap.x * BlendValue.y) +
					(ZPlaneLowDetailmap.y * BlendValue.z);

	float4 OutputColor = ColorMap * Light * 2.0;
	OutputColor *= lerp(0.5, YPlaneLowDetailmap.z, LowComponent.x);
	OutputColor *= lerp(0.5, Mounten, LowComponent.z);

	// tl: changed a few things with this factor:
	// - using (1-a) is unnecessary, we can just invert the lerp in the ps instead.
	// - by pre-multiplying the _WaterHeight, we can change the (wh-wp)*c to (-wp*c)+whc i.e. from ADD+MUL to MAD
	float WaterLerp = saturate((WorldPos.y / -3.0) + _WaterHeight);
	OutputColor = lerp(OutputColor * 4.0, _TerrainWaterColor, WaterLerp);

	ApplyFog(OutputColor.rgb, GetFogValue(WorldPos, _CameraPos));
	return OutputColor;
}

/*
	Dynamic shadowmapping
*/

struct VS2PS_Shared_DynamicShadowmap
{
	float4 HPos : POSITION;
	float4 ShadowTex : TEXCOORD0;
};

VS2PS_Shared_DynamicShadowmap Shared_DynamicShadowmap_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_DynamicShadowmap Output;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	Output.HPos = mul(WorldPos, _ViewProj);

	Output.ShadowTex = mul(WorldPos, _LightViewProj);
	Output.ShadowTex.z = Output.ShadowTex.w;

	return Output;
}

float4 Shared_DynamicShadowmap_PS(VS2PS_Shared_DynamicShadowmap Input) : COLOR
{
	#if NVIDIA
		float AvgShadowValue = tex2Dproj(SampleTex2_Clamp, Input.ShadowTex);
	#else
		float AvgShadowValue = tex2Dproj(SampleTex2_Clamp, Input.ShadowTex) == 1.0;
	#endif
	return AvgShadowValue.x;
}

/*
	Directional light shadows
*/

struct VS2PS_Shared_DirectionalLightShadows
{
	float4 HPos : POSITION;
	float2 Tex0 : TEXCOORD0;
	float4 ShadowTex : TEXCOORD1;
	float2 Z : TEXCOORD2;
};

VS2PS_Shared_DirectionalLightShadows Shared_DirectionalLightShadows_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_DirectionalLightShadows Output;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	float YDelta, InterpVal;
	MorphPosition(WorldPos, Input.MorphDelta, Input.Pos0.z, YDelta, InterpVal);

	Output.HPos = mul(WorldPos, _ViewProj);

	Output.ShadowTex = mul(WorldPos, _LightViewProj);
	float LightZ = mul(WorldPos, _LightViewProjOrtho).z;
	Output.Z.xy = Output.ShadowTex.z;
	#if NVIDIA
		Output.ShadowTex.z = LightZ * Output.ShadowTex.w;
	#else
		Output.ShadowTex.z = LightZ;
	#endif

	Output.Tex0 = (Input.Pos0.xy * _ScaleBaseUV * _ColorLightTex.x) + _ColorLightTex.y;

	return Output;
}

/*
	Underwater
*/

struct VS2PS_Shared_UnderWater
{
	float4 HPos : POSITION;
	float3 WorldPos : TEXCOORD0;
};

VS2PS_Shared_UnderWater Shared_UnderWater_VS(APP2VS_Shared Input)
{
	VS2PS_Shared_UnderWater Output;

	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);

	float YDelta, InterpVal;
	MorphPosition(WorldPos, Input.MorphDelta, Input.Pos0.z, YDelta, InterpVal);

	Output.HPos = mul(WorldPos, _ViewProj);
	Output.WorldPos = WorldPos;

	return Output;
}

float4 Shared_UnderWater_PS(VS2PS_Shared_UnderWater Input) : COLOR
{
	float3 WorldPos = Input.WorldPos;
	float3 OutputColor = _TerrainWaterColor.rgb;
	float WaterLerp = saturate((WorldPos.y / -3.0) + _WaterHeight);

	ApplyFog(OutputColor, GetFogValue(WorldPos, _CameraPos));

	return float4(OutputColor, WaterLerp);
}

/*
	Surrounding Terrain (ST)
*/

struct APP2VS_Shared_ST_Normal
{
	float2 Pos0 : POSITION0;
	float2 TexCoord0 : TEXCOORD0;
	float4 Pos1 : POSITION1;
	float3 Normal : NORMAL;
};

struct VS2PS_Shared_ST_Normal
{
	float4 HPos : POSITION;
	float3 WorldPos : TEXCOORD0;
	float2 ColorLightTex : TEXCOORD1;
	float2 LowDetailTex : TEXCOORD2;
	float2 YPlaneTex : TEXCOORD3;
	float2 XPlaneTex : TEXCOORD4;
	float2 ZPlaneTex : TEXCOORD5;
	float3 WorldNormal : TEXCOORD6;
};

VS2PS_Shared_ST_Normal Shared_ST_Normal_VS(APP2VS_Shared_ST_Normal Input)
{
	VS2PS_Shared_ST_Normal Output;

	Output.ColorLightTex = (Input.TexCoord0 * _STColorLightTex.x) + _STColorLightTex.y;
	Output.LowDetailTex = (Input.TexCoord0 * _STLowDetailTex.x) + _STLowDetailTex.y;

	float4 WorldPos = 0.0;
	WorldPos.xz = mul(float4(Input.Pos0.xy, 0.0, 1.0), _STTransXZ).xy;
	WorldPos.yw = (Input.Pos1.xw * _STScaleTransY.xy) + _STScaleTransY.zw;

	Output.HPos = mul(WorldPos, _ViewProj);
	Output.WorldPos = WorldPos.xyz;

	float3 Tex = 0.0;
	Tex.x = WorldPos.x * _STTexScale.x;
	Tex.y = -(Input.Pos1.x * _STTexScale.y);
	Tex.z = WorldPos.z * _STTexScale.z;

	float2 YPlaneTexCoord = Tex.xz;
	float2 XPlaneTexCoord = Tex.zy;
	float2 ZPlaneTexCoord = Tex.xy;

	Output.YPlaneTex = (YPlaneTexCoord * _STFarTexTiling.z);
	Output.XPlaneTex = (XPlaneTexCoord * _STFarTexTiling.xy) + float2(0.0, _STFarTexTiling.w);
	Output.ZPlaneTex = (ZPlaneTexCoord * _STFarTexTiling.xy) + float2(0.0, _STFarTexTiling.w);

	Output.WorldNormal = Input.Normal;

	return Output;
}

float4 Shared_ST_Normal_PS(VS2PS_Shared_ST_Normal Input) : COLOR
{
	float3 WorldNormal = normalize(Input.WorldNormal);

	float3 BlendValue = saturate(abs(WorldNormal) - _BlendMod);
	BlendValue = saturate(BlendValue / dot(1.0, BlendValue));

	float4 ColorMap = tex2D(SampleTex0_Clamp, Input.ColorLightTex);

	// If thermals assume gray color
	if (FogColor.r < 0.01)
	{
		ColorMap.rgb = 1.0 / 3.0;
	}

	float4 LowComponent = tex2D(SampleTex5_Clamp, Input.LowDetailTex);
	float4 YPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.YPlaneTex);
	float4 XPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.XPlaneTex);
	float4 ZPlaneLowDetailmap = tex2D(SampleTex4_Wrap, Input.ZPlaneTex);
	float Mounten = (XPlaneLowDetailmap.y * BlendValue.x) +
					(YPlaneLowDetailmap.x * BlendValue.y) +
					(ZPlaneLowDetailmap.y * BlendValue.z);

	float4 LowDetailMap = lerp(0.5, YPlaneLowDetailmap.z, LowComponent.x);
	LowDetailMap *= lerp(0.5, Mounten, LowComponent.z);

	float4 OutputColor = (ColorMap * LowDetailMap) * 4.0;
	OutputColor.rb = (_GIColor.r < 0.01) ? 0.0 : OutputColor.rb; // M (temporary fix)

	ApplyFog(OutputColor.rgb, GetFogValue(Input.WorldPos.xyz, _CameraPos.xyz));

	return OutputColor;
}

technique Shared_SurroundingTerrain
{
	// Normal
	pass Pass0
	{
		CullMode = CW;

		ZEnable = TRUE;
		ZWriteEnable = TRUE;
		ZFunc = LESSEQUAL;

		AlphaBlendEnable = FALSE;

		VertexShader = compile vs_3_0 Shared_ST_Normal_VS();
		PixelShader = compile ps_3_0 Shared_ST_Normal_PS();
	}
}

/*
	Shadow occlusion shaders
*/

float4x4 _vpLightMat : vpLightMat;
float4x4 _vpLightTrapezMat : vpLightTrapezMat;

struct HI_APP2VS_OccluderShadow
{
	float4 Pos0 : POSITION0;
	float4 Pos1 : POSITION1;
};

struct HI_VS2PS_OccluderShadow
{
	float4 HPos : POSITION;
	float4 DepthPos : TEXCOORD0;
};

HI_VS2PS_OccluderShadow Hi_OccluderShadow_VS(HI_APP2VS_OccluderShadow Input)
{
	HI_VS2PS_OccluderShadow Output;
	float4 WorldPos = 0.0;
	WorldPos.xz = (Input.Pos0.xy * _ScaleTransXZ.xy) + _ScaleTransXZ.zw;
	WorldPos.yw = (Input.Pos1.xw * _ScaleTransY.xy);
	Output.HPos = GetMeshShadowProjection(WorldPos, _vpLightTrapezMat, _vpLightMat);
	Output.DepthPos = Output.HPos;
	return Output;
}

float4 Hi_OccluderShadow_PS(HI_VS2PS_OccluderShadow Input) : COLOR
{
	#if NVIDIA
		return 0.5;
	#else
		return Input.DepthPos.z / Input.DepthPos.w;
	#endif
}

technique TerrainOccludershadow
{
	// Pass 16
	pass OccluderShadow
	{
		CullMode = NONE;

		ZEnable = TRUE;
		ZWriteEnable = TRUE;
		ZFunc = LESS;

		AlphaBlendEnable = FALSE;
		AlphaTestEnable = FALSE;

		#if NVIDIA
			ColorWriteEnable = 0;
		#else
			ColorWriteEnable = RED|BLUE|GREEN|ALPHA;
		#endif

		VertexShader = compile vs_3_0 Hi_OccluderShadow_VS();
		PixelShader = compile ps_3_0 Hi_OccluderShadow_PS();
	}
}

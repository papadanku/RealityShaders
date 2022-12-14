
/*
	Description: Renders circle for debug shaders
*/

#include "shaders/RealityGraphics.fxh"

float4x4 _WorldViewProj : WorldViewProjection;
bool _ZBuffer : ZBUFFER;

// string Category = "Effects\\Lighting";

struct APP2VS
{
	float4 Pos : POSITION;
	float4 Diffuse : COLOR;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float4 Diffuse : TEXCOORD1;
};

struct PS2FB
{
	float4 Color : COLOR;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

VS2PS Debug_Circle_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	Output.HPos = mul(float4(Input.Pos.xyz, 1.0), _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Diffuse.xyz = Input.Diffuse.xyz;
	Output.Diffuse.w = 0.8f;

	return Output;
}

PS2FB Debug_Circle_PS(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = Input.Diffuse;

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique t0
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_D3DCOLOR, D3DDECLUSAGE_COLOR, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		CullMode = NONE;
		DepthBias = -0.00001;
		ShadeMode = FLAT;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 1;
		ZEnable = FALSE;
		ZFunc = LESSEQUAL;

		VertexShader = compile vs_3_0 Debug_Circle_VS();
		PixelShader = compile ps_3_0 Debug_Circle_PS();
	}
}

//$ TODO: Temporary fix for enabling z-buffer writing for collision meshes.
technique t0_usezbuffer
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_D3DCOLOR, D3DDECLUSAGE_COLOR, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		CullMode = NONE;
		AlphaBlendEnable = FALSE;
		ZWriteEnable = 1;
		ZEnable = TRUE;

		VertexShader = compile vs_3_0 Debug_Circle_VS();
		PixelShader = compile ps_3_0 Debug_Circle_PS();
	}
}

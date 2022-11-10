
/*
	Data for RaShaderSM
*/

// Fallback stuff
string DeprecationList[] =
{
	{ "hasnormalmap", "objspacenormalmap", "" },
	{ "usehemimap", "hasenvmap", "" },
	{ "hasshadow", "" },
	{ "hascolormapgloss", "" },
};

uniform float4 ObjectSpaceCamPos;
uniform float4 WorldSpaceCamPos;

uniform int AlphaTestRef = 0;
uniform bool DepthWrite = 1;
uniform bool DoubleSided = 2;

uniform float4 DiffuseColor;
uniform float4 SpecularColor;
uniform float SpecularPower;
uniform float StaticGloss;
uniform float4 Ambient;

uniform float4 HemiMapSkyColor;
uniform float HeightOverTerrain = 0;

uniform float Reflectivity;

uniform float4x3 MatBones[26];

Light Lights[1];

// Common SkinnedMesh samplers

#define CREATE_SAMPLER(NAME, TEXTURE, ADDRESS) \
	sampler NAME = sampler_state \
	{ \
		Texture = (TEXTURE); \
		MipFilter = LINEAR; \
		MinFilter = LINEAR; \
		MagFilter = LINEAR; \
		AddressU = ADDRESS; \
		AddressV = ADDRESS; \
		AddressW = ADDRESS; \
	}; \

uniform texture HemiMap;
CREATE_SAMPLER(SampleHemiMap, HemiMap, CLAMP)

uniform texture CubeMap;
CREATE_SAMPLER(SampleCubeMap, CubeMap, WRAP)

uniform texture DiffuseMap;
CREATE_SAMPLER(SampleDiffuseMap, DiffuseMap, CLAMP)

uniform texture NormalMap;
CREATE_SAMPLER(SampleNormalMap, NormalMap, CLAMP)

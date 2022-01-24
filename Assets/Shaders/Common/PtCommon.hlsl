#include "UnityRaytracingMeshUtils.cginc"

#define MAX_DEPTH (5)
#define MIN_DEPTH (1)
//#define RaytracingMaxRecursion (4)

#define _RaytracingRayBias 0.001
#define  ATTRIBUTES_NEED_TANGENT
#define  ATTRIBUTES_NEED_TEXCOORD0

#define CBUFFER_START(name) cbuffer name {
#define CBUFFER_END };

#define RAYTRACINGRENDERERFLAG_OPAQUE (1)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW_TRANSPARENT (2)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW_OPAQUE (4)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW (6)
#define RAYTRACINGRENDERERFLAG_AMBIENT_OCCLUSION (8)
#define RAYTRACINGRENDERERFLAG_REFLECTION (16)
#define RAYTRACINGRENDERERFLAG_GLOBAL_ILLUMINATION (32)
#define RAYTRACINGRENDERERFLAG_RECURSIVE_RENDERING (64)
#define RAYTRACINGRENDERERFLAG_PATH_TRACING (128)


#define SAMPLE_TEXTURE2D_LOD(textureName, samplerName, coord2, lod) textureName.SampleLevel(samplerName, coord2, lod)
#define TEXTURE2D(textureName) Texture2D textureName
#define SAMPLER(samplerName) SamplerState samplerName


CBUFFER_START(CameraBuffer)
float4x4 _InvCameraViewProj;
float3 _WorldSpaceCameraPos;
float _CameraFarDistance;
float3 _FocusCameraLeftBottomCorner;
float3 _FocusCameraRight;
float3 _FocusCameraUp;
float2 _FocusCameraSize;
float _FocusCameraHalfAperture;
float4 _Sundir;
float4 _Up;
float4 _Right;
float4 _Forward;

uint _DirectionalLightCount;
uint _PunctualLightCount;
uint _AreaLightCount;
uint _EnvLightCount;

float _AngularDiameter;
int _FogEnabled;
int _PBRFogEnabled;
int _EnableVolumetricFog;
float _MaxFogDistance;
float4 _FogColor;
float _FogColorMode;
float _Pad0;
float _Pad1;
float _Pad2;
float4 _MipFogParameters;
float4 _HeightFogBaseScattering;
float _HeightFogBaseExtinction;
float _HeightFogBaseHeight;
float _GlobalFogAnisotropy;
int _VolumetricFilteringEnabled;
float2 _HeightFogExponents;
int  _FrameIndex;
CBUFFER_END

CBUFFER_START(UnityPerMaterial)
float4 _Color;
float4 _TransmittanceColor;
float4 _EmissionColor;
float _Smoothness;
float _Metallic;
float _IOR;
float _CoatMask;
float _TransmittanceMask;
float4 _ShapeParamsAndMaxScatterDists;
float4 _worldScaleAndFilterRadiusAndThicknessRemap;
float4 _transmissionTintAndFresnel0;
float4 _disabledTransmissionTintAndFresnel0;
CBUFFER_END

RaytracingAccelerationStructure _AccelerationStructure;

struct RayIntersection
{
  int remainingDepth;
  uint4 PRNGStates;
  float4 color;
  float t;
  bool shadow;
};



inline void GenerateCameraRay(out float3 origin, out float3 direction)
{
  float2 xy = DispatchRaysIndex().xy + 0.5f; // center in the middle of the pixel.
  float2 screenPos = xy / DispatchRaysDimensions().xy * 2.0f - 1.0f;

  // Un project the pixel coordinate into a ray.
  float4 world = mul(_InvCameraViewProj, float4(screenPos, 0, 1));

  world.xyz /= world.w;
  origin = _WorldSpaceCameraPos.xyz;
  direction = normalize(world.xyz - origin);
}

inline void GenerateCameraRayWithOffset(out float3 origin, out float3 direction, float2 offset)
{
  float2 xy = DispatchRaysIndex().xy + offset;
  float2 screenPos = xy / DispatchRaysDimensions().xy * 2.0f - 1.0f;

  // Un project the pixel coordinate into a ray.
  float4 world = mul(_InvCameraViewProj, float4(screenPos, 0, 1));

  world.xyz /= world.w;
  origin = _WorldSpaceCameraPos.xyz;
  direction = normalize(world.xyz - origin);
}

inline void GenerateFocusCameraRayWithOffset(out float3 origin, out float3 direction, float2 apertureOffset, float2 offset)
{
  float2 xy = DispatchRaysIndex().xy + offset;
  float2 uv = xy / DispatchRaysDimensions().xy;

  float3 world = _FocusCameraLeftBottomCorner + uv.x * _FocusCameraSize.x * _FocusCameraRight + uv.y * _FocusCameraSize.y * _FocusCameraUp;
  origin = _WorldSpaceCameraPos.xyz + _FocusCameraHalfAperture * apertureOffset.x * _FocusCameraRight + _FocusCameraHalfAperture * apertureOffset.y * _FocusCameraUp;
  direction = normalize(world.xyz - origin);
}

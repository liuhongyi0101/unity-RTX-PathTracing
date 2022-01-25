#ifndef UNITY_LIGHTING_INCLUDED
#define UNITY_LIGHTING_INCLUDED
#define GLOBAL_RESOURCE(type, name, reg) type name : register(reg, space1);
#define GLOBAL_CBUFFER_START(name, reg) cbuffer name : register(reg, space1) {

#define RAY_TRACING_ACCELERATION_STRUCTURE_REGISTER             t0
#define RAY_TRACING_LIGHT_CLUSTER_REGISTER                      t1
#define RAY_TRACING_LIGHT_DATA_REGISTER                         t3
#define RAY_TRACING_ENV_LIGHT_DATA_REGISTER                     t4

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonShadow.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Sampling/Sampling.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/AreaLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/VolumeRendering.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
#include "../../Scripts/Lights/Lighting/LightDefinition.cs.hlsl"
#include "../../Scripts/Lights/LightLoop/raytracing/ShaderVariablesRaytracingLightLoop.cs.hlsl"
#include "../Common/SphericalQuad.hlsl"
GLOBAL_RESOURCE(StructuredBuffer<uint>, _RaytracingLightCluster, RAY_TRACING_LIGHT_CLUSTER_REGISTER);
GLOBAL_RESOURCE(StructuredBuffer<LightData>, _LightDatasRT, RAY_TRACING_LIGHT_DATA_REGISTER);
GLOBAL_RESOURCE(StructuredBuffer<EnvLightData>, _EnvLightDatasRT, RAY_TRACING_ENV_LIGHT_DATA_REGISTER);



StructuredBuffer<DirectionalLightData> _DirectionalLightDatas;
StructuredBuffer<LightData>            _LightDatas;
StructuredBuffer<EnvLightData>         _EnvLightDatas;
//#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
//
//#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightDefinition.cs.hlsl"
//#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightLoop/HDShadow.hlsl"

#endif // UNITY_LIGHTING_INCLUDED

// Ray tracing includes
#include "RaytracingFragInputs.hlsl"
//#include "../Common/AtmosphericScatteringRayTracing.hlsl"

// Path tracing includes
#include "PathTracingIntersection.hlsl"
#include "PathTracingLightOne.hlsl"
#include "PathTracingVolume.hlsl"


#include "../Common/LitData.hlsl"
#include "../Common/Lit.hlsl"



//#ifdef HAS_LIGHTLOOP
//#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/PathTracing/Shaders/PathTracingLight.hlsl"
//#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/PathTracing/Shaders/PathTracingSampling.hlsl"
//#endif

float PowerHeuristic(float f, float b)
{
    return Sq(f) / (Sq(f) + Sq(b));
}

float3 GetPositionBias(float3 geomNormal, float bias, bool below)
{
    return geomNormal * (below ? -bias : bias);
}
float roughnessToSpreadAngle(float roughness)
{
    // FIXME: The mapping will most likely need adjustment...
    return roughness * PI / 8;
}

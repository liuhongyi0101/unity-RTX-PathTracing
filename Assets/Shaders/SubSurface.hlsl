#ifndef UNITY_SUB_SURFACE_INCLUDED
#define UNITY_SUB_SURFACE_INCLUDED

//#include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/Raytracing/Shaders/SubSurface/RayTracingIntersectionSubSurface.hlsl"

// Data for the sub-surface walk
struct ScatteringResult
{
    bool hit;
    float3 outputPosition;
    float3 outputNormal;
    float3 outputDirection;
    float3 outputDiffuse;
    float3 outputThroughput;
};

// This function does the remapping from scattering color and distance to sigmaS and sigmaT
void RemapSubSurfaceScatteringParameters(float3 albedo, float3 radius, out float3 sigmaS, out float3 sigmaT)
{
    float3 a = 1.0 - exp(albedo * (-5.09406 + albedo * (2.61188 - albedo * 4.31805)));
    float3 s = 1.9 - albedo + 3.5 * (albedo - 0.8) * (albedo - 0.8);

    sigmaT = 1.0 / max(radius * s, 1e-16);
    sigmaS = sigmaT * a;
}

// This function allows us to pick a color channel
int GetChannel(float u1, float3 channelWeight)
{
    if (channelWeight.x > u1)
        return 0;
    if ((channelWeight.x + channelWeight.y) > u1)
        return 1;
    return 2;
}

// Safe division to avoid nans
float3 SafeDivide(float3 val0, float3 val1)
{
    float3 result;
    result.x = val1.x != 0.0 ? val0.x / val1.x : 0.0;
    result.y = val1.y != 0.0 ? val0.y / val1.y : 0.0;
    result.z = val1.z != 0.0 ? val0.z / val1.z : 0.0;
    return result;
}

#define MAX_WALK_STEPS 16
#define DIM_OFFSET 42

struct Result
{
    float3  exitPosition;
    float3 exitNormal;
    float3 throughput;
};

bool RandomWalk(float3 position, float3 normal, inout uint4 states, float3 diffuseColor, float3 meanFreePath, uint2 pixelCoord, out Result result)
{
    // Remap from our user-friendly parameters to and sigmaS and sigmaT
    float3 sigmaS, sigmaT;
    RemapSubSurfaceScatteringParameters(diffuseColor, meanFreePath, sigmaS, sigmaT);

    // Initialize the intersection structure
 //   PathIntersection intersection;
 //   intersection.remainingDepth = MAX_DEPTH + 1;

    // Tracing reflection.
    RayIntersection reflectionRayIntersection;
    reflectionRayIntersection.remainingDepth = MAX_DEPTH + 1;
    reflectionRayIntersection.PRNGStates = states;
    reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);


    // Initialize the walk parameters
    RayDesc rayDesc;
    rayDesc.Origin = position - normal * _RaytracingRayBias;
    rayDesc.TMin = 0.0;

    bool hit;
    uint walkIdx = 0;

    result.throughput = 1.0;

    do // Start our random walk
    {
        // Samples for direction, distance and channel selection
       // float dirSample0 = GetSample(pixelCoord, _RaytracingSampleIndex, DIM_OFFSET + 4 * walkIdx + 0);
        float dirSample0 = GetRandomValue(states);
        float dirSample1 = GetRandomValue(states);
        float distSample = GetRandomValue(states);

        float channelSample = GetRandomValue(states);

        // Compute the per-channel weight
        float3 weights = result.throughput * SafeDivide(sigmaS, sigmaT);

        // Normalize our weights
        float wSum = weights.x + weights.y + weights.z;
        float3 channelWeights = SafeDivide(weights, wSum);

        // Evaluate what channel we should be using for this sample
        uint channelIdx = GetChannel(channelSample, channelWeights);

        // Evaluate the length of our steps
        rayDesc.TMax = -log(1.0 - distSample) / sigmaT[channelIdx];

        // Sample our next path segment direction
        ONB uvw;
        ONBBuildFromW(uvw, normal);

        rayDesc.Direction = walkIdx ?
            GetRandomOnUnitSphere(states) : ONBLocal(uvw, CosineSampleHemisphere(float2(dirSample0, dirSample1)));
        
        // Initialize the intersection data
        reflectionRayIntersection.t = -1.0;

        // Do the next step
        TraceRay(_AccelerationStructure, RAY_FLAG_FORCE_OPAQUE | RAY_FLAG_CULL_FRONT_FACING_TRIANGLES,
            128, 0, 1, 1, rayDesc, reflectionRayIntersection);

        // Check if we hit something
        hit = reflectionRayIntersection.t > 0.0;

        // How much did the ray travel?
        float t = hit ? reflectionRayIntersection.t : rayDesc.TMax;

        // Evaluate the transmittance for the current segment
        float3 transmittance = exp(-t * sigmaT);

        // Evaluate the pdf for the current segment
        float pdf = dot((hit ? transmittance : sigmaT * transmittance), channelWeights);

        // Contribute to the throughput
        result.throughput *= SafeDivide(hit ? transmittance : sigmaS * transmittance, pdf);

        // Compute the next path position
        rayDesc.Origin += rayDesc.Direction * t;

        // increment the path depth
        walkIdx++;
    } while (!hit && walkIdx < MAX_WALK_STEPS);

    // Set the exit intersection position and normal
    if (!hit)
    {
        result.exitPosition = position;
        result.exitNormal = normal;
        result.throughput = diffuseColor;

        // By not returning false here, we default to a diffuse BRDF when an intersection is not found;
        // this is physically wrong, but may prove more convenient for a user, as results will look
        // like diffuse instead of getting slightly darker when the mean free path becomes shorter.
        //return false;
    }
    else
    {
        result.exitPosition = rayDesc.Origin;
        result.exitNormal = reflectionRayIntersection.color;
    }

    return true;
}

#endif // UNITY_SUB_SURFACE_INCLUDED

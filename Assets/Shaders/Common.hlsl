#include "UnityRaytracingMeshUtils.cginc"

#define MAX_DEPTH (6)
#define _RaytracingMaxRecursion 6
#define _RaytracingRayBias 0.001

#define CBUFFER_START(name) cbuffer name {
#define CBUFFER_END };

// Macro that interpolate any attribute using barycentric coordinates
#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)


#define RAYTRACINGRENDERERFLAG_OPAQUE (1)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW_TRANSPARENT (2)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW_OPAQUE (4)
#define RAYTRACINGRENDERERFLAG_CAST_SHADOW (6)
#define RAYTRACINGRENDERERFLAG_AMBIENT_OCCLUSION (8)
#define RAYTRACINGRENDERERFLAG_REFLECTION (16)
#define RAYTRACINGRENDERERFLAG_GLOBAL_ILLUMINATION (32)
#define RAYTRACINGRENDERERFLAG_RECURSIVE_RENDERING (64)
#define RAYTRACINGRENDERERFLAG_PATH_TRACING (128)

// Structure to fill for intersections
struct IntersectionVertex
{
    // Object space normal of the vertex
    float3 normalOS;
    // Object space tangent of the vertex
    float4 tangentOS;
    // UV coordinates
    float4 texCoord0;
    float4 texCoord1;
    float4 texCoord2;
    float4 texCoord3;
    float4 color;

#ifdef USE_RAY_CONE_LOD
    // Value used for LOD sampling
    float  triangleArea;
    float  texCoord0Area;
    float  texCoord1Area;
    float  texCoord2Area;
    float  texCoord3Area;
#endif
};

struct AttributeData
{
    float2 barycentrics;
};
// Fetch the intersetion vertex data for the target vertex
void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
{
    outVertex.normalOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);

#ifdef ATTRIBUTES_NEED_TANGENT
    outVertex.tangentOS = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTangent);
#else
    outVertex.tangentOS = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD0
    outVertex.texCoord0 = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTexCoord0);
#else
    outVertex.texCoord0 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD1
    outVertex.texCoord1 = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTexCoord1);
#else
    outVertex.texCoord1 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD2
    outVertex.texCoord2 = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTexCoord2);
#else
    outVertex.texCoord2 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD3
    outVertex.texCoord3 = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeTexCoord3);
#else
    outVertex.texCoord3 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_COLOR
    outVertex.color = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeColor);
#else
    outVertex.color = 0.0;
#endif
}

void GetCurrentIntersectionVertex(AttributeData attributeData, out IntersectionVertex outVertex)
{
    // Fetch the indices of the currentr triangle
    uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

    // Fetch the 3 vertices
    IntersectionVertex v0, v1, v2;
    FetchIntersectionVertex(triangleIndices.x, v0);
    FetchIntersectionVertex(triangleIndices.y, v1);
    FetchIntersectionVertex(triangleIndices.z, v2);

    // Compute the full barycentric coordinates
    float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

    // Interpolate all the data
    outVertex.normalOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates);

#ifdef ATTRIBUTES_NEED_TANGENT
    outVertex.tangentOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangentOS, v1.tangentOS, v2.tangentOS, barycentricCoordinates);
#else
    outVertex.tangentOS = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD0
    outVertex.texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
#else
    outVertex.texCoord0 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD1
    outVertex.texCoord1 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord1, v1.texCoord1, v2.texCoord1, barycentricCoordinates);
#else
    outVertex.texCoord1 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD2
    outVertex.texCoord2 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord2, v1.texCoord2, v2.texCoord2, barycentricCoordinates);
#else
    outVertex.texCoord2 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_TEXCOORD3
    outVertex.texCoord3 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord3, v1.texCoord3, v2.texCoord3, barycentricCoordinates);
#else
    outVertex.texCoord3 = 0.0;
#endif

#ifdef ATTRIBUTES_NEED_COLOR
    outVertex.color = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.color, v1.color, v2.color, barycentricCoordinates);
#else
    outVertex.color = 0.0;
#endif

#ifdef USE_RAY_CONE_LOD
    // Compute the lambda value (area computed in object space)
    outVertex.triangleArea = length(cross(v1.positionOS - v0.positionOS, v2.positionOS - v0.positionOS));
    outVertex.texCoord0Area = abs((v1.texCoord0.x - v0.texCoord0.x) * (v2.texCoord0.y - v0.texCoord0.y) - (v2.texCoord0.x - v0.texCoord0.x) * (v1.texCoord0.y - v0.texCoord0.y));
    outVertex.texCoord1Area = abs((v1.texCoord1.x - v0.texCoord1.x) * (v2.texCoord1.y - v0.texCoord1.y) - (v2.texCoord1.x - v0.texCoord1.x) * (v1.texCoord1.y - v0.texCoord1.y));
    outVertex.texCoord2Area = abs((v1.texCoord2.x - v0.texCoord2.x) * (v2.texCoord2.y - v0.texCoord2.y) - (v2.texCoord2.x - v0.texCoord2.x) * (v1.texCoord2.y - v0.texCoord2.y));
    outVertex.texCoord3Area = abs((v1.texCoord3.x - v0.texCoord3.x) * (v2.texCoord3.y - v0.texCoord3.y) - (v2.texCoord3.x - v0.texCoord3.x) * (v1.texCoord3.y - v0.texCoord3.y));
#endif
}

// Compute the proper world space geometric normal from the intersected triangle
void GetCurrentIntersectionGeometricNormal(AttributeData attributeData, out float3 geomNormalWS)
{
    uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());
    float3 p0 = UnityRayTracingFetchVertexAttribute3(triangleIndices.x, kVertexAttributePosition);
    float3 p1 = UnityRayTracingFetchVertexAttribute3(triangleIndices.y, kVertexAttributePosition);
    float3 p2 = UnityRayTracingFetchVertexAttribute3(triangleIndices.z, kVertexAttributePosition);

    geomNormalWS = normalize(mul(cross(p1 - p0, p2 - p0), (float3x3)WorldToObject3x4()));
}




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

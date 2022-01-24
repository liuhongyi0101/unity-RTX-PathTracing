#ifndef UNITY_PATH_TRACING_MATERIAL_INCLUDED
#define UNITY_PATH_TRACING_MATERIAL_INCLUDED

#define BSDF_WEIGHT_EPSILON 0.001

struct FragInputs
{
    // Contain value return by SV_POSITION (That is name positionCS in PackedVarying).
    // xy: unormalized screen position (offset by 0.5), z: device depth, w: depth in view space
    // Note: SV_POSITION is the result of the clip space position provide to the vertex shaders that is transform by the viewport
    float4 positionSS; // In case depth offset is use, positionRWS.w is equal to depth offset
    float3 positionRWS; // Relative camera space position
    float4 texCoord0;
    float4 texCoord1;
    float4 texCoord2;
    float4 texCoord3;
    float4 color; // vertex color

    // TODO: confirm with Morten following statement
    // Our TBN is orthogonal but is maybe not orthonormal in order to be compliant with external bakers (Like xnormal that use mikktspace).
    // (xnormal for example take into account the interpolation when baking the normal and normalizing the tangent basis could cause distortion).
    // When using tangentToWorld with surface gradient, it doesn't normalize the tangent/bitangent vector (We instead use exact same scale as applied to interpolated vertex normal to avoid breaking compliance).
    // this mean that any usage of tangentToWorld[1] or tangentToWorld[2] outside of the context of normal map (like for POM) must normalize the TBN (TCHECK if this make any difference ?)
    // When not using surface gradient, each vector of tangentToWorld are normalize (TODO: Maybe they should not even in case of no surface gradient ? Ask Morten)
    float3x3 tangentToWorld;

    uint primitiveID; // Only with fullscreen pass debug currently - not supported on all platforms

    // For two sided lighting
    bool isFrontFace;
};

struct BuiltinData
{
    real opacity;
    real alphaClipTreshold;
    real3 bakeDiffuseLighting;
    real3 backBakeDiffuseLighting;
    real shadowMask0;
    real shadowMask1;
    real shadowMask2;
    real shadowMask3;
    real3 emissiveColor;
    real2 motionVector;
    real2 distortion;
    real distortionBlur;
    uint renderingLayers;
    float depthOffset;
    real4 vtPackedFeedback;
};
// Generated from UnityEngine.Rendering.HighDefinition.Lit+BSDFData
// PackingRules = Exact
struct SurfaceData
{
    uint materialFeatures;
    real3 baseColor;
    real specularOcclusion;
    float3 normalWS;
    real perceptualSmoothness;
    real ambientOcclusion;
    real metallic;
    real coatMask;
    real3 specularColor;
    uint diffusionProfileHash;
    real subsurfaceMask;
    real thickness;
    float3 tangentWS;
    real anisotropy;
    real iridescenceThickness;
    real iridescenceMask;
    real3 geomNormalWS;
    real ior;
    real3 transmittanceColor;
    real atDistance;
    real transmittanceMask;
};

struct BSDFData
{
    uint materialFeatures;
    real3 diffuseColor;
    real3 fresnel0;
    real ambientOcclusion;
    real specularOcclusion;
    float3 normalWS;
    real perceptualRoughness;
    real coatMask;
    uint diffusionProfileIndex;
    real subsurfaceMask;
    real thickness;
    bool useThickObjectMode;
    real3 transmittance;
    float3 tangentWS;
    float3 bitangentWS;
    real roughnessT;
    real roughnessB;
    real anisotropy;
    real iridescenceThickness;
    real iridescenceMask;
    real coatRoughness;
    real3 geomNormalWS;
    real ior;
    real3 absorptionCoefficient;
    real transmittanceMask;
};

struct BSDFDataMini
{
    real3 diffuseColor;
    real3 fresnel0;
    real coatMask;
    real roughnessT;
    real roughnessB;
    real ior;
    float3 normalWS;
    float3 V;
    real perceptualRoughness;
    real3 geomNormalWS;
    float4   bsdfWeight;
    float transmittanceMask;
    //// Subsurface scattering
    bool     isSubsurface;
    float    subsurfaceWeightFactor;
    real subsurfaceMask;
    real thickness;
};
struct MaterialData
{
    // BSDFs (4 max)
    BSDFData bsdfData;
    float3   V;
    //float4   bsdfWeight;

    //// Subsurface scattering
    //bool     isSubsurface;
    //float    subsurfaceWeightFactor;

    // View vector
   
};

struct MaterialResult
{
    float3 diffValue;
    float  diffPdf;
    float3 specValue;
    float  specPdf;
};

void Init(inout MaterialResult result)
{
    result.diffValue = 0.0;
    result.diffPdf = 0.0;
    result.specValue = 0.0;
    result.specPdf = 0.0;
}

void InitDiffuse(inout MaterialResult result)
{
    result.diffValue = 0.0;
    result.diffPdf = 0.0;
}

void InitSpecular(inout MaterialResult result)
{
    result.specValue = 0.0;
    result.specPdf = 0.0;
}

bool IsAbove(float3 normalWS, float3 dirWS)
{
    return dot(normalWS, dirWS) >= 0.0;
}

bool IsAbove(BSDFDataMini bsdfData, float3 dirWS)
{
    return IsAbove(bsdfData.geomNormalWS, dirWS);
}

bool IsAbove(BSDFDataMini bsdfData)
{
    return IsAbove(bsdfData.geomNormalWS, bsdfData.V);
}

bool IsBelow(float3 normalWS, float3 dirWS)
{
    return !IsAbove(normalWS, dirWS);
}

bool IsBelow(BSDFDataMini bsdfData, float3 dirWS)
{
    return !IsAbove(bsdfData, dirWS);
}

bool IsBelow(BSDFDataMini bsdfData)
{
    return !IsAbove(bsdfData);
}

float3x3 GetTangentFrame(BSDFDataMini bsdfData)
{
    //return bsdfData.anisotropy != 0.0 ?
    //    float3x3(bsdfData.tangentWS, bsdfData.bitangentWS, bsdfData.normalWS) :
    //    GetLocalFrame(bsdfData.normalWS);
    return GetLocalFrame(bsdfData.normalWS);
}

#endif // UNITY_PATH_TRACING_MATERIAL_INCLUDED

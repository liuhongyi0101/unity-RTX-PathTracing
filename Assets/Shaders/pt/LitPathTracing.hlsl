#include "PathTracingIntersection.hlsl"
#include "PathTracingMaterial.hlsl"
#include "PathTracingBSDF.hlsl"

// Lit Material Data:
//
// bsdfWeight0  Diffuse BRDF
// bsdfWeight1  Coat GGX BRDF
// bsdfWeight2  Spec GGX BRDF
// bsdfWeight3  Spec GGX BTDF

void ProcessBSDFData(PathIntersection pathIntersection, BuiltinData builtinData, inout BSDFDataMini bsdfData)
{
    // Adjust roughness to reduce fireflies
   // bsdfData.roughnessT = max(pathIntersection.maxRoughness, bsdfData.roughnessT);
   // bsdfData.roughnessB = max(pathIntersection.maxRoughness, bsdfData.roughnessB);

//    float NdotV = abs(dot(bsdfData.normalWS, WorldRayDirection()));
//
//    // Modify fresnel0 value to take iridescence into account (code adapted from Lit.hlsl to produce identical results)
//    if (bsdfData.iridescenceMask > 0.0)
//    {
//        float topIOR = lerp(1.0, CLEAR_COAT_IOR, bsdfData.coatMask);
//        float viewAngle = sqrt(1.0 + (Sq(NdotV) - 1.0) / Sq(topIOR));
//
//        bsdfData.fresnel0 = lerp(bsdfData.fresnel0, EvalIridescence(topIOR, viewAngle, bsdfData.iridescenceThickness, bsdfData.fresnel0), bsdfData.iridescenceMask);
//    }
//
//    // We store an energy compensation coefficient for GGX into the specular occlusion (code adapted from Lit.hlsl to produce identical results)
//#ifdef LIT_USE_GGX_ENERGY_COMPENSATION
//    float roughness = 0.5 * (bsdfData.roughnessT + bsdfData.roughnessB);
//    float2 coordLUT = Remap01ToHalfTexelCoord(float2(sqrt(NdotV), roughness), FGDTEXTURE_RESOLUTION);
//    float E = SAMPLE_TEXTURE2D_LOD(_PreIntegratedFGD_GGXDisneyDiffuse, s_linear_clamp_sampler, coordLUT, 0).y;
//    bsdfData.specularOcclusion = (1.0 - E) / E;
//#else
//    bsdfData.specularOcclusion = 0.0;
//#endif
//
//#if defined(_SURFACE_TYPE_TRANSPARENT) && !HAS_REFRACTION
//    // Turn alpha blending into proper refraction
//    bsdfData.transmittanceMask = 1.0 - builtinData.opacity;
//    bsdfData.ior = 1.0;
//#endif
}

bool CreateMaterialData(PathIntersection pathIntersection, BuiltinData builtinData, inout BSDFDataMini bsdfData, inout float3 shadingPosition, inout float theSample)
{
   
    ProcessBSDFData(pathIntersection, builtinData, bsdfData);
    // Assume no coating by default
    float coatingTransmission = 1.0;

    // First determine if our incoming direction V is above (exterior) or below (interior) the surface
    if (IsAbove(bsdfData.geomNormalWS, bsdfData.V))
    {
        float NdotV = dot(bsdfData.normalWS, bsdfData.V);
        float Fcoat = F_Schlick(CLEAR_COAT_F0, NdotV) * bsdfData.coatMask;
        float Fspec = Luminance(F_Schlick(bsdfData.fresnel0, NdotV));

        // If N.V < 0 (can happen with normal mapping) we want to avoid spec sampling
        bool consistentNormal = (NdotV > 0.001);
        bsdfData.bsdfWeight[1] = consistentNormal ? Fcoat : 0.0;
        coatingTransmission = 1.0 - bsdfData.bsdfWeight[1];
        bsdfData.bsdfWeight[2] = consistentNormal ? coatingTransmission * lerp(Fspec, 0.5, 0.5 * (bsdfData.roughnessT + bsdfData.roughnessB)) * (1.0 /*+ Fspec * mtlData.bsdfData.specularOcclusion*/) : 0.0;
        bsdfData.bsdfWeight[3] = consistentNormal ? (coatingTransmission - bsdfData.bsdfWeight[2]) * bsdfData.transmittanceMask : 0.0;
        bsdfData.bsdfWeight[0] = coatingTransmission * (1.0 - bsdfData.transmittanceMask) * Luminance(bsdfData.diffuseColor) ;
    }

#ifdef SURFACE_TYPE_TRANSPARENT
    else // Below
    {
        float NdotV = -dot(bsdfData.normalWS, bsdfData.V);
        float F = F_FresnelDielectric(1.0 / bsdfData.ior, NdotV);

        // If N.V < 0 (can happen with normal mapping) we want to avoid spec sampling
        bool consistentNormal = (NdotV > 0.001);
        bsdfData.bsdfWeight[0] = 0.0;
        bsdfData.bsdfWeight[1] = 0.0;
        bsdfData.bsdfWeight[2] = consistentNormal ? F : 0.0;
        bsdfData.bsdfWeight[3] = consistentNormal ? (1.0 - bsdfData.bsdfWeight[1]) * bsdfData.transmittanceMask : 0.0;
    }
#endif

    // Normalize the weights
    float wSum = bsdfData.bsdfWeight[0] + bsdfData.bsdfWeight[1] + bsdfData.bsdfWeight[2] + bsdfData.bsdfWeight[3];

    if (wSum < BSDF_WEIGHT_EPSILON)
        return false;

    bsdfData.bsdfWeight /= wSum;


#ifdef SUBSURFACE
    float subsurfaceWeight = bsdfData.bsdfWeight[0] * bsdfData.subsurfaceMask /** (1.0 - pathIntersection.maxRoughness)*/;
   
    bsdfData.isSubsurface = theSample < subsurfaceWeight;
    if (bsdfData.isSubsurface)
    {
        // We do a full, ray-traced subsurface scattering computation here:
        // Let's try and change shading position and normal, and replace the diffuse color by the subsurface throughput
        bsdfData.subsurfaceWeightFactor = subsurfaceWeight;

        SSS::Result subsurfaceResult;
        float3 meanFreePath = 0.001 / (_ShapeParamsAndMaxScatterDists.rgb * _worldScaleAndFilterRadiusAndThicknessRemap.x);

        if (!SSS::RandomWalk(shadingPosition, bsdfData.normalWS, bsdfData.diffuseColor, meanFreePath, pathIntersection.pixelCoord, subsurfaceResult))
            return false;

        shadingPosition = subsurfaceResult.exitPosition;
        bsdfData.normalWS = subsurfaceResult.exitNormal;
        bsdfData.geomNormalWS = subsurfaceResult.exitNormal;
        bsdfData.diffuseColor = subsurfaceResult.throughput * coatingTransmission;
       // bsdfData.diffuseColor = float3(15.0,0.0,0.0);

    }
    else
    {
        // Otherwise, we just compute BSDFs as usual
        bsdfData.subsurfaceWeightFactor = 1.0 - subsurfaceWeight;

        bsdfData.bsdfWeight[0] = max(bsdfData.bsdfWeight[0] - subsurfaceWeight, BSDF_WEIGHT_EPSILON);
        bsdfData.bsdfWeight /= bsdfData.subsurfaceWeightFactor;

        theSample -= subsurfaceWeight;
       // bsdfData.diffuseColor = float3(1.0, 1.0, 0.0);
    }

    // Rescale the sample we used for the SSS selection test
    theSample /= bsdfData.subsurfaceWeightFactor;
#endif
    return true;
}

// Little helper to get the specular compensation term
float3 GetSpecularCompensation(BSDFDataMini bsdfData)
{
    return 1.0 + 1.0 * bsdfData.fresnel0;
}

bool SampleMaterial(BSDFDataMini bsdfData,float3 inputSample, out float3 sampleDir, out MaterialResult result)
{
    Init(result);
    
#ifdef SUBSURFACE
    if (bsdfData.isSubsurface)
    {
        if (!BRDF::SampleLambert(bsdfData, inputSample, sampleDir, result.diffValue, result.diffPdf))
            return false;

        result.diffValue *= (1.0 - bsdfData.transmittanceMask);

        return true;
    }
#endif

    if (IsAbove(bsdfData))
    {
        float3 value;
        float  pdf;
        float  fresnelSpec, fresnelClearCoat = 0.0;

        if (inputSample.z < bsdfData.bsdfWeight.x) // Diffuse BRDF
        {
            if (!BRDF::SampleDiffuse(bsdfData, inputSample, sampleDir, result.diffValue, result.diffPdf))
                return false;

           result.diffPdf *= 1.0;

            if (bsdfData.bsdfWeight.y > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateGGX(bsdfData, CLEAR_COAT_ROUGHNESS, CLEAR_COAT_F0, sampleDir, value, pdf, fresnelClearCoat);
                fresnelClearCoat *= 1.0;
                result.specValue += value * 1.0;
                result.specPdf += 1.0 * pdf;
            }

            result.diffValue *= 1.0;

            if (bsdfData.bsdfWeight.z > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateAnisoGGX(bsdfData, bsdfData.fresnel0, sampleDir, value, pdf, fresnelSpec);
                result.specValue += value * (1.0 - fresnelClearCoat) * GetSpecularCompensation(bsdfData);
                result.specPdf += bsdfData.bsdfWeight.z * pdf;
            }
        }     
        else if (inputSample.z < bsdfData.bsdfWeight[0] + bsdfData.bsdfWeight[1]) // Clear coat BRDF
        {
            if (!BRDF::SampleGGX(bsdfData, CLEAR_COAT_ROUGHNESS, CLEAR_COAT_F0, inputSample, sampleDir, result.specValue, result.specPdf, fresnelClearCoat))
                return false;

            fresnelClearCoat *= bsdfData.coatMask;
            result.specValue *= bsdfData.coatMask;
            result.specPdf *= bsdfData.bsdfWeight[1];

            if (bsdfData.bsdfWeight[0] > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateDiffuse(bsdfData, sampleDir, result.diffValue, result.diffPdf);
                result.diffValue *= /* mtlData.bsdfData.ambientOcclusion*/ (1.0 - bsdfData.transmittanceMask) * (1.0 - fresnelClearCoat);
                result.diffPdf *= bsdfData.bsdfWeight[0];
            }

            if (bsdfData.bsdfWeight[2] > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateAnisoGGX(bsdfData, bsdfData.fresnel0, sampleDir, value, pdf, fresnelSpec);
                result.specValue += value * (1.0 - fresnelClearCoat) * GetSpecularCompensation(bsdfData);
                result.specPdf += bsdfData.bsdfWeight[2] * pdf;
            }
        }
        else if (inputSample.z < bsdfData.bsdfWeight[0] + bsdfData.bsdfWeight[1] + bsdfData.bsdfWeight[2]) // Specular BRDF
        {
            if (!BRDF::SampleAnisoGGX(bsdfData, bsdfData.fresnel0, inputSample, sampleDir, result.specValue, result.specPdf, fresnelSpec))
                return false;

            result.specValue *= GetSpecularCompensation(bsdfData);
            result.specPdf *= bsdfData.bsdfWeight[2];

            if (bsdfData.bsdfWeight[1] > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateGGX(bsdfData, CLEAR_COAT_ROUGHNESS, CLEAR_COAT_F0, sampleDir, value, pdf, fresnelClearCoat);
                fresnelClearCoat *= bsdfData.coatMask;
                result.specValue = result.specValue * (1.0 - fresnelClearCoat) + value * bsdfData.coatMask;
                result.specPdf += bsdfData.bsdfWeight[1] * pdf;
            }

            if (bsdfData.bsdfWeight[0] > BSDF_WEIGHT_EPSILON)
            {
                BRDF::EvaluateDiffuse(bsdfData, sampleDir, result.diffValue, result.diffPdf);
                result.diffValue *=/* mtlData.bsdfData.ambientOcclusion*/ (1.0 - bsdfData.transmittanceMask) * (1.0 - fresnelClearCoat);
                //result.diffValue *= float3(1.0, 0.0, 0.0)*10.;
                result.diffPdf *= bsdfData.bsdfWeight[0];
            }
        }
#ifdef SURFACE_TYPE_TRANSPARENT
        else // Specular BTDF
        {
            if (!BTDF::SampleAnisoGGX(bsdfData, inputSample, sampleDir, result.specValue, result.specPdf))
                return false;

#ifdef REFRACTION_THIN
            sampleDir = refract(sampleDir, bsdfData.normalWS, 1.0/bsdfData.ior);
            if (!any(sampleDir))
                return false;
#endif

            result.specValue *= bsdfData.transmittanceMask;
            result.specPdf *= bsdfData.bsdfWeight[3];
        }
#endif


#ifdef SUBSURFACE
        // We compensate for the fact that there is no spec when computing SSS
        result.specValue /= bsdfData.subsurfaceWeightFactor;
#endif
    }
    else // Below
    {
#ifdef SURFACE_TYPE_TRANSPARENT

    bsdfData.normalWS = -bsdfData.normalWS;
    BTDF::SampleAnisoGGX(bsdfData, inputSample, sampleDir, result.specValue, result.specPdf);

#ifdef REFRACTION_THIN
    if (bsdfData.transmittanceMask)
    {
        // Just go through (although we should not end up here)
        sampleDir = -bsdfData.V;
        result.specValue = DELTA_PDF;
        result.specPdf = DELTA_PDF;
    }
   
    sampleDir = refract(sampleDir, bsdfData.normalWS, bsdfData.ior);
#else
    //bsdfData.normalWS = -bsdfData.normalWS;
    //sampleDir = refract(sampleDir, bsdfData.normalWS, bsdfData.ior);

    if (inputSample.z < bsdfData.bsdfWeight[2]) // Specular BRDF
    {
        if (!BRDF::SampleDelta(bsdfData, sampleDir, result.specValue, result.specPdf))
            return false;

        result.specPdf *= bsdfData.bsdfWeight[2];
    }
    else // Specular BTDF
    {
        if (!BTDF::SampleDelta(bsdfData, sampleDir, result.specValue, result.specPdf))
            return false;

        result.specPdf *= bsdfData.bsdfWeight[3];
    }
#endif
#else
    return false;
#endif
    }

    return true;
}

void EvaluateMaterial(BSDFDataMini bsdfData, float3 sampleDir, out MaterialResult result)
{
    Init(result);

#ifdef SUBSURFACE
    if (bsdfData.isSubsurface)
    {
        BRDF::EvaluateLambert(bsdfData, sampleDir, result.diffValue, result.diffPdf);
        result.diffValue *= 1.0 - bsdfData.transmittanceMask; // AO purposedly ignored here

        return;
    }
#endif

    if (IsAbove(bsdfData))
    {
        float3 value;
        float pdf;
        float fresnelSpec, fresnelClearCoat = 0.0;

        if (bsdfData.bsdfWeight[1] > BSDF_WEIGHT_EPSILON)
        {
            BRDF::EvaluateGGX(bsdfData, CLEAR_COAT_ROUGHNESS, CLEAR_COAT_F0, sampleDir, result.specValue, result.specPdf, fresnelClearCoat);
            fresnelClearCoat *= bsdfData.coatMask;
            result.specValue *= bsdfData.coatMask;
            result.specPdf *= bsdfData.bsdfWeight[1];
        }

        if (bsdfData.bsdfWeight[0] > BSDF_WEIGHT_EPSILON)
        {
            BRDF::EvaluateDiffuse(bsdfData, sampleDir, result.diffValue, result.diffPdf);
            result.diffValue *= (1.0 - bsdfData.transmittanceMask) * (1.0 - fresnelClearCoat);
            result.diffPdf *= 1.0;
        }

        if (bsdfData.bsdfWeight[2] > BSDF_WEIGHT_EPSILON)
        {
            BRDF::EvaluateAnisoGGX(bsdfData, bsdfData.fresnel0, sampleDir, value, pdf, fresnelSpec);
            result.specValue += value * (1.0 - fresnelClearCoat) * GetSpecularCompensation(bsdfData);
           
            result.specPdf += bsdfData.bsdfWeight[2]* pdf;
        }

#ifdef SUBSURFACE
        // We compensate for the fact that there is no spec when computing SSS
        result.specValue /= bsdfData.subsurfaceWeightFactor;
#endif
    }
}

float AdjustPathRoughness(BSDFDataMini bsdfData, MaterialResult mtlResult, bool isSampleBelow, float pathRoughness)
{
    // Adjust the max roughness, based on the estimated diff/spec ratio
    float adjustedPathRoughness = (mtlResult.specPdf * max(bsdfData.roughnessT, bsdfData.roughnessB) + mtlResult.diffPdf) / (mtlResult.diffPdf + mtlResult.specPdf);
    
#ifdef SURFACE_TYPE_TRANSPARENT
    // When transmitting with an IOR close to 1.0, roughness is barely noticeable -> take that into account for path roughness adjustment
    if (IsBelow(bsdfData) != isSampleBelow)
        adjustedPathRoughness = lerp(pathRoughness, adjustedPathRoughness, smoothstep(1.0, 1.3, bsdfData.ior));
#endif

    return adjustedPathRoughness;
}

float3 ApplyAbsorption(BSDFDataMini bsdfData, float dist, bool isSampleBelow, float3 value)
{
#if defined(SURFACE_TYPE_TRANSPARENT) && HAS_REFRACTION
    // Apply absorption on rays below the interface, using Beer-Lambert's law
    if (isSampleBelow)
    {
    #ifdef REFRACTION_THIN
        value *= exp(-bsdfData.absorptionCoefficient /** REFRACTION_THIN_DISTANCE*/);
    #else
        value *= exp(-bsdfData.absorptionCoefficient * dist);
    #endif
    }
#endif

    return value;
}

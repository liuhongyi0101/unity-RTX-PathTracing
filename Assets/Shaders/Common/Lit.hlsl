#define REFRACTION_THIN_DISTANCE 0.005

void FillMaterialTransparencyData(float3 baseColor, float metallic, float ior, float3 transmittanceColor, float atDistance, float thickness, float transmittanceMask, inout BSDFDataMini bsdfData)
{
    // Uses thickness from SSS's property set
    bsdfData.ior = ior;

    // IOR define the fresnel0 value, so update it also for consistency (and even if not physical we still need to take into account any metal mask)
    bsdfData.fresnel0 = lerp(IorToFresnel0(ior).xxx, baseColor, metallic);

    //bsdfData.absorptionCoefficient = TransmittanceColorAtDistanceToAbsorption(transmittanceColor, atDistance);
    bsdfData.transmittanceMask = transmittanceMask;
    bsdfData.thickness = max(thickness, 0.0001);
}

BSDFDataMini ConvertSurfaceDataToBSDFData(uint2 positionSS)
{
   
    BSDFDataMini bsdfData;
    ZERO_INITIALIZE(BSDFDataMini, bsdfData);

    // IMPORTANT: In case of foward or gbuffer pass all enable flags are statically know at compile time, so the compiler can do compile time optimization
    //bsdfData.materialFeatures = surfaceData.materialFeatures;
    // Standard material
    //bsdfData.ambientOcclusion = surfaceData.ambientOcclusion;
    //bsdfData.specularOcclusion = surfaceData.specularOcclusion;

    bsdfData.diffuseColor = ComputeDiffuseColor(_Color.rgb, _Metallic);

    bsdfData.V = -WorldRayDirection();
    bsdfData.perceptualRoughness = 1 - _Smoothness;

    bsdfData.bsdfWeight = 0.0;
    bsdfData.fresnel0 = ComputeFresnel0(_Color.rgb, _Metallic, DEFAULT_SPECULAR_VALUE);
    bsdfData.coatMask = _CoatMask;
    bsdfData.ior = _IOR;
    bsdfData.transmittanceMask = _TransmittanceMask;
    ConvertAnisotropyToRoughness(bsdfData.perceptualRoughness, 0.0, bsdfData.roughnessT, bsdfData.roughnessB);

    bsdfData.isSubsurface = 0.0;
    bsdfData.subsurfaceWeightFactor = 1.0;
    bsdfData.subsurfaceMask = 1.0;
    bsdfData.thickness = 0.1;

 
    // There is no metallic with SSS and specular color mode
   // float metallic = HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SPECULAR_COLOR | MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING | MATERIALFEATUREFLAGS_LIT_TRANSMISSION) ? 0.0 : surfaceData.metallic;

   // bsdfData.fresnel0 = HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SPECULAR_COLOR) ? surfaceData.specularColor : ComputeFresnel0(surfaceData.baseColor, surfaceData.metallic, DEFAULT_SPECULAR_VALUE);

    // Note: we have ZERO_INITIALIZE the struct so bsdfData.anisotropy == 0.0
    // Note: DIFFUSION_PROFILE_NEUTRAL_ID is 0

    // In forward everything is statically know and we could theorically cumulate all the material features. So the code reflect it.
    // However in practice we keep parity between deferred and forward, so we should constrain the various features.
    // The UI is in charge of setuping the constrain, not the code. So if users is forward only and want unleash power, it is easy to unleash by some UI change

//    bsdfData.diffusionProfileIndex = FindDiffusionProfileIndex(surfaceData.diffusionProfileHash);

    //if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_SUBSURFACE_SCATTERING))
    //{
    //    // Assign profile id and overwrite fresnel0
    //    FillMaterialSSS(bsdfData.diffusionProfileIndex, surfaceData.subsurfaceMask, bsdfData);
    //}

    //if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_TRANSMISSION))
    //{
    //    // Assign profile id and overwrite fresnel0
    //    FillMaterialTransmission(bsdfData.diffusionProfileIndex, surfaceData.thickness, bsdfData);
    //}

    //if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_ANISOTROPY))
    //{
    //    FillMaterialAnisotropy(surfaceData.anisotropy, surfaceData.tangentWS, cross(surfaceData.normalWS, surfaceData.tangentWS), bsdfData);
    //}

    //if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_IRIDESCENCE))
    //{
    //    FillMaterialIridescence(surfaceData.iridescenceMask, surfaceData.iridescenceThickness, bsdfData);
    //}

    //if (HasFlag(surfaceData.materialFeatures, MATERIALFEATUREFLAGS_LIT_CLEAR_COAT))
    //{
    //    // Modify perceptualRoughness
    //    FillMaterialClearCoatData(surfaceData.coatMask, bsdfData);
    //}


   // Note: Reuse thickness of transmission's property set
   
#ifdef REFRACTION_THIN
        // We set both atDistance and thickness to the same, small value
    FillMaterialTransparencyData(_Color.rgb, _Metallic, _IOR, _TransmittanceColor, REFRACTION_THIN_DISTANCE, REFRACTION_THIN_DISTANCE, _TransmittanceMask, bsdfData);

#endif

    return bsdfData;
}


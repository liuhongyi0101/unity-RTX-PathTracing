#define RAY_TRACING_OPTIONAL_PARAMETERS , IntersectionVertex intersectionVertex, RayCone rayCone, out bool alphaTestResult
//Material\Decal\DecalData.hlsl
void GetSurfaceAndBuiltinData(FragInputs input, float3 V, inout PositionInputs posInput, 
    out SurfaceData surfaceData, out BuiltinData builtinData RAY_TRACING_OPTIONAL_PARAMETERS)
{


    float3 normalTS;
    float3 bentNormalTS;
    float3 bentNormalWS;
    //float alpha = GetSurfaceData(input, layerTexCoord, surfaceData, normalTS, bentNormalTS);

    //float3 normalWS = SafeNormalize(TransformTangentToWorld(normalTS, input.tangentToWorld));
    //GetNormalWS(input, normalTS, surfaceData.normalWS, doubleSidedConstants);

    //surfaceData.geomNormalWS = input.tangentToWorld[2];

   // surfaceData.specularOcclusion = 1.0; // This need to be init here to quiet the compiler in case of decal, but can be override later.

    //surfaceData.tangentWS = Orthonormalize(surfaceData.tangentWS, surfaceData.normalWS);

    //GetBuiltinData(input, V, posInput, surfaceData, alpha, bentNormalWS, depthOffset, layerTexCoord.base, builtinData);
   // alphaTestResult = true;
}


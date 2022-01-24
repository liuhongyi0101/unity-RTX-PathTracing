real GetOddNegativeScale()
{
    // FIXME: We should be able to just return unity_WorldTransformParams.w, but it is not
    // properly set at the moment, when doing ray-tracing; once this has been fixed in cpp,
    // we can revert back to the former implementation.
    return  1.0 ;
}


real3x3 CreateTangentToWorld(real3 normal, real3 tangent, real flipSign)
{
    // For odd-negative scale transforms we need to flip the sign
    real sgn = flipSign * GetOddNegativeScale();
    real3 bitangent = cross(normal, tangent) * sgn;

    return real3x3(tangent, bitangent, normal);
}
// FIXME: Should probably be renamed as we don't need rayIntersection as input anymore (neither do we need incidentDirection)
void BuildFragInputsFromIntersection(IntersectionVertex currentVertex, float3 incidentDirection, out FragInputs outFragInputs)
{
    outFragInputs.positionSS = float4(0.0, 0.0, 0.0, 0.0);
    outFragInputs.positionRWS = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
    outFragInputs.texCoord0 = currentVertex.texCoord0;
    outFragInputs.texCoord1 = currentVertex.texCoord1;
    outFragInputs.texCoord2 = currentVertex.texCoord2;
    outFragInputs.texCoord3 = currentVertex.texCoord3;
    outFragInputs.color = currentVertex.color;

    float3 normalWS = normalize(mul(currentVertex.normalOS, (float3x3)WorldToObject3x4()));
    float3 tangentWS = normalize(mul(currentVertex.tangentOS.xyz, (float3x3)WorldToObject3x4()));
    outFragInputs.tangentToWorld = CreateTangentToWorld(normalWS, tangentWS, sign(currentVertex.tangentOS.w));

    outFragInputs.isFrontFace = dot(incidentDirection, outFragInputs.tangentToWorld[2]) < 0.0f;
}

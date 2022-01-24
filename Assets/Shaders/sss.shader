Shader "Tutorial/sss"
{
  Properties
  {
    _Color ("Main Color", Color) = (1,1,1,1)
    _IOR ("IOR", float) = 1.5
          _Smoothness("Smoothness", float) = 0
    _Metallic("Metallic", float) = 0
  }
  SubShader
  {
    Tags { "RenderType"="Opaque" }
    LOD 100

    Pass
    {
      CGPROGRAM
      #pragma vertex vert
      #pragma fragment frag
      // make fog work
      #pragma multi_compile_fog

      #include "UnityCG.cginc"

      struct appdata
      {
        float4 vertex : POSITION;
        float3 normal : NORMAL;
      };

      struct v2f
      {
        float3 normal : TEXCOORD0;
        UNITY_FOG_COORDS(1)
        float4 vertex : SV_POSITION;
      };

      CBUFFER_START(UnityPerMaterial)
      half4 _Color;
      CBUFFER_END

      v2f vert (appdata v)
      {
        v2f o;
        o.vertex = UnityObjectToClipPos(v.vertex);
        o.normal = UnityObjectToWorldNormal(v.normal);
        UNITY_TRANSFER_FOG(o, o.vertex);
        return o;
      }

      half4 frag (v2f i) : SV_Target
      {
        half4 col = _Color * half4(dot(i.normal, float3(0.0f, 1.0f, 0.0f)).xxx, 1.0f);
        // apply fog
        UNITY_APPLY_FOG(i.fogCoord, col);
        return col;
      }
      ENDCG
    }
  }

  SubShader
  {
    Pass
    {
      Name "RayTracing"
      Tags { "LightMode" = "RayTracing" }

      HLSLPROGRAM
       #define ATTRIBUTES_NEED_TEXCOORD0  
      #pragma raytracing test

      #include "./Common.hlsl"
      #include "./PRNG.hlsl"
      #include "./ONB.hlsl" 
      #include  "./Sampling.hlsl"
      #include  "./SubSurface.hlsl"

      //struct IntersectionVertex
      //{
      //  // Object space normal of the vertex
      //  float3 normalOS;
      //};

      CBUFFER_START(UnityPerMaterial)
      float4 _Color;
      float4 _ShapeParamsAndMaxScatterDists;
      float4 _worldScaleAndFilterRadiusAndThicknessRemap;
      float4 _transmissionTintAndFresnel0;
      float4 _disabledTransmissionTintAndFresnel0;
      float _Smoothness;
      float _Metallic;
      float _IOR;
 
      CBUFFER_END

      //void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
      //{
      //  outVertex.normalOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
      //}

      inline float schlick(float cosine, float IOR)
      {
        float r0 = (1.0f - IOR) / (1.0f + IOR);
        r0 = r0 * r0;
        return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
      }

      [shader("closesthit")]
      void ClosestHitShader(inout RayIntersection rayIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
      {
        // Fetch the indices of the currentr triangle

              // If the max depth has been reached, bail out
          if (!rayIntersection.remainingDepth)
          {
              rayIntersection.color = 0.0;
              return;
          }

        uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

        // Fetch the 3 vertices
        IntersectionVertex v0, v1, v2;
        FetchIntersectionVertex(triangleIndices.x, v0);
        FetchIntersectionVertex(triangleIndices.y, v1);
        FetchIntersectionVertex(triangleIndices.z, v2);

        // Compute the full barycentric coordinates
        float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

        // Get normal in world space.
        float3 normalOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates);
        float2 texCoord0 = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
        float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
        float3 normalWS = normalize(mul(objectToWorld, normalOS));
        // Make reflection ray.
        ONB uvw;
        ONBBuildFromW(uvw, normalWS);
        float4 color = float4(0, 0, 0, 1);

        // X = meters per world unit, Y = filter radius (in mm), Z = remap start, W = end - start
        //worldScaleAndFilterRadiusAndThicknessRemap.x
        // RGB = S = 1 / D, A = d = RgbMax(D)
        // _ShapeParamsAndMaxScatterDists.rgb

        float3 meanFreePath = 0.001 / (_ShapeParamsAndMaxScatterDists.rgb * _worldScaleAndFilterRadiusAndThicknessRemap.x);
        //remainingDepth 剩余
        //RandomWalk(float3 position, float3 normal, inout uint4 states, float3 diffuseColor, float3 meanFreePath, uint2 pixelCoord, out Result result)

        float3 diffuseColor = _Color.rgb;
       // if (rayIntersection.remainingDepth > 0)
        {
          // Get position in world space.
          float3 origin = WorldRayOrigin();
          float3 direction = WorldRayDirection();
          float t = RayTCurrent();
          float3 positionWS = origin + direction * t;

          //if (!SSS::RandomWalk(shadingPosition, mtlData.bsdfData.normalWS, mtlData.bsdfData.diffuseColor, meanFreePath, pathIntersection.pixelCoord, subsurfaceResult))
          //    return false;

          //shadingPosition = subsurfaceResult.exitPosition;
          //mtlData.bsdfData.normalWS = subsurfaceResult.exitNormal;
          //mtlData.bsdfData.geomNormalWS = subsurfaceResult.exitNormal;
          //mtlData.bsdfData.diffuseColor = subsurfaceResult.throughput * coatingTransmission;

          Result result;

          bool res = RandomWalk(positionWS, normalWS, rayIntersection.PRNGStates, _Color.rgb, meanFreePath, texCoord0, result);
          if (!res) return;
           

          positionWS = result.exitPosition;
          normalWS = result.exitNormal;
          diffuseColor = result.throughput;
          // Make reflection & refraction ray.
          float3 outwardNormal;
          float niOverNt;
          float reflectProb;
          float cosine;
          float3 H  = brdfSampling(rayIntersection.PRNGStates, normalWS, -direction, _Metallic, _Smoothness);

         // if (dot(-direction, normalWS) > 0.0f)
         // {
         //   outwardNormal = normalWS;
         //   niOverNt = 1.0f / _IOR;
         //   cosine = _IOR * dot(-direction, normalWS);
         // }
         // else
         // {
         //   outwardNormal = -normalWS;
         //   niOverNt = _IOR;
         //   cosine = -dot(-direction, -normalWS);
         //   H = brdfSampling(rayIntersection.PRNGStates, -normalWS, -direction, _Metallic, _Smoothness);
         // }
         // reflectProb = schlick(cosine, _IOR);

         // float3 scatteredDir =  refract(direction, H, niOverNt);

         // bool all_reflect = length(scatteredDir) < 0.5;
         // 
         //// if (GetRandomValue(rayIntersection.PRNGStates) < reflectProb)
         // if (!all_reflect)
         //   scatteredDir = scatteredDir;
         // else
         //   scatteredDir = reflect(direction, H);

          RayDesc rayDescriptor;
          rayDescriptor.Origin = positionWS + 1e-5f * normalWS;
          rayDescriptor.Direction = ONBLocal(uvw, GetRandomCosineDirection(rayIntersection.PRNGStates));
          rayDescriptor.TMin = 1e-5f;
          rayDescriptor.TMax = _CameraFarDistance;

          // Tracing reflection.
          RayIntersection reflectionRayIntersection;
          reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
          reflectionRayIntersection.PRNGStates = rayIntersection.PRNGStates;
          reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);

          // Tracing shadow.
          RayIntersection shadowRayIntersection;
          shadowRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
          shadowRayIntersection.PRNGStates = rayIntersection.PRNGStates;
          shadowRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);
          shadowRayIntersection.shadow = true;

          RayDesc shaddowRayDescriptor;
          shaddowRayDescriptor.Origin = positionWS + 0.001f * normalWS;
          shaddowRayDescriptor.Direction = _Sundir.xyz;
          shaddowRayDescriptor.TMin = 1e-5f;
          shaddowRayDescriptor.TMax = _CameraFarDistance;

          // Tracing sun.

          TraceRay(_AccelerationStructure, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER, RAYTRACINGRENDERERFLAG_CAST_SHADOW, 1, 1, 0, shaddowRayDescriptor, shadowRayIntersection);

          rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
          if (!shadowRayIntersection.shadow)
          {
              color.rgb = max(0, dot(_Sundir.xyz, normalWS)) * diffuseColor * M_1_PI_F;
              reflectionRayIntersection.remainingDepth = 0;
          }





          TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 0, 1, 0, rayDescriptor, reflectionRayIntersection);

          rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
          color = reflectionRayIntersection.color;
        }

       rayIntersection.color = float4(diffuseColor.rgb * color.rgb,1.0);
        //rayIntersection.color = float4(diffuseColor.rgb, 1.0);
      }

      ENDHLSL
    }
  }
}

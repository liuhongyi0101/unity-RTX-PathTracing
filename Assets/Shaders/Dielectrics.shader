﻿Shader "Tutorial/Dielectrics"
{
  Properties
  {
    _Color ("Main Color", Color) = (1,1,1,1)
    _IOR ("IOR", float) = 1.5
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

      #pragma raytracing test

      #include "./Common.hlsl"
      #include "./PRNG.hlsl"

      //struct IntersectionVertex
      //{
      //  // Object space normal of the vertex
      //  float3 normalOS;
      //};

      CBUFFER_START(UnityPerMaterial)
      float4 _Color;
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
        float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
        float3 normalWS = normalize(mul(objectToWorld, normalOS));

        float4 color = float4(0, 0, 0, 1);
        if (rayIntersection.remainingDepth > 0)
        {
          // Get position in world space.
          float3 origin = WorldRayOrigin();
          float3 direction = WorldRayDirection();
          float t = RayTCurrent();
          float3 positionWS = origin + direction * t;

          // Make reflection & refraction ray.
          float3 outwardNormal;
          float niOverNt;
          float reflectProb;
          float cosine;
          if (dot(-direction, normalWS) > 0.0f)
          {
            outwardNormal = normalWS;
            niOverNt = 1.0f / _IOR;
            cosine = _IOR * dot(-direction, normalWS);
          }
          else
          {
            outwardNormal = -normalWS;
            niOverNt = _IOR;
            cosine = -dot(-direction, normalWS);
          }
          reflectProb = schlick(cosine, _IOR);

          float3 scatteredDir;
          if (GetRandomValue(rayIntersection.PRNGStates) < reflectProb)
            scatteredDir = reflect(direction, normalWS);
          else
            scatteredDir = refract(direction, outwardNormal, niOverNt);

          RayDesc rayDescriptor;
          rayDescriptor.Origin = positionWS + 1e-5f * scatteredDir;
          rayDescriptor.Direction = scatteredDir;
          rayDescriptor.TMin = 1e-5f;
          rayDescriptor.TMax = _CameraFarDistance;

          // Tracing reflection.
          RayIntersection reflectionRayIntersection;
          reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
          reflectionRayIntersection.PRNGStates = rayIntersection.PRNGStates;
          reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);

          TraceRay(_AccelerationStructure, RAY_FLAG_NONE, 0xFF, 0, 1, 0, rayDescriptor, reflectionRayIntersection);

          rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
          color = reflectionRayIntersection.color;
        }

        rayIntersection.color = _Color * color;
      }

      ENDHLSL
    }
  }
}


Shader "Tutorial/Metal"
{
  Properties
  {
    _Color ("Main Color", Color) = (1,1,1,1)
    _Fuzz ("Fuzz", float) = 0
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
      float4 _Sundir;
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
       #include "./ONB.hlsl" 
#include  "./Sampling.hlsl"
      //struct IntersectionVertex
      //{
      //  // Object space normal of the vertex
      //  float3 normalOS;
      //};

      CBUFFER_START(UnityPerMaterial)
      float4 _Color;
      float _Fuzz;
      float _Smoothness;
      float _Metallic;
      CBUFFER_END

      //void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex)
      //{
      //  outVertex.normalOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
      //}
 


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

          // Make reflection ray.
          ONB uvw;
          ONBBuildFromW(uvw, normalWS);
         float4 hpdf =  brdfSampling(rayIntersection.PRNGStates, normalWS, -direction, _Metallic, _Smoothness);
          // Make reflection ray.
          float3 reflectDir = reflect(direction, normalWS);
          reflectDir = reflect(direction, hpdf.xyz);
          //if (dot(reflectDir, normalWS) < 0.0f)
          //  reflectDir = direction;
          RayDesc rayDescriptor;
          rayDescriptor.Origin = positionWS + 0.0001f * normalWS;
    
          rayDescriptor.Direction = reflectDir;
          rayDescriptor.TMin = 1e-5f;
          rayDescriptor.TMax = _CameraFarDistance;


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




          // Tracing reflection.
          RayIntersection reflectionRayIntersection;
          reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
          reflectionRayIntersection.PRNGStates = rayIntersection.PRNGStates;
          reflectionRayIntersection.color = float4(0.0f, 0.0f, 0.0f, 0.0f);

          // Tracing sun.
          TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xFF, 1, 1, 0, shaddowRayDescriptor, shadowRayIntersection);
          float4  dircolor = 0;
          if (!shadowRayIntersection.shadow)
          {
              //dircolor = 5.0 * max(0, dot(_Sundir.xyz, normalWS)) * M_1_PI_F;
              dircolor.rgb = UE4Eval( _Sundir.xyz, -direction, normalWS.xyz, _Color.xyz, _Metallic, _Smoothness) * max(0, dot(_Sundir.xyz, normalWS));
              //reflectionRayIntersection.remainingDepth = rayIntersection.remainingDepth - 1;
          }


          TraceRay(_AccelerationStructure, RAY_FLAG_CULL_BACK_FACING_TRIANGLES, 0xff, 0, 1, 0, rayDescriptor, reflectionRayIntersection);

          float pdf = UE4Pdf(rayDescriptor.Direction, -direction, normalWS.xyz, _Metallic, 1-_Smoothness);
          rayIntersection.PRNGStates = reflectionRayIntersection.PRNGStates;
          color.rgb = reflectionRayIntersection.color* UE4Eval( rayDescriptor.Direction, -direction, normalWS.xyz, _Color.xyz, _Metallic, 1-_Smoothness).rgb* max(0, dot(rayDescriptor.Direction, normalWS))/pdf + dircolor.rgb;
          //color.rgb = reflectionRayIntersection.color+ dircolor.rgb;
        }

        rayIntersection.color =  color;
      }

      ENDHLSL
    }
  }
}

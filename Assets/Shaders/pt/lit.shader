Shader "Tutorial/Lit"
{
    Properties
    {
      _Color("Main Color", Color) = (1,1,1,1)
      _TransmittanceColor("Transmittance Color", Color) = (1,1,1,1)
      [HDR]_EmissionColor("Emission Color", Color) = (1,1,1,1)
      _IOR("IOR", float) = 1.5
      _Smoothness("Smoothness", float) = 0
      _Metallic("Metallic", float) = 0
      _CoatMask("coat Mask", float) = 0
      _Opacity("opacity", float) = 0
      _TransmittanceMask("transmittanceMask", float) = 0

       _NormalMap("NormalMap", 2D) = "bump" {}     // Tangent space normal map
       _BaseColorMap("BaseColorMap", 2D) = "white" {}
       [Toggle(SUBSURFACE)] _SUBSURFACE("SUBSURFACE", Float) = 0

       [Toggle(NORMALMAP)] _NORMALMAP("NORMALMAP", Float) = 0
       [Toggle(REFRACTION_THIN)] _REFRACTION_THIN("REFRACTION_THIN", Float) = 0
       [Toggle(LIGHTSOURCE)] _LIGHT_SOURCE("LIGHT SOURCE", Float) = 0
       [Toggle(SURFACE_TYPE_TRANSPARENT)] _SURFACE_TYPE_TRANSPARENT("SURFACE_TYPE_TRANSPARENT", Float) = 0
    
    }
        SubShader
    {
      Tags { "RenderType" = "Opaque" }
      LOD 100

      Pass
      {
        CGPROGRAM
        #pragma vertex vert
        #pragma fragment frag

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

        v2f vert(appdata v)
        {
          v2f o;
          o.vertex = UnityObjectToClipPos(v.vertex);
          o.normal = UnityObjectToWorldNormal(v.normal);
          UNITY_TRANSFER_FOG(o, o.vertex);
          return o;
        }

        half4 frag(v2f i) : SV_Target
        {
          half4 col = _Color * half4(dot(float3(1.0,0,0), _Sundir.xyz).xxx, 1.0f);

          return _Color;
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
            #pragma shader_feature SUBSURFACE
            #pragma shader_feature REFRACTION_THIN
            #pragma shader_feature LIGHTSOURCE
            #pragma shader_feature SURFACE_TYPE_TRANSPARENT
            #pragma shader_feature NORMALMAP

            #include "../Common/PtCommon.hlsl"
            #include "../PRNG.hlsl"
            #include "../ONB.hlsl" 
            #include  "../Sampling.hlsl"

            #include "PathTracingIntersection.hlsl"
            #include  "Lighting.hlsl"
            #include  "PathTracingMaterial.hlsl"
            #include "PathTracingBSDF.hlsl"
            #include "LitPathTracing.hlsl"
            #include "ShaderPassPathTracing.hlsl"
            #include "PathTracingSampling.hlsl"
            TEXTURE2D(_BaseColorMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_BaseColorMap);
            SAMPLER(sampler_NormalMap);


         [shader("closesthit")]
        void ClosestHit(inout PathIntersection pathIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
        {
            // Always set the new t value
            pathIntersection.t = RayTCurrent();

            // If the max depth has been reached, bail out
            if (!pathIntersection.remainingDepth)
            {
                pathIntersection.value = 0.0;
                return;
            }

            // Grab depth information
            int currentDepth = MAX_DEPTH - pathIntersection.remainingDepth;
     
            float4 inputSample = 0;       
            float pdf = 1.0;
            bool sampleLocalLights, sampleVolume = false;
          
            if (currentDepth >= 0)
            {
                // Generate a 4D unit-square sample for this depth, from our QMC sequence
                inputSample = GetSample4D(pathIntersection.pixelCoord, _FrameIndex, 4 * currentDepth);
                if (!currentDepth)
                    sampleVolume = SampleVolumeScatteringPosition(inputSample.w, pathIntersection.t, pdf, sampleLocalLights);
            }

            if (sampleVolume)
            {
                ComputeVolumeScattering(pathIntersection, inputSample.xyz, sampleLocalLights);
                pathIntersection.value /= pdf;
                return;
            }
               
            // The first thing that we should do is grab the intersection vertex
            IntersectionVertex currentVertex;
            GetCurrentIntersectionVertex(attributeData, currentVertex);

            // Build the Frag inputs from the intersection vertex
            FragInputs fragInput;
            BuildFragInputsFromIntersection(currentVertex, WorldRayDirection(), fragInput);
  
            // Such an invalid remainingDepth value means we are called from a subsurface computation
            if (pathIntersection.remainingDepth > MAX_DEPTH)
            {
                pathIntersection.value = fragInput.tangentToWorld[2]; // Returns normal
                return;
            }

            // Make sure to add the additional travel distance
            pathIntersection.cone.width += pathIntersection.t * abs(pathIntersection.cone.spreadAngle);

            PositionInputs posInput;
            posInput.positionWS = fragInput.positionRWS;
            posInput.positionSS = pathIntersection.pixelCoord;

            // For path tracing, we want the front-facing test to be performed on the actual geometric normal
            float3 geomNormal;
            GetCurrentIntersectionGeometricNormal(attributeData, geomNormal);
            fragInput.isFrontFace = dot(WorldRayDirection(), geomNormal) < 0.0;
     

            // Build the surfacedata and builtindata
            SurfaceData surfaceData;
            BuiltinData builtinData;
            bool isVisible;
            GetSurfaceAndBuiltinData(fragInput, -WorldRayDirection(), posInput, surfaceData, builtinData, currentVertex, pathIntersection.cone, isVisible);
            // Check if we want to compute direct and emissive lighting for current depth
            bool computeDirect = currentDepth >= MIN_DEPTH - 1;
            float3 normalTS = UnpackNormalmapRGorAG(SAMPLE_TEXTURE2D_LOD(_NormalMap, sampler_NormalMap, currentVertex.texCoord0,0)).rgb;
            float3 normalWS = normalize(mul(normalTS, fragInput.tangentToWorld)); 
            float4 color =  SAMPLE_TEXTURE2D_LOD(_BaseColorMap, sampler_BaseColorMap, currentVertex.texCoord0, 0);
            // Compute the bsdf data
            BSDFDataMini bsdfDD = ConvertSurfaceDataToBSDFData(posInput.positionSS);

//#if REFRACTION_THIN
//            if (fragInput.isFrontFace)
//            {
//                //normalOS = -normalOS;
//               // geomNormal = -geomNormal;
//                bsdfDD.ior =_IOR;
//            }
//#endif
#if NORMALMAP
            bsdfDD.normalWS = normalWS;
#else
            bsdfDD.normalWS = normalize(mul(currentVertex.normalOS, (float3x3)WorldToObject3x4()));
#endif
            bsdfDD.geomNormalWS = geomNormal;
            // Override the geometric normal (otherwise, it is merely the non-mapped smooth normal)
            // Also make sure that it is in the same hemisphere as the shading normal (which may have been flipped)
           // bsdfDD.geomNormalWS = dot(bsdfDD.normalWS, geomNormal) > 0.0 ? geomNormal : -geomNormal;

            // Compute the world space position (the non-camera relative one if camera relative rendering is enabled)
            float3 shadingPosition = fragInput.positionRWS;

            // Get current path throughput
            float3 pathThroughput = pathIntersection.value;

            // And reset the ray intersection color, which will store our final result
            pathIntersection.value = computeDirect ? _EmissionColor : 0.0;
            #if LIGHTSOURCE
            pathIntersection.value = _EmissionColor * _Color * color;
            pathIntersection.remainingDepth = 0;
            return;
            #endif
      
            bool continueNext = CreateMaterialData(pathIntersection, builtinData, bsdfDD, shadingPosition, inputSample.z);
            if (continueNext)
            {
                float3 lightNormal = bsdfDD.normalWS;

                LightList lightList = CreateLightList(shadingPosition, lightNormal);

                // Bunch of variables common to material and light sampling
                float pdf;
                float3 value;
                MaterialResult mtlResult;

                RayDesc rayDescriptor;
                rayDescriptor.Origin = shadingPosition + bsdfDD.geomNormalWS * _RaytracingRayBias;
                rayDescriptor.TMin = 0.0;          
                PathIntersection nextPathIntersection;
                
                // Light sampling
                if (computeDirect)
                {

                   // if (SampleLight(_Sundir.xyz, inputSample.xyz, rayDescriptor.Origin, bsdfDD.geomNormalWS, rayDescriptor.Direction, value, pdf, rayDescriptor.TMax))
                    if (SampleLights(lightList, inputSample.xyz, rayDescriptor.Origin, bsdfDD.geomNormalWS, rayDescriptor.Direction, value, pdf, rayDescriptor.TMax))
                    {
                        EvaluateMaterial(bsdfDD, rayDescriptor.Direction, mtlResult);                                   
                        value *= (mtlResult.diffValue + mtlResult.specValue) / pdf;
                        if (Luminance(value) > 0.001)
                        {
                            // Shoot a transmission ray (to mark it as such, purposedly set remaining depth to an invalid value)
                            nextPathIntersection.remainingDepth = MAX_DEPTH + 1;
                            rayDescriptor.TMax -= _RaytracingRayBias;
                            nextPathIntersection.value = 1.0;

                            // FIXME: For the time being, we choose not to apply any back/front-face culling for shadows, will possibly change in the future
                            TraceRay(_AccelerationStructure, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_FORCE_NON_OPAQUE | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER,
                                RAYTRACINGRENDERERFLAG_CAST_SHADOW, 0, 1, 1, rayDescriptor, nextPathIntersection);

                            float misWeight = PowerHeuristic(pdf, mtlResult.diffPdf + mtlResult.specPdf);
                            pathIntersection.value += value *nextPathIntersection.value /** misWeight*/;
                        }
                    }
                }
               // return;  // Material sampling
                bool xm = SampleMaterial(bsdfDD, inputSample.xyz, rayDescriptor.Direction, mtlResult);               
                if (xm)
                {
                    // Compute overall material value and pdf
                    pdf = mtlResult.diffPdf + mtlResult.specPdf;
                    value = (mtlResult.diffValue + mtlResult.specValue) / pdf;
                    pathThroughput *= value;
                    //// Apply Russian roulette to our path
                    const float rrThreshold = 0.2 + 0.1 * MAX_DEPTH;
                    float rrFactor, rrValue = Luminance(pathThroughput);

                    if (RussianRouletteTest(rrThreshold, rrValue, inputSample.w, rrFactor, !currentDepth))
                    {
                        bool isSampleBelow = IsBelow(bsdfDD, rayDescriptor.Direction);

                        rayDescriptor.Origin = shadingPosition + GetPositionBias(bsdfDD.geomNormalWS, _RaytracingRayBias, isSampleBelow);
                        rayDescriptor.TMax = FLT_INF;

                        // Copy path constants across
                        nextPathIntersection.pixelCoord = pathIntersection.pixelCoord;
                        nextPathIntersection.cone.width = pathIntersection.cone.width;

                        // Complete PathIntersection structure for this sample
                        nextPathIntersection.value = pathThroughput * rrFactor;
                        nextPathIntersection.remainingDepth = pathIntersection.remainingDepth - 1;
                        nextPathIntersection.t = rayDescriptor.TMax;

                        // Adjust the path max roughness (used for roughness clamping, to reduce fireflies)
                        nextPathIntersection.maxRoughness = 1.0;// AdjustPathRoughness(bsdfDD, mtlResult, isSampleBelow, pathIntersection.maxRoughness);
                        // In order to achieve filtering for the textures, we need to compute the spread angle of the pixel
                        nextPathIntersection.cone.spreadAngle = pathIntersection.cone.spreadAngle + roughnessToSpreadAngle(nextPathIntersection.maxRoughness);

                        // Shoot ray for indirect lighting
                        TraceRay(_AccelerationStructure, RAY_FLAG_NONE,  RAYTRACINGRENDERERFLAG_PATH_TRACING, 0, 1, 2, rayDescriptor, nextPathIntersection);

                        if (computeDirect)
                        {
                            // Use same ray for direct lighting (use indirect result for occlusion)
                            rayDescriptor.TMax = nextPathIntersection.t + _RaytracingRayBias;
                            float3 lightValue;
                            float lightPdf;
                            EvaluateLights(lightList, rayDescriptor, lightValue, lightPdf);
                            float misWeight = PowerHeuristic(pdf, lightPdf);
                            nextPathIntersection.value += lightValue * misWeight;
                        }
                        // Apply material absorption
                        float dist = min(nextPathIntersection.t, surfaceData.atDistance * 10.0);
                        pathIntersection.value += value * rrFactor * nextPathIntersection.value;

                    }
                }
            } 

                pathIntersection.value /= pdf;
          }

            [shader("anyhit")]
            void AnyHit(inout PathIntersection pathIntersection : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes)
            {
                // The first thing that we should do is grab the intersection vertice
                IntersectionVertex currentVertex;
                GetCurrentIntersectionVertex(attributeData, currentVertex);

                // Build the Frag inputs from the intersection vertex
                FragInputs fragInput;
                BuildFragInputsFromIntersection(currentVertex, WorldRayDirection(), fragInput);

                PositionInputs posInput;
                posInput.positionWS = fragInput.positionRWS;
                posInput.positionSS = pathIntersection.pixelCoord;

                // Build the surfacedata and builtindata
                SurfaceData surfaceData;
                BuiltinData builtinData;
                bool isVisible;
                GetSurfaceAndBuiltinData(fragInput, -WorldRayDirection(), posInput, surfaceData, builtinData, currentVertex, pathIntersection.cone, isVisible);
#if LIGHTSOURCE
                IgnoreHit();
                return;
#endif
                // Check alpha clipping
                if (false)
                {
                    IgnoreHit();
                }
                else if (pathIntersection.remainingDepth > MAX_DEPTH)
                {
#ifdef SURFACE_TYPE_TRANSPARENT
#if REFRACTION_THIN
                    pathIntersection.value *= _TransmittanceMask /** _TransmittanceColor*/;
#else
                    pathIntersection.value *= 1.0 - _Color.a;
#endif
                    if (Luminance(pathIntersection.value) < 0.001)
                        AcceptHitAndEndSearch();
                    else
                        IgnoreHit();
#else
                    // Opaque surface
                    pathIntersection.value = 0.0;

                    AcceptHitAndEndSearch();
#endif
                }
            }
             ENDHLSL
            }
        }
     }
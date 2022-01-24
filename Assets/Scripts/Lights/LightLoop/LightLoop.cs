using System;
using System.Collections.Generic;
using UnityEngine.Experimental.Rendering;

namespace UnityEngine.Rendering.HighDefinition
{
    static class VisibleLightExtensionMethods
    {
        public struct VisibleLightAxisAndPosition
        {
            public Vector3 Position;
            public Vector3 Forward;
            public Vector3 Up;
            public Vector3 Right;
        }

        public static Vector3 GetPosition(this VisibleLight value)
        {
            return value.localToWorldMatrix.GetColumn(3);
        }

        public static Vector3 GetForward(this VisibleLight value)
        {
            return value.localToWorldMatrix.GetColumn(2);
        }

        public static Vector3 GetUp(this VisibleLight value)
        {
            return value.localToWorldMatrix.GetColumn(1);
        }

        public static Vector3 GetRight(this VisibleLight value)
        {
            return value.localToWorldMatrix.GetColumn(0);
        }

        public static VisibleLightAxisAndPosition GetAxisAndPosition(this VisibleLight value)
        {
            var matrix = value.localToWorldMatrix;
            VisibleLightAxisAndPosition output;
            output.Position = matrix.GetColumn(3);
            output.Forward  = matrix.GetColumn(2);
            output.Up       = matrix.GetColumn(1);
            output.Right    = matrix.GetColumn(0);
            return output;
        }
    }

    //-----------------------------------------------------------------------------
    // structure definition
    //-----------------------------------------------------------------------------

    [GenerateHLSL]
    internal enum LightVolumeType
    {
        Cone,
        Sphere,
        Box,
        Count
    }

    [GenerateHLSL]
    internal enum LightCategory
    {
        Punctual,
        Area,
        Env,
        ProbeVolume,
        Decal,
        DensityVolume, // WARNING: Currently lightlistbuild.compute assumes density volume is the last element in the LightCategory enum. Do not append new LightCategory types after DensityVolume. TODO: Fix .compute code.
        Count
    }

    [GenerateHLSL]
    internal enum LightFeatureFlags
    {
        // Light bit mask must match LightDefinitions.s_LightFeatureMaskFlags value
        Punctual    = 1 << 12,
        Area        = 1 << 13,
        Directional = 1 << 14,
        Env         = 1 << 15,
        Sky         = 1 << 16,
        SSRefraction = 1 << 17,
        SSReflection = 1 << 18,
        ProbeVolume = 1 << 19
            // If adding more light be sure to not overflow LightDefinitions.s_LightFeatureMaskFlags
    }

    [GenerateHLSL]
    class LightDefinitions
    {
        public static int s_MaxNrBigTileLightsPlusOne = 512;      // may be overkill but the footprint is 2 bits per pixel using uint16.
        public static float s_ViewportScaleZ = 1.0f;
        public static int s_UseLeftHandCameraSpace = 1;

        public static int s_TileSizeFptl = 16;
        public static int s_TileSizeClustered = 32;
        public static int s_TileSizeBigTile = 64;

        // Tile indexing constants for indirect dispatch deferred pass : [2 bits for eye index | 15 bits for tileX | 15 bits for tileY]
        public static int s_TileIndexMask = 0x7FFF;
        public static int s_TileIndexShiftX = 0;
        public static int s_TileIndexShiftY = 15;
        public static int s_TileIndexShiftEye = 30;

        // feature variants
        public static int s_NumFeatureVariants = 29;

        // light list limits
        public static int s_LightListMaxCoarseEntries = 64;
        public static int s_LightListMaxPrunedEntries = 24;
        public static int s_LightClusterMaxCoarseEntries = 128;

        // Following define the maximum number of bits use in each feature category.
        public static uint s_LightFeatureMaskFlags = 0xFFF000;
        public static uint s_LightFeatureMaskFlagsOpaque = 0xFFF000 & ~((uint)LightFeatureFlags.SSRefraction); // Opaque don't support screen space refraction
        public static uint s_LightFeatureMaskFlagsTransparent = 0xFFF000 & ~((uint)LightFeatureFlags.SSReflection); // Transparent don't support screen space reflection
        public static uint s_MaterialFeatureMaskFlags = 0x000FFF;   // don't use all bits just to be safe from signed and/or float conversions :/

        // Screen space shadow flags
        public static uint s_RayTracedScreenSpaceShadowFlag = 0x1000;
        public static uint s_ScreenSpaceColorShadowFlag = 0x100;
        public static uint s_InvalidScreenSpaceShadow = 0xff;
        public static uint s_ScreenSpaceShadowIndexMask = 0xff;
    }

    [GenerateHLSL]
    struct SFiniteLightBound
    {
        public Vector3 boxAxisX; // Scaled by the extents (half-size)
        public Vector3 boxAxisY; // Scaled by the extents (half-size)
        public Vector3 boxAxisZ; // Scaled by the extents (half-size)
        public Vector3 center;   // Center of the bounds (box) in camera space
        public float   scaleXY;  // Scale applied to the top of the box to turn it into a truncated pyramid (X = Y)
        public float   radius;     // Circumscribed sphere for the bounds (box)
    };

    [GenerateHLSL]
    struct LightVolumeData
    {
        public Vector3 lightPos;     // Of light's "origin"
        public uint lightVolume;     // Type index

        public Vector3 lightAxisX;   // Normalized
        public uint lightCategory;   // Category index

        public Vector3 lightAxisY;   // Normalized
        public float radiusSq;       // Cone and sphere: light range squared

        public Vector3 lightAxisZ;   // Normalized
        public float cotan;          // Cone: cotan of the aperture (half-angle)

        public Vector3 boxInnerDist; // Box: extents (half-size) of the inner box
        public uint featureFlags;

        public Vector3 boxInvRange;  // Box: 1 / (OuterBoxExtents - InnerBoxExtents)
        public float unused2;
    };

    /// <summary>
    /// Tile and Cluster Debug Mode.
    /// </summary>
    public enum TileClusterDebug : int
    {
        /// <summary>No Tile and Cluster debug.</summary>
        None,
        /// <summary>Display lighting tiles debug.</summary>
        Tile,
        /// <summary>Display lighting clusters debug.</summary>
        Cluster,
        /// <summary>Display material feautre variants.</summary>
        MaterialFeatureVariants
    };

    /// <summary>
    /// Cluster visualization mode.
    /// </summary>
    [GenerateHLSL]
    public enum ClusterDebugMode : int
    {
        /// <summary>Visualize Cluster on opaque objects.</summary>
        VisualizeOpaque,
        /// <summary>Visualize a slice of the Cluster at a given distance.</summary>
        VisualizeSlice
    }

    /// <summary>
    /// Light Volume Debug Mode.
    /// </summary>
    public enum LightVolumeDebug : int
    {
        /// <summary>Display light volumes as a gradient.</summary>
        Gradient,
        /// <summary>Display light volumes as shapes will color and edges depending on the light type.</summary>
        ColorAndEdge
    };

    /// <summary>
    /// Tile and Cluster Debug Categories.
    /// </summary>
    public enum TileClusterCategoryDebug : int
    {
        /// <summary>Punctual lights.</summary>
        Punctual = 1,
        /// <summary>Area lights.</summary>
        Area = 2,
        /// <summary>Area and punctual lights.</summary>
        AreaAndPunctual = 3,
        /// <summary>Environment lights.</summary>
        Environment = 4,
        /// <summary>Environment and punctual lights.</summary>
        EnvironmentAndPunctual = 5,
        /// <summary>Environment and area lights.</summary>
        EnvironmentAndArea = 6,
        /// <summary>All lights.</summary>
        EnvironmentAndAreaAndPunctual = 7,
        /// <summary>Probe Volumes.</summary>
        ProbeVolumes = 8,
        /// <summary>Decals.</summary>
        Decal = 16,
        /// <summary>Density Volumes.</summary>
        DensityVolumes = 32
    };

    [GenerateHLSL(needAccessors = false, generateCBuffer = true)]
    unsafe struct ShaderVariablesLightList
    {
        [HLSLArray(ShaderConfig.k_XRMaxViewsForCBuffer, typeof(Matrix4x4))]
        public fixed float  g_mInvScrProjectionArr[ShaderConfig.k_XRMaxViewsForCBuffer * 16];
        [HLSLArray(ShaderConfig.k_XRMaxViewsForCBuffer, typeof(Matrix4x4))]
        public fixed float  g_mScrProjectionArr[ShaderConfig.k_XRMaxViewsForCBuffer * 16];
        [HLSLArray(ShaderConfig.k_XRMaxViewsForCBuffer, typeof(Matrix4x4))]
        public fixed float  g_mInvProjectionArr[ShaderConfig.k_XRMaxViewsForCBuffer * 16];
        [HLSLArray(ShaderConfig.k_XRMaxViewsForCBuffer, typeof(Matrix4x4))]
        public fixed float  g_mProjectionArr[ShaderConfig.k_XRMaxViewsForCBuffer * 16];

        public Vector4      g_screenSize;

        public Vector2Int   g_viDimensions;
        public int          g_iNrVisibLights;
        public uint         g_isOrthographic;

        public uint         g_BaseFeatureFlags;
        public int          g_iNumSamplesMSAA;
        public uint         _EnvLightIndexShift;
        public uint         _DecalIndexShift;

        public uint         _DensityVolumeIndexShift;
        public uint         _ProbeVolumeIndexShift;
        public uint         _Pad0_SVLL;
        public uint         _Pad1_SVLL;
    }

    internal struct ProcessedLightData
    {
        public HDAdditionalLightData    additionalLightData;
        public HDLightType              lightType;
        public LightCategory            lightCategory;
        public GPULightType             gpuLightType;
        public LightVolumeType          lightVolumeType;
        public float                    distanceToCamera;
        public float                    lightDistanceFade;
        public float                    volumetricDistanceFade;
        public bool                     isBakedShadowMask;
    }

    internal struct ProcessedProbeData
    {
       // public HDProbe  hdProbe;
        public float    weight;
    }

    public partial class HDRenderPipeline
    {
        internal class LightList
        {
            public List<DirectionalLightData> directionalLights;
            public List<LightData> lights;
            public List<EnvLightData> envLights;
            public int punctualLightCount;
            public int areaLightCount;

            public struct LightsPerView
            {
                public List<SFiniteLightBound> bounds;
                public List<LightVolumeData> lightVolumes;
                public List<SFiniteLightBound> probeVolumesBounds;
                public List<LightVolumeData> probeVolumesLightVolumes;
            }

            public List<LightsPerView> lightsPerView;

            public void Clear()
            {
                directionalLights.Clear();
                lights.Clear();
                envLights.Clear();
                punctualLightCount = 0;
                areaLightCount = 0;

                for (int i = 0; i < lightsPerView.Count; ++i)
                {
                    lightsPerView[i].bounds.Clear();
                    lightsPerView[i].lightVolumes.Clear();
                    lightsPerView[i].probeVolumesBounds.Clear();
                    lightsPerView[i].probeVolumesLightVolumes.Clear();
                }
            }

            public void Allocate()
            {
                directionalLights = new List<DirectionalLightData>();
                lights = new List<LightData>();
                envLights = new List<EnvLightData>();

                lightsPerView = new List<LightsPerView>();
                for (int i = 0; i < TextureXR.slices; ++i)
                {
                    lightsPerView.Add(new LightsPerView { bounds = new List<SFiniteLightBound>(), lightVolumes = new List<LightVolumeData>(), probeVolumesBounds = new List<SFiniteLightBound>(), probeVolumesLightVolumes = new List<LightVolumeData>() });
                }
            }
        }
        internal class LightLoopLightData
        {
            public ComputeBuffer directionalLightData { get; private set; }
            public ComputeBuffer lightData { get; private set; }
          //  public ComputeBuffer envLightData { get; private set; }
          //  public ComputeBuffer decalData { get; private set; }

            public void Initialize(int directionalCount, int punctualCount, int areaLightCount)
            {
                directionalLightData = new ComputeBuffer(directionalCount, System.Runtime.InteropServices.Marshal.SizeOf(typeof(DirectionalLightData)));
                lightData = new ComputeBuffer(punctualCount + areaLightCount, System.Runtime.InteropServices.Marshal.SizeOf(typeof(LightData)));
                //envLightData = new ComputeBuffer(envLightCount, System.Runtime.InteropServices.Marshal.SizeOf(typeof(EnvLightData)));
                //decalData = new ComputeBuffer(decalCount, System.Runtime.InteropServices.Marshal.SizeOf(typeof(DecalData)));
            }

            public void Cleanup()
            {
                CoreUtils.SafeRelease(directionalLightData);
                CoreUtils.SafeRelease(lightData);
            //    CoreUtils.SafeRelease(envLightData);
              //  CoreUtils.SafeRelease(decalData);
            }
        }
        internal LightList m_lightList;
        internal LightLoopLightData m_LightLoopLightData = new LightLoopLightData();
        int m_TotalLightCount = 0;
        int m_DensityVolumeCount = 0;
        int m_ProbeVolumeCount = 0;
        internal static Vector3 GetLightColor(VisibleLight light)
        {
            return new Vector3(light.finalColor.r, light.finalColor.g, light.finalColor.b);
        }

        // Keep sorting array around to avoid garbage
        uint[] m_SortKeys = null;
        DynamicArray<ProcessedLightData> m_ProcessedLightData = new DynamicArray<ProcessedLightData>();
        DynamicArray<ProcessedProbeData> m_ProcessedReflectionProbeData = new DynamicArray<ProcessedProbeData>();
        DynamicArray<ProcessedProbeData> m_ProcessedPlanarProbeData = new DynamicArray<ProcessedProbeData>();
        // Directional light
        Light m_CurrentSunLight;
        int m_CurrentShadowSortedSunLightIndex = -1;
        HDAdditionalLightData m_CurrentSunLightAdditionalLightData;
        DirectionalLightData m_CurrentSunLightDirectionalLightData;
        Light GetCurrentSunLight() { return m_CurrentSunLight; }
        void UpdateSortKeysArray(int count)
        {
            if (m_SortKeys == null || count > m_SortKeys.Length)
            {
                m_SortKeys = new uint[count];
            }
        }
        int m_MaxLightsOnScreen = 256;
        int m_MaxDirectionalLightsOnScreen = 256;
        int m_MaxPunctualLightsOnScreen = 256;
        int m_MaxAreaLightsOnScreen = 256;
      public  void InitializeLightLoop()
        {
    
           m_lightList = new LightList();
           m_lightList.Allocate();
            // All the allocation of the compute buffers need to happened after the kernel finding in order to avoid the leak loop when a shader does not compile or is not available
           m_LightLoopLightData.Initialize(m_MaxDirectionalLightsOnScreen, m_MaxPunctualLightsOnScreen, m_MaxAreaLightsOnScreen);
            m_MaxLightsOnScreen = 256;
           // m_TileAndClusterData.Initialize(allocateTileBuffers: true, clusterNeedsDepth: k_UseDepthBuffer, maxLightCount: m_MaxLightsOnScreen);
           

        }


        internal static void EvaluateGPULightType(HDLightType lightType, SpotLightShape spotLightShape, AreaLightShape areaLightShape,
        ref LightCategory lightCategory, ref GPULightType gpuLightType, ref LightVolumeType lightVolumeType)
        {
            lightCategory = LightCategory.Count;
            gpuLightType = GPULightType.Point;
            lightVolumeType = LightVolumeType.Count;

            switch (lightType)
            {
                case HDLightType.Spot:
                    lightCategory = LightCategory.Punctual;

                    switch (spotLightShape)
                    {
                        case SpotLightShape.Cone:
                            gpuLightType = GPULightType.Spot;
                            lightVolumeType = LightVolumeType.Cone;
                            break;
                        case SpotLightShape.Pyramid:
                            gpuLightType = GPULightType.ProjectorPyramid;
                            lightVolumeType = LightVolumeType.Cone;
                            break;
                        case SpotLightShape.Box:
                            gpuLightType = GPULightType.ProjectorBox;
                            lightVolumeType = LightVolumeType.Box;
                            break;
                        default:
                            Debug.Assert(false, "Encountered an unknown SpotLightShape.");
                            break;
                    }
                    break;

                case HDLightType.Directional:
                    lightCategory = LightCategory.Punctual;
                    gpuLightType = GPULightType.Directional;
                    // No need to add volume, always visible
                    lightVolumeType = LightVolumeType.Count; // Count is none
                    break;

                case HDLightType.Point:
                    lightCategory = LightCategory.Punctual;
                    gpuLightType = GPULightType.Point;
                    lightVolumeType = LightVolumeType.Sphere;
                    break;

                case HDLightType.Area:
                    lightCategory = LightCategory.Area;

                    switch (areaLightShape)
                    {
                        case AreaLightShape.Rectangle:
                            gpuLightType = GPULightType.Rectangle;
                            lightVolumeType = LightVolumeType.Box;
                            break;

                        case AreaLightShape.Tube:
                            gpuLightType = GPULightType.Tube;
                            lightVolumeType = LightVolumeType.Box;
                            break;

                        case AreaLightShape.Disc:
                            //not used in real-time at the moment anyway
                            gpuLightType = GPULightType.Disc;
                            lightVolumeType = LightVolumeType.Sphere;
                            break;

                        default:
                            Debug.Assert(false, "Encountered an unknown AreaLightShape.");
                            break;
                    }
                    break;

                default:
                    Debug.Assert(false, "Encountered an unknown LightType.");
                    break;
            }
        }
        internal void GetLightData(CommandBuffer cmd,  VisibleLight light, in ProcessedLightData processedData,  ref Vector3 lightDimensions, ref LightData lightData)
        {
            var additionalLightData = processedData.additionalLightData;
            var gpuLightType = processedData.gpuLightType;
            var lightType = processedData.lightType;

            var visibleLightAxisAndPosition = light.GetAxisAndPosition();
            lightData.lightLayers =  additionalLightData.GetLightLayers();

            lightData.lightType = gpuLightType;

            lightData.positionRWS = visibleLightAxisAndPosition.Position;

            lightData.range = light.range;

            if (additionalLightData.applyRangeAttenuation)
            {
                lightData.rangeAttenuationScale = 1.0f / (light.range * light.range);
                lightData.rangeAttenuationBias = 1.0f;

                if (lightData.lightType == GPULightType.Rectangle)
                {
                    // Rect lights are currently a special case because they use the normalized
                    // [0, 1] attenuation range rather than the regular [0, r] one.
                    lightData.rangeAttenuationScale = 1.0f;
                }
            }
            else // Don't apply any attenuation but do a 'step' at range
            {
                // Solve f(x) = b - (a * x)^2 where x = (d/r)^2.
                // f(0) = huge -> b = huge.
                // f(1) = 0    -> huge - a^2 = 0 -> a = sqrt(huge).
                const float hugeValue = 16777216.0f;
                const float sqrtHuge = 4096.0f;
                lightData.rangeAttenuationScale = sqrtHuge / (light.range * light.range);
                lightData.rangeAttenuationBias = hugeValue;

                if (lightData.lightType == GPULightType.Rectangle)
                {
                    // Rect lights are currently a special case because they use the normalized
                    // [0, 1] attenuation range rather than the regular [0, r] one.
                    lightData.rangeAttenuationScale = sqrtHuge;
                }
            }

            lightData.color = GetLightColor(light);

            lightData.forward = visibleLightAxisAndPosition.Forward;
            lightData.up = visibleLightAxisAndPosition.Up;
            lightData.right = visibleLightAxisAndPosition.Right;

            lightDimensions.x = additionalLightData.shapeWidth;
            lightDimensions.y = additionalLightData.shapeHeight;
            lightDimensions.z = light.range;

            lightData.boxLightSafeExtent = 1.0f;
            if (lightData.lightType == GPULightType.ProjectorBox)
            {
                // Rescale for cookies and windowing.
                lightData.right *= 2.0f / Mathf.Max(additionalLightData.shapeWidth, 0.001f);
                lightData.up *= 2.0f / Mathf.Max(additionalLightData.shapeHeight, 0.001f);


            }
            else if (lightData.lightType == GPULightType.ProjectorPyramid)
            {
                // Get width and height for the current frustum
                var spotAngle = light.spotAngle;

                float frustumWidth, frustumHeight;

                if (additionalLightData.aspectRatio >= 1.0f)
                {
                    frustumHeight = 2.0f * Mathf.Tan(spotAngle * 0.5f * Mathf.Deg2Rad);
                    frustumWidth = frustumHeight * additionalLightData.aspectRatio;
                }
                else
                {
                    frustumWidth = 2.0f * Mathf.Tan(spotAngle * 0.5f * Mathf.Deg2Rad);
                    frustumHeight = frustumWidth / additionalLightData.aspectRatio;
                }

                // Adjust based on the new parametrization.
                lightDimensions.x = frustumWidth;
                lightDimensions.y = frustumHeight;

                // Rescale for cookies and windowing.
                lightData.right *= 2.0f / frustumWidth;
                lightData.up *= 2.0f / frustumHeight;
            }

            if (lightData.lightType == GPULightType.Spot)
            {
                var spotAngle = light.spotAngle;

                var innerConePercent = additionalLightData.innerSpotPercent01;
                var cosSpotOuterHalfAngle = Mathf.Clamp(Mathf.Cos(spotAngle * 0.5f * Mathf.Deg2Rad), 0.0f, 1.0f);
                var sinSpotOuterHalfAngle = Mathf.Sqrt(1.0f - cosSpotOuterHalfAngle * cosSpotOuterHalfAngle);
                var cosSpotInnerHalfAngle = Mathf.Clamp(Mathf.Cos(spotAngle * 0.5f * innerConePercent * Mathf.Deg2Rad), 0.0f, 1.0f); // inner cone

                var val = Mathf.Max(0.0001f, (cosSpotInnerHalfAngle - cosSpotOuterHalfAngle));
                lightData.angleScale = 1.0f / val;
                lightData.angleOffset = -cosSpotOuterHalfAngle * lightData.angleScale;
                lightData.iesCut = additionalLightData.spotIESCutoffPercent01;

                // Rescale for cookies and windowing.
                float cotOuterHalfAngle = cosSpotOuterHalfAngle / sinSpotOuterHalfAngle;
                lightData.up *= cotOuterHalfAngle;
                lightData.right *= cotOuterHalfAngle;
            }
            else
            {
                // These are the neutral values allowing GetAngleAnttenuation in shader code to return 1.0
                lightData.angleScale = 0.0f;
                lightData.angleOffset = 1.0f;
                lightData.iesCut = 1.0f;
            }

            if (lightData.lightType != GPULightType.Directional && lightData.lightType != GPULightType.ProjectorBox)
            {
                // Store the squared radius of the light to simulate a fill light.
                lightData.size = new Vector4(additionalLightData.shapeRadius * additionalLightData.shapeRadius, 0, 0, 0);
            }

            if (lightData.lightType == GPULightType.Rectangle || lightData.lightType == GPULightType.Tube)
            {
                lightData.size = new Vector4(additionalLightData.shapeWidth, additionalLightData.shapeHeight, Mathf.Cos(additionalLightData.barnDoorAngle * Mathf.PI / 180.0f), additionalLightData.barnDoorLength);
            }

            lightData.lightDimmer = processedData.lightDistanceFade * (additionalLightData.lightDimmer);
            lightData.diffuseDimmer = processedData.lightDistanceFade * (additionalLightData.affectDiffuse ? additionalLightData.lightDimmer : 0);
            lightData.specularDimmer = processedData.lightDistanceFade * additionalLightData.lightDimmer;
            lightData.volumetricLightDimmer = Mathf.Min(processedData.volumetricDistanceFade, processedData.lightDistanceFade) * (additionalLightData.volumetricDimmer);

            lightData.cookieMode = CookieMode.None;
            lightData.shadowIndex = -1;
            lightData.screenSpaceShadowIndex = (int)LightDefinitions.s_InvalidScreenSpaceShadow;
            lightData.isRayTracedContactShadow = 0.0f;
            //Value of max smoothness is derived from Radius. Formula results from eyeballing. Radius of 0 results in 1 and radius of 2.5 results in 0.
            float maxSmoothness = Mathf.Clamp01(1.1725f / (1.01f + Mathf.Pow(1.0f * (additionalLightData.shapeRadius + 0.1f), 2f)) - 0.15f);
            // Value of max smoothness is from artists point of view, need to convert from perceptual smoothness to roughness
            lightData.minRoughness = (1.0f - maxSmoothness) * (1.0f - maxSmoothness);

            lightData.shadowMaskSelector = Vector4.zero;

        }


        internal void GetDirectionalLightData(CommandBuffer cmd, Camera hdCamera, VisibleLight light, Light lightComponent, int lightIndex, int shadowIndex,
            int sortedIndex, bool isPhysicallyBasedSkyActive)
        {
            var processedData = m_ProcessedLightData[lightIndex];
            var additionalLightData = processedData.additionalLightData;
            var gpuLightType = processedData.gpuLightType;

            var lightData = new DirectionalLightData();

            lightData.lightLayers =  uint.MaxValue;

            // Light direction for directional is opposite to the forward direction
            lightData.forward = light.GetForward();
            // Rescale for cookies and windowing.
            lightData.right = light.GetRight() * 2 / Mathf.Max(additionalLightData.shapeWidth, 0.001f);
            lightData.up = light.GetUp() * 2 / Mathf.Max(additionalLightData.shapeHeight, 0.001f);
            lightData.positionRWS = light.GetPosition();
            lightData.color = GetLightColor(light);

            // Caution: This is bad but if additionalData == HDUtils.s_DefaultHDAdditionalLightData it mean we are trying to promote legacy lights, which is the case for the preview for example, so we need to multiply by PI as legacy Unity do implicit divide by PI for direct intensity.
            // So we expect that all light with additionalData == HDUtils.s_DefaultHDAdditionalLightData are currently the one from the preview, light in scene MUST have additionalData
            lightData.color *=  Mathf.PI;

            lightData.lightDimmer = additionalLightData.lightDimmer;
            lightData.diffuseDimmer = additionalLightData.affectDiffuse ? additionalLightData.lightDimmer : 0;
            lightData.specularDimmer = 0;
            lightData.volumetricLightDimmer = additionalLightData.volumetricDimmer;

            lightData.shadowIndex = -1;
            lightData.screenSpaceShadowIndex = (int)LightDefinitions.s_InvalidScreenSpaceShadow;
            lightData.isRayTracedContactShadow = 0.0f;

            //if (lightComponent != null && lightComponent.cookie != null)
            //{
            //    lightData.cookieMode = lightComponent.cookie.wrapMode == TextureWrapMode.Repeat ? CookieMode.Repeat : CookieMode.Clamp;
            //   // lightData.cookieScaleOffset = m_TextureCaches.lightCookieManager.Fetch2DCookie(cmd, lightComponent.cookie);
            //}
            //else
            {
                lightData.cookieMode = CookieMode.None;
            }

           // if (additionalLightData.surfaceTexture == null)
            {
                lightData.surfaceTextureScaleOffset = Vector4.zero;
            }
            //else
            //{
            //    lightData.surfaceTextureScaleOffset = m_TextureCaches.lightCookieManager.Fetch2DCookie(cmd, additionalLightData.surfaceTexture);
            //}

            lightData.shadowDimmer = additionalLightData.shadowDimmer;
            lightData.volumetricShadowDimmer = additionalLightData.volumetricShadowDimmer;
            //GetContactShadowMask(additionalLightData, HDAdditionalLightData.ScalableSettings.UseContactShadow(m_Asset), hdCamera, isRasterization: true, ref lightData.contactShadowMask, ref lightData.isRayTracedContactShadow);

            // We want to have a colored penumbra if the flag is on and the color is not gray
            bool penumbraTint = additionalLightData.penumbraTint && ((additionalLightData.shadowTint.r != additionalLightData.shadowTint.g) || (additionalLightData.shadowTint.g != additionalLightData.shadowTint.b));
            lightData.penumbraTint = penumbraTint ? 1.0f : 0.0f;
            if (penumbraTint)
                lightData.shadowTint = new Vector3(additionalLightData.shadowTint.r * additionalLightData.shadowTint.r, additionalLightData.shadowTint.g * additionalLightData.shadowTint.g, additionalLightData.shadowTint.b * additionalLightData.shadowTint.b);
            else
                lightData.shadowTint = new Vector3(additionalLightData.shadowTint.r, additionalLightData.shadowTint.g, additionalLightData.shadowTint.b);

            // fix up shadow information
            lightData.shadowIndex = shadowIndex;
            if (shadowIndex != -1)
            {

                m_CurrentSunLight = lightComponent;
                m_CurrentSunLightAdditionalLightData = additionalLightData;
                m_CurrentSunLightDirectionalLightData = lightData;
                m_CurrentShadowSortedSunLightIndex = sortedIndex;
            }
            //Value of max smoothness is derived from AngularDiameter. Formula results from eyeballing. Angular diameter of 0 results in 1 and angular diameter of 80 results in 0.
            float maxSmoothness = Mathf.Clamp01(1.35f / (1.0f + Mathf.Pow(1.15f * (0.0315f * additionalLightData.angularDiameter + 0.4f), 2f)) - 0.11f);
            // Value of max smoothness is from artists point of view, need to convert from perceptual smoothness to roughness
            lightData.minRoughness = (1.0f - maxSmoothness) * (1.0f - maxSmoothness);

            lightData.shadowMaskSelector = Vector4.zero;

            if (processedData.isBakedShadowMask)
            {
                lightData.shadowMaskSelector[lightComponent.bakingOutput.occlusionMaskChannel] = 1.0f;
                lightData.nonLightMappedOnly = lightComponent.lightShadowCasterMode == LightShadowCasterMode.NonLightmappedOnly ? 1 : 0;
            }
            else
            {
                // use -1 to say that we don't use shadow mask
                lightData.shadowMaskSelector.x = -1.0f;
                lightData.nonLightMappedOnly = 0;
            }

            bool interactsWithSky = isPhysicallyBasedSkyActive && additionalLightData.interactsWithSky;

            lightData.distanceFromCamera = -1; // Encode 'interactsWithSky'

            //if (interactsWithSky)
            //{
            //    lightData.distanceFromCamera = additionalLightData.distance;

            //    if (ShaderConfig.s_PrecomputedAtmosphericAttenuation != 0)
            //    {
            //        var skySettings = hdCamera.volumeStack.GetComponent<PhysicallyBasedSky>();

            //        // Ignores distance (at infinity).
            //        Vector3 transm = EvaluateAtmosphericAttenuation(skySettings, -lightData.forward, hdCamera.GetComponent<UnityEngine.Camera>().transform.position);
            //        lightData.color.x *= transm.x;
            //        lightData.color.y *= transm.y;
            //        lightData.color.z *= transm.z;
            //    }
            //}

            lightData.angularDiameter = additionalLightData.angularDiameter * Mathf.Deg2Rad;
            lightData.flareSize = Mathf.Max(additionalLightData.flareSize * Mathf.Deg2Rad, 5.960464478e-8f);
            lightData.flareFalloff = additionalLightData.flareFalloff;
            lightData.flareTint = (Vector3)(Vector4)additionalLightData.flareTint;
            lightData.surfaceTint = (Vector3)(Vector4)additionalLightData.surfaceTint;

            // Fallback to the first non shadow casting directional light.
            m_CurrentSunLight = m_CurrentSunLight == null ? lightComponent : m_CurrentSunLight;

            m_lightList.directionalLights.Add(lightData);
        }
        HDAdditionalLightData GetHDAdditionalLightData(Light light)
        {
            HDAdditionalLightData add = null;

            // Light reference can be null for particle lights.
            if (light != null)
                light.TryGetComponent<HDAdditionalLightData>(out add);

            //// Light should always have additional data, however preview light right don't have, so we must handle the case by assigning HDUtils.s_DefaultHDAdditionalLightData
            //if (add == null)
            //    add = HDUtils.s_DefaultHDAdditionalLightData;

            return add;
        }
        void PreprocessLightData(ref ProcessedLightData processedData, VisibleLight light, Camera hdCamera)
        {
            Light lightComponent = light.light;
            HDAdditionalLightData additionalLightData = GetHDAdditionalLightData(lightComponent);

            processedData.additionalLightData = additionalLightData;
            processedData.lightType = additionalLightData.ComputeLightType(lightComponent);
            processedData.distanceToCamera = (additionalLightData.transform.position - hdCamera.transform.position).magnitude;

            // Evaluate the types that define the current light
            processedData.lightCategory = LightCategory.Count;
            processedData.gpuLightType = GPULightType.Point;
            processedData.lightVolumeType = LightVolumeType.Count;
            HDRenderPipeline.EvaluateGPULightType(processedData.lightType, processedData.additionalLightData.spotLightShape, processedData.additionalLightData.areaLightShape,
                ref processedData.lightCategory, ref processedData.gpuLightType, ref processedData.lightVolumeType);

            processedData.isBakedShadowMask = false;
        }

        bool TrivialRejectLight(VisibleLight light, Camera hdCamera )
        {
            // We can skip the processing of lights that are so small to not affect at least a pixel on screen.
            // TODO: The minimum pixel size on screen should really be exposed as parameter, to allow small lights to be culled to user's taste.
            const int minimumPixelAreaOnScreen = 1;
            if ((light.screenRect.height * hdCamera.pixelHeight) * (light.screenRect.width * hdCamera.pixelWidth) < minimumPixelAreaOnScreen)
            {
                return true;
            }

            if (light.light != null)
                return true;

            return false;
        }
        int PreprocessVisibleLights(Camera hdCamera, CullingResults cullResults)
        {
      

            // 1. Count the number of lights and sort all lights by category, type and volume - This is required for the fptl/cluster shader code
            // If we reach maximum of lights available on screen, then we discard the light.
            // Lights are processed in order, so we don't discards light based on their importance but based on their ordering in visible lights list.
            int directionalLightcount = 0;
            int punctualLightcount = 0;
            int areaLightCount = 0;

            m_ProcessedLightData.Resize(cullResults.visibleLights.Length);

            int lightCount = Math.Min(cullResults.visibleLights.Length, m_MaxLightsOnScreen);
            UpdateSortKeysArray(lightCount);
            int sortCount = 0;
            for (int lightIndex = 0, numLights = cullResults.visibleLights.Length; (lightIndex < numLights) && (sortCount < lightCount); ++lightIndex)
            {
                var light = cullResults.visibleLights[lightIndex];

                //// First we do all the trivial rejects.
                //if (TrivialRejectLight(light, hdCamera))
                //    continue;

                // Then we compute all light data that will be reused for the rest of the light loop.
                ref ProcessedLightData processedData = ref m_ProcessedLightData[lightIndex];
                PreprocessLightData(ref processedData, light, hdCamera);

                // Then we can reject lights based on processed data.
                var additionalData = processedData.additionalLightData;

                //// If the camera is in ray tracing mode and the light is disabled in ray tracing mode, we skip this light.
                //if (hdCamera.frameSettings.IsEnabled(FrameSettingsField.RayTracing) && !additionalData.includeForRayTracing)
                //    continue;

                var lightType = processedData.lightType;
                if (ShaderConfig.s_AreaLights == 0 && (lightType == HDLightType.Area && (additionalData.areaLightShape == AreaLightShape.Rectangle || additionalData.areaLightShape == AreaLightShape.Tube)))
                    continue;

                //bool contributesToLighting = ((additionalData.lightDimmer > 0) && (additionalData.affectDiffuse || additionalData.affectSpecular)) || (additionalData.volumetricDimmer > 0);
                //contributesToLighting = contributesToLighting && (processedData.lightDistanceFade > 0);

                //if (!contributesToLighting)
                //    continue;

                // Do NOT process lights beyond the specified limit!
                switch (processedData.lightCategory)
                {
                    case LightCategory.Punctual:
                        if (processedData.gpuLightType == GPULightType.Directional) // Our directional lights are "punctual"...
                        {                         
                            directionalLightcount++;
                            break;
                        }
                     
                        punctualLightcount++;
                        break;
                    case LightCategory.Area:
                      
                        areaLightCount++;
                        break;
                    default:
                        break;
                }


                // 5 bit (0x1F) light category, 5 bit (0x1F) GPULightType, 5 bit (0x1F) lightVolume, 1 bit for shadow casting, 16 bit index
                m_SortKeys[sortCount++] = (uint)processedData.lightCategory << 27 | (uint)processedData.gpuLightType << 22 | (uint)processedData.lightVolumeType << 17 | (uint)lightIndex;
            }

            CoreUnsafeUtils.QuickSort(m_SortKeys, 0, sortCount - 1); // Call our own quicksort instead of Array.Sort(sortKeys, 0, sortCount) so we don't allocate memory (note the SortCount-1 that is different from original call).
            return sortCount;
        }
        // TODO: we should be able to do this calculation only with LightData without VisibleLight light, but for now pass both
        void GetLightVolumeDataAndBound(LightCategory lightCategory, GPULightType gpuLightType, LightVolumeType lightVolumeType,
            VisibleLight light, LightData lightData, Vector3 lightDimensions, Matrix4x4 worldToView)
        {
            // Then Culling side
            var range = lightDimensions.z;
            var lightToWorld = light.localToWorldMatrix;
            Vector3 positionWS = lightData.positionRWS;
            Vector3 positionVS = worldToView.MultiplyPoint(positionWS);

            Vector3 xAxisVS = worldToView.MultiplyVector(lightToWorld.GetColumn(0));
            Vector3 yAxisVS = worldToView.MultiplyVector(lightToWorld.GetColumn(1));
            Vector3 zAxisVS = worldToView.MultiplyVector(lightToWorld.GetColumn(2));

            // Fill bounds
            var bound = new SFiniteLightBound();
            var lightVolumeData = new LightVolumeData();

            lightVolumeData.lightCategory = (uint)lightCategory;
            lightVolumeData.lightVolume = (uint)lightVolumeType;

            if (gpuLightType == GPULightType.Spot || gpuLightType == GPULightType.ProjectorPyramid)
            {
                Vector3 lightDir = lightToWorld.GetColumn(2);

                // represents a left hand coordinate system in world space since det(worldToView)<0
                Vector3 vx = xAxisVS;
                Vector3 vy = yAxisVS;
                Vector3 vz = zAxisVS;

                var sa = light.spotAngle;
                var cs = Mathf.Cos(0.5f * sa * Mathf.Deg2Rad);
                var si = Mathf.Sin(0.5f * sa * Mathf.Deg2Rad);

                if (gpuLightType == GPULightType.ProjectorPyramid)
                {
                    Vector3 lightPosToProjWindowCorner = (0.5f * lightDimensions.x) * vx + (0.5f * lightDimensions.y) * vy + 1.0f * vz;
                    cs = Vector3.Dot(vz, Vector3.Normalize(lightPosToProjWindowCorner));
                    si = Mathf.Sqrt(1.0f - cs * cs);
                }

                const float FltMax = 3.402823466e+38F;
                var ta = cs > 0.0f ? (si / cs) : FltMax;
                var cota = si > 0.0f ? (cs / si) : FltMax;

                //const float cotasa = l.GetCotanHalfSpotAngle();

                // apply nonuniform scale to OBB of spot light
                var squeeze = true;//sa < 0.7f * 90.0f;      // arb heuristic
                var fS = squeeze ? ta : si;
                bound.center = worldToView.MultiplyPoint(positionWS + ((0.5f * range) * lightDir));    // use mid point of the spot as the center of the bounding volume for building screen-space AABB for tiled lighting.

                // scale axis to match box or base of pyramid
                bound.boxAxisX = (fS * range) * vx;
                bound.boxAxisY = (fS * range) * vy;
                bound.boxAxisZ = (0.5f * range) * vz;

                // generate bounding sphere radius
                var fAltDx = si;
                var fAltDy = cs;
                fAltDy = fAltDy - 0.5f;
                //if(fAltDy<0) fAltDy=-fAltDy;

                fAltDx *= range; fAltDy *= range;

                // Handle case of pyramid with this select (currently unused)
                var altDist = Mathf.Sqrt(fAltDy * fAltDy + (true ? 1.0f : 2.0f) * fAltDx * fAltDx);
                bound.radius = altDist > (0.5f * range) ? altDist : (0.5f * range);       // will always pick fAltDist
                bound.scaleXY = squeeze ? 0.01f : 1.0f;

                lightVolumeData.lightAxisX = vx;
                lightVolumeData.lightAxisY = vy;
                lightVolumeData.lightAxisZ = vz;
                lightVolumeData.lightPos = positionVS;
                lightVolumeData.radiusSq = range * range;
                lightVolumeData.cotan = cota;
                lightVolumeData.featureFlags = (uint)LightFeatureFlags.Punctual;
            }
            else if (gpuLightType == GPULightType.Point)
            {
                // Construct a view-space axis-aligned bounding cube around the bounding sphere.
                // This allows us to utilize the same polygon clipping technique for all lights.
                // Non-axis-aligned vectors may result in a larger screen-space AABB.
                Vector3 vx = new Vector3(1, 0, 0);
                Vector3 vy = new Vector3(0, 1, 0);
                Vector3 vz = new Vector3(0, 0, 1);

                bound.center = positionVS;
                bound.boxAxisX = vx * range;
                bound.boxAxisY = vy * range;
                bound.boxAxisZ = vz * range;
                bound.scaleXY = 1.0f;
                bound.radius = range;

                // fill up ldata
                lightVolumeData.lightAxisX = vx;
                lightVolumeData.lightAxisY = vy;
                lightVolumeData.lightAxisZ = vz;
                lightVolumeData.lightPos = bound.center;
                lightVolumeData.radiusSq = range * range;
                lightVolumeData.featureFlags = (uint)LightFeatureFlags.Punctual;
            }
            else if (gpuLightType == GPULightType.Tube)
            {
                Vector3 dimensions = new Vector3(lightDimensions.x + 2 * range, 2 * range, 2 * range); // Omni-directional
                Vector3 extents = 0.5f * dimensions;
                Vector3 centerVS = positionVS;

                bound.center = centerVS;
                bound.boxAxisX = extents.x * xAxisVS;
                bound.boxAxisY = extents.y * yAxisVS;
                bound.boxAxisZ = extents.z * zAxisVS;
                bound.radius = extents.x;
                bound.scaleXY = 1.0f;

                lightVolumeData.lightPos = centerVS;
                lightVolumeData.lightAxisX = xAxisVS;
                lightVolumeData.lightAxisY = yAxisVS;
                lightVolumeData.lightAxisZ = zAxisVS;
                lightVolumeData.boxInvRange.Set(1.0f / extents.x, 1.0f / extents.y, 1.0f / extents.z);
                lightVolumeData.featureFlags = (uint)LightFeatureFlags.Area;
            }
            else if (gpuLightType == GPULightType.Rectangle)
            {
                Vector3 dimensions = new Vector3(lightDimensions.x + 2 * range, lightDimensions.y + 2 * range, range); // One-sided
                Vector3 extents = 0.5f * dimensions;
                Vector3 centerVS = positionVS + extents.z * zAxisVS;

                float d = range + 0.5f * Mathf.Sqrt(lightDimensions.x * lightDimensions.x + lightDimensions.y * lightDimensions.y);

                bound.center = centerVS;
                bound.boxAxisX = extents.x * xAxisVS;
                bound.boxAxisY = extents.y * yAxisVS;
                bound.boxAxisZ = extents.z * zAxisVS;
                bound.radius = Mathf.Sqrt(d * d + (0.5f * range) * (0.5f * range));
                bound.scaleXY = 1.0f;

                lightVolumeData.lightPos = centerVS;
                lightVolumeData.lightAxisX = xAxisVS;
                lightVolumeData.lightAxisY = yAxisVS;
                lightVolumeData.lightAxisZ = zAxisVS;
                lightVolumeData.boxInvRange.Set(1.0f / extents.x, 1.0f / extents.y, 1.0f / extents.z);
                lightVolumeData.featureFlags = (uint)LightFeatureFlags.Area;
            }
            else if (gpuLightType == GPULightType.ProjectorBox)
            {
                Vector3 dimensions = new Vector3(lightDimensions.x, lightDimensions.y, range);  // One-sided
                Vector3 extents = 0.5f * dimensions;
                Vector3 centerVS = positionVS + extents.z * zAxisVS;

                bound.center = centerVS;
                bound.boxAxisX = extents.x * xAxisVS;
                bound.boxAxisY = extents.y * yAxisVS;
                bound.boxAxisZ = extents.z * zAxisVS;
                bound.radius = extents.magnitude;
                bound.scaleXY = 1.0f;

                lightVolumeData.lightPos = centerVS;
                lightVolumeData.lightAxisX = xAxisVS;
                lightVolumeData.lightAxisY = yAxisVS;
                lightVolumeData.lightAxisZ = zAxisVS;
                lightVolumeData.boxInvRange.Set(1.0f / extents.x, 1.0f / extents.y, 1.0f / extents.z);
                lightVolumeData.featureFlags = (uint)LightFeatureFlags.Punctual;
            }
            else if (gpuLightType == GPULightType.Disc)
            {
                //not supported at real time at the moment
            }
            else
            {
                Debug.Assert(false, "TODO: encountered an unknown GPULightType.");
            }

            //m_lightList.lightsPerView[viewIndex].bounds.Add(bound);
            //m_lightList.lightsPerView[viewIndex].lightVolumes.Add(lightVolumeData);
        }
        void PrepareGPULightdata(CommandBuffer cmd, Camera hdCamera, CullingResults cullResults, int processedLightCount)
        {
            Vector3 camPosWS = hdCamera.transform.position;

            int directionalLightcount = 0;
            int punctualLightcount = 0;
            int areaLightCount = 0;


            // 2. Go through all lights, convert them to GPU format.
            // Simultaneously create data for culling (LightVolumeData and SFiniteLightBound)

            for (int sortIndex = 0; sortIndex < processedLightCount; ++sortIndex)
            {
                // In 1. we have already classify and sorted the light, we need to use this sorted order here
                uint sortKey = m_SortKeys[sortIndex];
                LightCategory lightCategory = (LightCategory)((sortKey >> 27) & 0x1F);
                GPULightType gpuLightType = (GPULightType)((sortKey >> 22) & 0x1F);
                LightVolumeType lightVolumeType = (LightVolumeType)((sortKey >> 17) & 0x1F);
                int lightIndex = (int)(sortKey & 0xFFFF);

                var light = cullResults.visibleLights[lightIndex];
                var lightComponent = light.light;
                ProcessedLightData processedData = m_ProcessedLightData[lightIndex];
          
                // Light should always have additional data, however preview light right don't have, so we must handle the case by assigning HDUtils.s_DefaultHDAdditionalLightData
                var additionalLightData = processedData.additionalLightData;

                // Directional rendering side, it is separated as it is always visible so no volume to handle here
                if (gpuLightType == GPULightType.Directional)
                {
                    GetDirectionalLightData(cmd, hdCamera, light, lightComponent, lightIndex, -1, directionalLightcount, false);

                    directionalLightcount++;

                    // We make the light position camera-relative as late as possible in order
                    // to allow the preceding code to work with the absolute world space coordinates.
                    if (ShaderConfig.s_CameraRelativeRendering != 0)
                    {
                        // Caution: 'DirectionalLightData.positionWS' is camera-relative after this point.
                        int last = m_lightList.directionalLights.Count - 1;
                        DirectionalLightData lightData = m_lightList.directionalLights[last];
                        lightData.positionRWS -= camPosWS;
                        m_lightList.directionalLights[last] = lightData;
                    }
                }
                else
                {
                    Vector3 lightDimensions = new Vector3(); // X = length or width, Y = height, Z = range (depth)

                    // Allocate a light data
                    LightData lightData = new LightData();

                    // Punctual, area, projector lights - the rendering side.
                    GetLightData(cmd, light, in m_ProcessedLightData[lightIndex],   ref lightDimensions, ref lightData);

                    // Add the previously created light data
                    m_lightList.lights.Add(lightData);

                    switch (lightCategory)
                    {
                        case LightCategory.Punctual:
                            punctualLightcount++;
                            break;
                        case LightCategory.Area:
                            areaLightCount++;
                            break;
                        default:
                            Debug.Assert(false, "TODO: encountered an unknown LightCategory.");
                            break;
                    }

                    // Then culling side. Must be call in this order as we pass the created Light data to the function
                  //  for (int viewIndex = 0; viewIndex < hdCamera.viewCount; ++viewIndex)
                    {
                      //  GetLightVolumeDataAndBound(lightCategory, gpuLightType, lightVolumeType, light, m_lightList.lights[m_lightList.lights.Count - 1], lightDimensions, hdCamera.worldToCameraMatrix);
                    }

                    // We make the light position camera-relative as late as possible in order
                    // to allow the preceding code to work with the absolute world space coordinates.
                    if (ShaderConfig.s_CameraRelativeRendering != 0)
                    {
                        // Caution: 'LightData.positionWS' is camera-relative after this point.
                        int last = m_lightList.lights.Count - 1;
                        lightData = m_lightList.lights[last];
                        lightData.positionRWS -= camPosWS;
                        m_lightList.lights[last] = lightData;
                    }
                }
            }

            // Sanity check
            Debug.Assert(m_lightList.directionalLights.Count == directionalLightcount);
            Debug.Assert(m_lightList.lights.Count == areaLightCount + punctualLightcount);

            m_lightList.punctualLightCount = punctualLightcount;
            m_lightList.areaLightCount = areaLightCount;
        }
        void PushLightDataGlobalParams(CommandBuffer cmd)
        {
            m_LightLoopLightData.directionalLightData.SetData(m_lightList.directionalLights);
            m_LightLoopLightData.lightData.SetData(m_lightList.lights);
          //  m_LightLoopLightData.envLightData.SetData(m_lightList.envLights);
          //  m_LightLoopLightData.decalData.SetData(DecalSystem.m_DecalDatas, 0, 0, Math.Min(DecalSystem.m_DecalDatasCount, m_MaxDecalsOnScreen)); // don't add more than the size of the buffer

            // These two buffers have been set in Rebuild(). At this point, view 0 contains combined data from all views
         //   m_TileAndClusterData.convexBoundsBuffer.SetData(m_lightList.lightsPerView[0].bounds);
          //  m_TileAndClusterData.lightVolumeDataBuffer.SetData(m_lightList.lightsPerView[0].lightVolumes);

            ////cmd.SetGlobalTexture(HDShaderIDs._CookieAtlas, m_TextureCaches.lightCookieManager.atlasTexture);
            ////cmd.SetGlobalTexture(HDShaderIDs._EnvCubemapTextures, m_TextureCaches.reflectionProbeCache.GetTexCache());
            ////cmd.SetGlobalTexture(HDShaderIDs._Env2DTextures, m_TextureCaches.reflectionPlanarProbeCache.GetTexCache());

            cmd.SetGlobalBuffer(HDShaderIDs._LightDatas, m_LightLoopLightData.lightData);
          //  cmd.SetGlobalBuffer(HDShaderIDs._EnvLightDatas, m_LightLoopLightData.envLightData);
          //  cmd.SetGlobalBuffer(HDShaderIDs._DecalDatas, m_LightLoopLightData.decalData);
            cmd.SetGlobalBuffer(HDShaderIDs._DirectionalLightDatas, m_LightLoopLightData.directionalLightData);
        }


        unsafe void UpdateShaderVariablesGlobalLightLoop(CommandBuffer cmd)
        {
            // Light info
            cmd.SetGlobalInt("_PunctualLightCount", (int)m_lightList.punctualLightCount);
            cmd.SetGlobalInt("_DirectionalLightCount", (int)m_lightList.directionalLights.Count);
            cmd.SetGlobalInt("_AreaLightCount", (int)m_lightList.areaLightCount);
            cmd.SetGlobalInt("_EnvLightCount", (int)m_lightList.envLights.Count);
       
        }
        public bool PrepareLightsForGPU(CommandBuffer cmd, Camera hdCamera, CullingResults cullResults)
        {
            //var debugLightFilter = debugDisplaySettings.GetDebugLightFilterMode();
    

          

            using (new ProfilingScope(cmd, ProfilingSampler.Get(HDProfileId.PrepareLightsForGPU)))
            {
                Camera camera = hdCamera;

                // If any light require it, we need to enabled bake shadow mask feature
      

                m_lightList.Clear();

                // We need to properly reset this here otherwise if we go from 1 light to no visible light we would keep the old reference active.
                m_CurrentSunLight = null;
                m_CurrentSunLightAdditionalLightData = null;




                // Note: Light with null intensity/Color are culled by the C++, no need to test it here
                if (cullResults.visibleLights.Length != 0)
                {
                    int processedLightCount = PreprocessVisibleLights(hdCamera, cullResults);

                    // In case ray tracing supported and a light cluster is built, we need to make sure to reserve all the cookie slots we need
                    //if (m_RayTracingSupported)
                    //    ReserveRayTracingCookieAtlasSlots();

                    PrepareGPULightdata(cmd, hdCamera, cullResults, processedLightCount);

                }

                m_TotalLightCount = m_lightList.lights.Count ;

                // Aggregate the remaining views into the first entry of the list (view 0)
                //for (int viewIndex = 1; viewIndex < hdCamera.viewCount; ++viewIndex)
                //{
                //    Debug.Assert(m_lightList.lightsPerView[viewIndex].bounds.Count == m_TotalLightCount);
                //    m_lightList.lightsPerView[0].bounds.AddRange(m_lightList.lightsPerView[viewIndex].bounds);

                //    Debug.Assert(m_lightList.lightsPerView[viewIndex].lightVolumes.Count == m_TotalLightCount);
                //    m_lightList.lightsPerView[0].lightVolumes.AddRange(m_lightList.lightsPerView[viewIndex].lightVolumes);
                //}
                UpdateShaderVariablesGlobalLightLoop(cmd);
                PushLightDataGlobalParams(cmd);

            }


            return false;
        }
    }
}

// Memo used when debugging to remember order of dispatch and value
// GenerateLightsScreenSpaceAABBs
// cmd.DispatchCompute(parameters.screenSpaceAABBShader, parameters.screenSpaceAABBKernel, (parameters.totalLightCount + 7) / 8, parameters.viewCount, 1);
// BigTilePrepass(ScreenX / 64, ScreenY / 64)
// cmd.DispatchCompute(parameters.bigTilePrepassShader, parameters.bigTilePrepassKernel, parameters.numBigTilesX, parameters.numBigTilesY, parameters.viewCount);
// BuildPerTileLightList(ScreenX / 16, ScreenY / 16)
// cmd.DispatchCompute(parameters.buildPerTileLightListShader, parameters.buildPerTileLightListKernel, parameters.numTilesFPTLX, parameters.numTilesFPTLY, parameters.viewCount);
// VoxelLightListGeneration(ScreenX / 32, ScreenY / 32)
// cmd.DispatchCompute(parameters.buildPerVoxelLightListShader, s_ClearVoxelAtomicKernel, 1, 1, 1);
// cmd.DispatchCompute(parameters.buildPerVoxelLightListShader, parameters.buildPerVoxelLightListKernel, parameters.numTilesClusterX, parameters.numTilesClusterY, parameters.viewCount);
// buildMaterialFlags (ScreenX / 16, ScreenY / 16)
// cmd.DispatchCompute(parameters.buildMaterialFlagsShader, buildMaterialFlagsKernel, parameters.numTilesFPTLX, parameters.numTilesFPTLY, parameters.viewCount);
// cmd.DispatchCompute(parameters.clearDispatchIndirectShader, s_ClearDispatchIndirectKernel, 1, 1, 1);
// BuildDispatchIndirectArguments
// cmd.DispatchCompute(parameters.buildDispatchIndirectShader, s_BuildDispatchIndirectKernel, (parameters.numTilesFPTL + k_ThreadGroupOptimalSize - 1) / k_ThreadGroupOptimalSize, 1, parameters.viewCount);
// Then dispatch indirect will trigger the number of tile for a variant x4 as we process by wavefront of 64 (16x16 => 4 x 8x8)

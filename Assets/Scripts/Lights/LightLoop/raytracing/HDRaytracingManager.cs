using System.Collections.Generic;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Experimental.Rendering.RenderGraphModule;

namespace UnityEngine.Rendering.HighDefinition
{
    [GenerateHLSL]
    internal enum RayTracingRendererFlag
    {
        Opaque = 0x01,
        CastShadowTransparent = 0x02,
        CastShadowOpaque = 0x04,
        CastShadow = CastShadowOpaque | CastShadowTransparent,
        AmbientOcclusion = 0x08,
        Reflection = 0x10,
        GlobalIllumination = 0x20,
        RecursiveRendering = 0x40,
        PathTracing = 0x80
    }

    internal enum AccelerationStructureStatus
    {
        Clear = 0x0,
        Added = 0x1,
        Excluded = 0x02,
        TransparencyIssue = 0x04,
        NullMaterial = 0x08,
        MissingMesh = 0x10
    }

   public class HDRayTracingLights
    {
        // The list of non-directional lights in the sub-scene
        public List<HDAdditionalLightData> hdPointLightArray = new List<HDAdditionalLightData>();
        public List<HDAdditionalLightData> hdLineLightArray = new List<HDAdditionalLightData>();
        public List<HDAdditionalLightData> hdRectLightArray = new List<HDAdditionalLightData>();
        public List<HDAdditionalLightData> hdLightArray = new List<HDAdditionalLightData>();

        // The list of directional lights in the sub-scene
        public List<HDAdditionalLightData> hdDirectionalLightArray = new List<HDAdditionalLightData>();



        // Counter of the current number of lights
        public int lightCount;
    }

    public partial class HDRenderPipeline
    {
        // Data used for runtime evaluation
        RayTracingAccelerationStructure m_CurrentRAS = new RayTracingAccelerationStructure();
        public HDRaytracingLightCluster m_RayTracingLightCluster;
        HDRayTracingLights m_RayTracingLights = new HDRayTracingLights();
        bool m_ValidRayTracingState = false;
        bool m_ValidRayTracingCluster = false;
        bool m_ValidRayTracingClusterCulling = false;

        //// Ray-count manager data
        //RayCountManager m_RayCountManager;

        const int maxNumSubMeshes = 32;
        Dictionary<int, int> m_RayTracingRendererReference = new Dictionary<int, int>();
        bool[] subMeshFlagArray = new bool[maxNumSubMeshes];
        bool[] subMeshCutoffArray = new bool[maxNumSubMeshes];
        bool[] subMeshTransparentArray = new bool[maxNumSubMeshes];
        ReflectionProbe reflectionProbe = new ReflectionProbe();
        List<Material> materialArray = new List<Material>(maxNumSubMeshes);
        Dictionary<int, bool> m_ShaderValidityCache = new Dictionary<int, bool>();

        // Used to detect material and transform changes for Path Tracing
        Dictionary<int, int> m_MaterialCRCs = new Dictionary<int, int>();
        bool m_MaterialsDirty = false;
        bool m_TransformDirty = false;

        ShaderVariablesRaytracingLightLoop m_ShaderVariablesRaytracingLightLoopCB = new ShaderVariablesRaytracingLightLoop();

        internal void InitRayTracingManager(HDRenderPipelineRayTracingResources renderPipelineRayTracingResources)
        {
            // Init the ray count manager
            //m_RayCountManager = new RayCountManager();
            //m_RayCountManager.Init(m_Asset.renderPipelineRayTracingResources);

            // Build the light cluster
            m_RayTracingLightCluster = new HDRaytracingLightCluster();
            m_RayTracingLightCluster.Initialize(renderPipelineRayTracingResources,this);
        }

        internal void ReleaseRayTracingManager()
        {
            if (m_RayTracingLightCluster != null)
                m_RayTracingLightCluster.ReleaseResources();
        }

        bool IsValidRayTracedMaterial(Material currentMaterial)
        {
           
                return false;
        }



        AccelerationStructureStatus AddInstanceToRAS(Renderer currentRenderer)
        {
            // Get all the materials of the mesh renderer
            currentRenderer.GetSharedMaterials(materialArray);
            // If the array is null, we are done
            if (materialArray == null) return AccelerationStructureStatus.NullMaterial;

            // For every sub-mesh/sub-material let's build the right flags
            int numSubMeshes = 1;
            if (!(currentRenderer.GetType() == typeof(SkinnedMeshRenderer)))
            {
                currentRenderer.TryGetComponent(out MeshFilter meshFilter);
                if (meshFilter == null || meshFilter.sharedMesh == null) return AccelerationStructureStatus.MissingMesh;
                numSubMeshes = meshFilter.sharedMesh.subMeshCount;
            }
            else
            {
                SkinnedMeshRenderer skinnedMesh = (SkinnedMeshRenderer)currentRenderer;
                if (skinnedMesh.sharedMesh == null) return AccelerationStructureStatus.MissingMesh;
                numSubMeshes = skinnedMesh.sharedMesh.subMeshCount;
            }

            // Let's clamp the number of sub-meshes to avoid throwing an unwated error
            numSubMeshes = Mathf.Min(numSubMeshes, maxNumSubMeshes);

            // Get the layer of this object
            int objectLayerValue = 1 << currentRenderer.gameObject.layer;

            // We need to build the instance flag for this renderer
            uint instanceFlag = 0x00;

            bool doubleSided = false;
            bool materialIsOnlyTransparent = true;
            bool hasTransparentSubMaterial = false;


            for (int meshIdx = 0; meshIdx < numSubMeshes; ++meshIdx)
            {
                // Initially we consider the potential mesh as invalid
                bool validMesh = false;
                if (materialArray.Count > meshIdx)
                {
                    // Grab the material for the current sub-mesh
                    Material currentMaterial = materialArray[meshIdx];

                    // Make sure that the material is HDRP's and non-decal
                    if (IsValidRayTracedMaterial(currentMaterial))
                    {
                        // Mesh is valid given that all requirements are ok
                        validMesh = true;
                        subMeshFlagArray[meshIdx] = true;

                        // Is the sub material transparent?
                        //subMeshTransparentArray[meshIdx] = currentMaterial.IsKeywordEnabled("_SURFACE_TYPE_TRANSPARENT")
                        //    || (HDRenderQueue.k_RenderQueue_Transparent.lowerBound <= currentMaterial.renderQueue
                        //        && HDRenderQueue.k_RenderQueue_Transparent.upperBound >= currentMaterial.renderQueue);

                        // Aggregate the transparency info
                        materialIsOnlyTransparent &= subMeshTransparentArray[meshIdx];
                        hasTransparentSubMaterial |= subMeshTransparentArray[meshIdx];

                        //// Is the material alpha tested?
                        //subMeshCutoffArray[meshIdx] = currentMaterial.IsKeywordEnabled("_ALPHATEST_ON")
                        //    || (HDRenderQueue.k_RenderQueue_OpaqueAlphaTest.lowerBound <= currentMaterial.renderQueue
                        //        && HDRenderQueue.k_RenderQueue_OpaqueAlphaTest.upperBound >= currentMaterial.renderQueue);

                        // Check if we want to enable double-sidedness for the mesh
                        // (note that a mix of single and double-sided materials will result in a double-sided mesh in the AS)
                        doubleSided |= currentMaterial.doubleSidedGI || currentMaterial.IsKeywordEnabled("_DOUBLESIDED_ON");

                        // Check if the material has changed since last time we were here
                        if (!m_MaterialsDirty)
                        {
                            int matId = currentMaterial.GetInstanceID();
                            int matPrevCRC, matCurCRC = currentMaterial.ComputeCRC();
                            if (m_MaterialCRCs.TryGetValue(matId, out matPrevCRC))
                            {
                                m_MaterialCRCs[matId] = matCurCRC;
                                m_MaterialsDirty |= (matCurCRC != matPrevCRC);
                            }
                            else
                            {
                                m_MaterialCRCs.Add(matId, matCurCRC);
                            }
                        }
                    }
                }

                // If the mesh was not valid, exclude it (without affecting sidedness)
                if (!validMesh)
                {
                    subMeshFlagArray[meshIdx] = false;
                    subMeshCutoffArray[meshIdx] = false;
                }
            }

            // If the material is considered opaque, but has some transparent sub-materials
            if (!materialIsOnlyTransparent && hasTransparentSubMaterial)
            {
                for (int meshIdx = 0; meshIdx < numSubMeshes; ++meshIdx)
                {
                    subMeshCutoffArray[meshIdx] = subMeshTransparentArray[meshIdx] ? true : subMeshCutoffArray[meshIdx];
                }
            }

            // Propagate the opacity mask only if all sub materials are opaque
            bool isOpaque = !hasTransparentSubMaterial;
            if (isOpaque)
            {
                instanceFlag |= (uint)(RayTracingRendererFlag.Opaque);
            }

      
            {
                if (hasTransparentSubMaterial)
                {
                    // Raise the shadow casting flag if needed
                    instanceFlag |= ((currentRenderer.shadowCastingMode != ShadowCastingMode.Off) ? (uint)(RayTracingRendererFlag.CastShadowTransparent) : 0x00);
                }
                else
                {
                    // Raise the shadow casting flag if needed
                    instanceFlag |= ((currentRenderer.shadowCastingMode != ShadowCastingMode.Off) ? (uint)(RayTracingRendererFlag.CastShadowOpaque) : 0x00);
                }
            }

            // We consider a mesh visible by reflection, gi, etc if it is not in the shadow only mode.
            bool meshIsVisible = currentRenderer.shadowCastingMode != ShadowCastingMode.ShadowsOnly;

            if ( meshIsVisible)
            {
                // Raise the Path Tracing flag if needed
                instanceFlag |= (uint)(RayTracingRendererFlag.PathTracing);
            }

            // If the object was not referenced
            if (instanceFlag == 0) return AccelerationStructureStatus.Added;

            // Add it to the acceleration structure
            m_CurrentRAS.AddInstance(currentRenderer, subMeshMask: subMeshFlagArray, subMeshTransparencyFlags: subMeshCutoffArray, enableTriangleCulling: !doubleSided, mask: instanceFlag);

            // Indicates that a transform has changed in our scene (mesh or light)
            m_TransformDirty |= currentRenderer.transform.hasChanged;
            currentRenderer.transform.hasChanged = false;

            // return the status
            return (!materialIsOnlyTransparent && hasTransparentSubMaterial) ? AccelerationStructureStatus.TransparencyIssue : AccelerationStructureStatus.Added;
        }

        internal void BuildRayTracingAccelerationStructure(Camera hdCamera)
        {
            // Clear all the per frame-data
            m_RayTracingRendererReference.Clear();
            m_RayTracingLights.hdDirectionalLightArray.Clear();
            m_RayTracingLights.hdPointLightArray.Clear();
            m_RayTracingLights.hdLineLightArray.Clear();
            m_RayTracingLights.hdRectLightArray.Clear();
            m_RayTracingLights.hdLightArray.Clear();
 //           m_RayTracingLights.reflectionProbeArray.Clear();
            m_RayTracingLights.lightCount = 0;
            m_CurrentRAS.Dispose();
            m_CurrentRAS = new RayTracingAccelerationStructure();
            m_ValidRayTracingState = false;
            m_ValidRayTracingCluster = false;
            m_ValidRayTracingClusterCulling = false;

            // fetch all the lights in the scene
            HDAdditionalLightData[] hdLightArray = UnityEngine.GameObject.FindObjectsOfType<HDAdditionalLightData>();

            for (int lightIdx = 0; lightIdx < hdLightArray.Length; ++lightIdx)
            {
                HDAdditionalLightData hdLight = hdLightArray[lightIdx];
                if (hdLight.enabled)
                {
                    // Indicates that a transform has changed in our scene (mesh or light)
                    m_TransformDirty |= hdLight.transform.hasChanged;
                    hdLight.transform.hasChanged = false;

                    switch (hdLight.type)
                    {
                        case HDLightType.Directional:
                            m_RayTracingLights.hdDirectionalLightArray.Add(hdLight);
                            break;
                        case HDLightType.Point:
                        case HDLightType.Spot:
                            m_RayTracingLights.hdPointLightArray.Add(hdLight);
                            break;
                        case HDLightType.Area:
                            switch (hdLight.areaLightShape)
                            {
                                case AreaLightShape.Rectangle:
                                    m_RayTracingLights.hdRectLightArray.Add(hdLight);
                                    break;
                                case AreaLightShape.Tube:
                                    m_RayTracingLights.hdLineLightArray.Add(hdLight);
                                    break;
                                    //TODO: case AreaLightShape.Disc:
                            }
                            break;
                    }
                }
            }

            m_RayTracingLights.hdLightArray.AddRange(m_RayTracingLights.hdPointLightArray);
            m_RayTracingLights.hdLightArray.AddRange(m_RayTracingLights.hdLineLightArray);
            m_RayTracingLights.hdLightArray.AddRange(m_RayTracingLights.hdRectLightArray);



            m_RayTracingLights.lightCount = m_RayTracingLights.hdPointLightArray.Count
                + m_RayTracingLights.hdLineLightArray.Count
                + m_RayTracingLights.hdRectLightArray.Count;


           // PathTracing pathTracingSettings = hdCamera.volumeStack.GetComponent<PathTracing>();
            bool ptEnabled = true;

            // We need to check if we should be building the ray tracing acceleration structure (if required by any effect)
            bool rayTracingRequired = ptEnabled;
            if (!rayTracingRequired)
                return;

            // We need to process the emissive meshes of the rectangular area lights
            for (var i = 0; i < m_RayTracingLights.hdRectLightArray.Count; i++)
            {
                // Fetch the current renderer of the rectangular area light (if any)
                MeshRenderer currentRenderer = m_RayTracingLights.hdRectLightArray[i].emissiveMeshRenderer;

                // If there is none it means that there is no emissive mesh for this light
                if (currentRenderer == null) continue;

                // This objects should be included into the RAS
                AddInstanceToRAS(currentRenderer);
            }

            int matCount = m_MaterialCRCs.Count;

            LODGroup[] lodGroupArray = UnityEngine.GameObject.FindObjectsOfType<LODGroup>();
            for (var i = 0; i < lodGroupArray.Length; i++)
            {
                // Grab the current LOD group
                LODGroup lodGroup = lodGroupArray[i];

                // Get the set of LODs
                LOD[] lodArray = lodGroup.GetLODs();
                for (int lodIdx = 0; lodIdx < lodArray.Length; ++lodIdx)
                {
                    LOD currentLOD = lodArray[lodIdx];
                    // We only want to push to the acceleration structure the lod0, we do not have defined way to select the right LOD at the moment
                    if (lodIdx == 0)
                    {
                        for (int rendererIdx = 0; rendererIdx < currentLOD.renderers.Length; ++rendererIdx)
                        {
                            // Fetch the renderer that we are interested in
                            Renderer currentRenderer = currentLOD.renderers[rendererIdx];

                            // This objects should but included into the RAS
                            AddInstanceToRAS(currentRenderer);
                        }
                    }

                    // Add them to the processed set so that they are not taken into account when processing all the renderers
                    for (int rendererIdx = 0; rendererIdx < currentLOD.renderers.Length; ++rendererIdx)
                    {
                        Renderer currentRenderer = currentLOD.renderers[rendererIdx];
                        if (currentRenderer == null) continue;

                        // Add this fella to the renderer list
                        // Unfortunately, we need to check that this renderer was not already pushed into the list (happens if the user uses the same mesh renderer
                        // for two LODs)
                        if (!m_RayTracingRendererReference.ContainsKey(currentRenderer.GetInstanceID()))
                            m_RayTracingRendererReference.Add(currentRenderer.GetInstanceID(), 1);
                    }
                }
            }

            // Grab all the renderers from the scene
            var rendererArray = UnityEngine.GameObject.FindObjectsOfType<Renderer>();
            for (var i = 0; i < rendererArray.Length; i++)
            {
                // Fetch the current renderer
                Renderer currentRenderer = rendererArray[i];

                // If it is not active skip it
                if (currentRenderer.enabled == false) continue;

                // Grab the current game object
                GameObject gameObject = currentRenderer.gameObject;

                // Has this object already been processed, just skip it
                if (m_RayTracingRendererReference.ContainsKey(currentRenderer.GetInstanceID()))
                {
                    continue;
                }

                // Does this object have a reflection probe component? if yes we do not want to have it in the acceleration structure
                if (gameObject.TryGetComponent<ReflectionProbe>(out reflectionProbe)) continue;

                // This objects should be included into the RAS
                AddInstanceToRAS(currentRenderer);
            }

            // Check if the amount of materials being tracked has changed
            m_MaterialsDirty |= (matCount != m_MaterialCRCs.Count);

            //if (ShaderConfig.s_CameraRelativeRendering != 0)
            //    m_CurrentRAS.Build(hdCamera.camera.transform.position);
            //else
                m_CurrentRAS.Build();

            // tag the structures as valid
            m_ValidRayTracingState = true;
        }

  //      static internal bool ValidRayTracingHistory(Camera hdCamera)
      //  {
            //return hdCamera.historyRTHandleProperties.previousViewportSize.x == hdCamera.pixelWidth
            //    && hdCamera.historyRTHandleProperties.previousViewportSize.y == hdCamera.pixelHeight;
    //    }
        internal void CullForRayTracing(CommandBuffer cmd, Camera hdCamera)
        {
           // if (m_ValidRayTracingState)
            {
                m_RayTracingLightCluster.CullForRayTracing(hdCamera, m_RayTracingLights);
                m_ValidRayTracingClusterCulling = true;
            }
        }

        internal void ReserveRayTracingCookieAtlasSlots()
        {
            if (m_ValidRayTracingState && m_ValidRayTracingClusterCulling)
            {
                m_RayTracingLightCluster.ReserveCookieAtlasSlots(m_RayTracingLights);
            }
        }

        internal void BuildRayTracingLightData(CommandBuffer cmd, Camera hdCamera)
        {
         //   if (m_ValidRayTracingState && m_ValidRayTracingClusterCulling)
            {
                m_RayTracingLightCluster.BuildRayTracingLightData(cmd, hdCamera, m_RayTracingLights);
                m_ValidRayTracingCluster = true;

                UpdateShaderVariablesRaytracingLightLoopCB(hdCamera, cmd);

                m_RayTracingLightCluster.BuildLightClusterBuffer(cmd, m_RayTracingLights);
            }
        }

        static internal float EvaluateHistoryValidity(Camera hdCamera)
        {
            float historyValidity = 1.0f;
#if UNITY_HDRP_DXR_TESTS_DEFINE
            if (Application.isPlaying)
                historyValidity = 0.0f;
            else
#endif
            // We need to check if something invalidated the history buffers
           // historyValidity *= ValidRayTracingHistory(hdCamera) ? 1.0f : 0.0f;
            return historyValidity;
        }

        void UpdateShaderVariablesRaytracingLightLoopCB(Camera hdCamera, CommandBuffer cmd)
        {
            m_ShaderVariablesRaytracingLightLoopCB._MinClusterPos = m_RayTracingLightCluster.GetMinClusterPos();
            m_ShaderVariablesRaytracingLightLoopCB._LightPerCellCount = (uint)m_RayTracingLightCluster.GetLightPerCellCount();
            m_ShaderVariablesRaytracingLightLoopCB._MaxClusterPos = m_RayTracingLightCluster.GetMaxClusterPos();
            m_ShaderVariablesRaytracingLightLoopCB._PunctualLightCountRT = (uint)m_RayTracingLightCluster.GetPunctualLightCount();
            m_ShaderVariablesRaytracingLightLoopCB._AreaLightCountRT = (uint)m_RayTracingLightCluster.GetAreaLightCount();
            m_ShaderVariablesRaytracingLightLoopCB._EnvLightCountRT = (uint)m_RayTracingLightCluster.GetEnvLightCount();

            ConstantBuffer.PushGlobal(cmd, m_ShaderVariablesRaytracingLightLoopCB, HDShaderIDs._ShaderVariablesRaytracingLightLoop);
        }



        internal RayTracingAccelerationStructure RequestAccelerationStructure()
        {
            if (m_ValidRayTracingState)
            {
                return m_CurrentRAS;
            }
            return null;
        }

        internal HDRaytracingLightCluster RequestLightCluster()
        {
            if (m_ValidRayTracingCluster)
            {
                return m_RayTracingLightCluster;
            }
            return null;
        }



        static internal bool rayTracingSupportedBySystem
            => UnityEngine.SystemInfo.supportsRayTracing
#if UNITY_EDITOR
            && (UnityEditor.EditorUserBuildSettings.activeBuildTarget == UnityEditor.BuildTarget.StandaloneWindows64
                || UnityEditor.EditorUserBuildSettings.activeBuildTarget == UnityEditor.BuildTarget.StandaloneWindows)
#endif
        ;


        internal bool GetRayTracingState()
        {
            return m_ValidRayTracingState;
        }

        internal bool GetRayTracingClusterState()
        {
            return m_ValidRayTracingCluster;
        }

        static internal float GetPixelSpreadTangent(float fov, int width, int height)
        {
            return Mathf.Tan(fov * Mathf.Deg2Rad * 0.5f) * 2.0f / Mathf.Min(width, height);
        }

        static internal float GetPixelSpreadAngle(float fov, int width, int height)
        {
            return Mathf.Atan(GetPixelSpreadTangent(fov, width, height));
        }

      //  internal TextureHandle EvaluateHistoryValidationBuffer(RenderGraph renderGraph, Camera hdCamera, TextureHandle depthBuffer, TextureHandle normalBuffer, TextureHandle motionVectorsBuffer)
      //  {
            //// Grab the temporal filter
            //HDTemporalFilter temporalFilter = GetTemporalFilter();

            //// If the temporal filter is valid use it, otherwise return a white texture
            //if (temporalFilter != null)
            //{
            //    float historyValidity = EvaluateHistoryValidity(hdCamera);
            //    HistoryValidityParameters parameters = temporalFilter.PrepareHistoryValidityParameters(hdCamera, historyValidity);
            //    return temporalFilter.HistoryValidity(renderGraph, hdCamera, parameters, depthBuffer, normalBuffer, motionVectorsBuffer);
            //}
            //else
            //    return renderGraph.defaultResources.whiteTexture;
       // }
    }
}

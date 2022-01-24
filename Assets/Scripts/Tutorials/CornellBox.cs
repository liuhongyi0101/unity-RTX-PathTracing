using UnityEngine;
using Unity.Mathematics;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;
/// <summary>
/// the cornell box.
/// </summary>
public  static class VisibleLightExtensionMethods
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
    output.Forward = matrix.GetColumn(2);
    output.Up = matrix.GetColumn(1);
    output.Right = matrix.GetColumn(0);
    return output;
}
    }
public class CornellBox : RayTracingTutorial
{
  /// <summary>
  /// the focus camera shader parameters
  /// </summary>
  private static class FocusCameraShaderParams
  {
    public static readonly int _FocusCameraLeftBottomCorner = Shader.PropertyToID("_FocusCameraLeftBottomCorner");
    public static readonly int _FocusCameraRight = Shader.PropertyToID("_FocusCameraRight");
    public static readonly int _FocusCameraUp = Shader.PropertyToID("_FocusCameraUp");
    public static readonly int _FocusCameraSize = Shader.PropertyToID("_FocusCameraSize");
    public static readonly int _FocusCameraHalfAperture = Shader.PropertyToID("_FocusCameraHalfAperture");
  }

  private readonly int _PRNGStatesShaderId = Shader.PropertyToID("_PRNGStates");

    HDRenderPipeline hDRenderPipeline;
  /// <summary>
  /// the frame index.
  /// </summary>
  private int _frameIndex = 0;
    public Material mat;
  private readonly int _frameIndexShaderId = Shader.PropertyToID("_FrameIndex");
  public Vector3 leftBottomCorner;
  public Vector3 rightTopCorner;
  public Vector2 size;
    internal void BindDitheredRNGData8SPP(CommandBuffer cmd)
    {
        cmd.SetGlobalTexture("_OwenScrambledTexture", _asset.owenScrambled256Tex);
        cmd.SetGlobalTexture("_ScramblingTileXSPP", _asset.scramblingTile8SPP);
        cmd.SetGlobalTexture("_RankingTileXSPP", _asset.rankingTile8SPP);
        cmd.SetGlobalTexture("_ScramblingTexture", _asset.scramblingTex);
        cmd.SetGlobalInt(_frameIndexShaderId, _frameIndex);
        cmd.SetGlobalInt("_FogEnabled", _asset.EnableFog == true ? 1 : 0) ;

        cmd.SetGlobalVector("_HeightFogBaseScattering", _asset._HeightFogBaseExtinction * _asset._FogColor);

        cmd.SetGlobalFloat("_HeightFogBaseExtinction", _asset._HeightFogBaseExtinction);
        cmd.SetGlobalFloat("_HeightFogBaseHeight", _asset._HeightFogBaseHeight);
        cmd.SetGlobalFloat("_MaxFogDistance", _asset._MaxFogDistance);

        float layerDepth = Mathf.Max(0.01f, _asset._MaximumHeight - _asset._HeightFogBaseHeight);
        float H = layerDepth  * 0.144765f;

        cmd.SetGlobalVector("_HeightFogExponents", new Vector2(1/H,H));

        cmd.SetGlobalFloat("_AngularDiameter", _asset.AngularDiameter * Mathf.Deg2Rad);
    }
    /// <summary>
    /// constructor.
    /// </summary>
    /// <param name="asset">the tutorial asset.</param>
  public CornellBox(RayTracingTutorialAsset asset) : base(asset)
  {
        hDRenderPipeline = new HDRenderPipeline();
        hDRenderPipeline.InitRayTracingManager(asset.PipelineRayTracingResources);
        hDRenderPipeline.InitializeLightLoop();
    }

  /// <summary>
  /// render.
  /// </summary>
  /// <param name="context">the render context.</param>
  /// <param name="camera">the camera.</param>
  public override void Render(ScriptableRenderContext context, Camera camera)
  {
    base.Render(context, camera);
        var outputTarget13 = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0);
        var cmd = CommandBufferPool.Get(typeof(MotionBlur).Name);
        CullingResults cullingResults;
        if (camera.TryGetCullingParameters(out ScriptableCullingParameters p))
        {
            cullingResults = context.Cull(ref p);

        }
        else
        {
            return;
        }
        mat = new Material(Shader.Find("Hidden/tyiop"));
        //var cmdxx = CommandBufferPool.Get("BuildRayTracingLightData");
        using (new ProfilingSample(cmd, "RayTracingLightCluster"))
        {
            hDRenderPipeline.BuildRayTracingAccelerationStructure(camera);
            hDRenderPipeline.CullForRayTracing(cmd, camera);
            hDRenderPipeline.PrepareLightsForGPU(cmd, camera, cullingResults);
            hDRenderPipeline.BuildRayTracingLightData(cmd, camera);


            // LightLoop data
            cmd.SetGlobalBuffer(HDShaderIDs._RaytracingLightCluster, hDRenderPipeline.m_RayTracingLightCluster.GetCluster());
            cmd.SetGlobalBuffer(HDShaderIDs._LightDatasRT, hDRenderPipeline.m_RayTracingLightCluster.GetLightDatas());
            cmd.Blit(null, outputTarget13, mat);
        }
      //  context.ExecuteCommandBuffer(cmd);
        var focusCamera = camera.GetComponent<FocusCamera>();
    //if (null == focusCamera)
    //  return;

    var outputTarget = RequireOutputTarget(camera);
    var outputTarget12 = RenderTexture.GetTemporary( camera.pixelWidth,camera.pixelHeight,0);
    var outputTargetSize = RequireOutputTargetSize(camera);

    var accelerationStructure = _pipeline.RequestAccelerationStructure();
    var PRNGStates = _pipeline.RequirePRNGStates(camera);

    
  // try
    {
      if (_frameIndex < 10000)
      {
        using (new ProfilingSample(cmd, "RayTracing"))
        {
                    cmd.SetRayTracingVectorParam(_shader, FocusCameraShaderParams._FocusCameraRight, camera.transform.right);
                    cmd.SetRayTracingVectorParam(_shader, FocusCameraShaderParams._FocusCameraUp, camera.transform.up);

                    var theta = camera.fieldOfView * Mathf.Deg2Rad;
                    var halfHeight = math.tan(theta * 0.5f);


                    var halfWidth = camera.aspect * halfHeight;
                    leftBottomCorner = camera.transform.position + camera.transform.forward * _asset.focusDistance -
                                       camera.transform.right * _asset.focusDistance * halfWidth -
                                       camera.transform.up * _asset.focusDistance * halfHeight;
                    size = new Vector2(_asset.focusDistance * halfWidth * 2.0f, _asset.focusDistance * halfHeight * 2.0f);
                    rightTopCorner = leftBottomCorner + camera.transform.right * size.x + camera.transform.up * size.y;
                
                    {
                        cmd.SetRayTracingVectorParam(_shader, FocusCameraShaderParams._FocusCameraLeftBottomCorner, leftBottomCorner);
                        cmd.SetRayTracingVectorParam(_shader, FocusCameraShaderParams._FocusCameraSize, size);
                        cmd.SetRayTracingFloatParam(_shader, FocusCameraShaderParams._FocusCameraHalfAperture, _asset.aperture * 0.5f);
                    }
          cmd.SetRayTracingShaderPass(_shader, "RayTracing");
          cmd.SetRayTracingAccelerationStructure(_shader, _pipeline.accelerationStructureShaderId,accelerationStructure);
          cmd.SetRayTracingIntParam(_shader, _frameIndexShaderId, _frameIndex);
          
           BindDitheredRNGData8SPP(cmd);
          cmd.SetRayTracingBufferParam(_shader, _PRNGStatesShaderId, PRNGStates);
          cmd.SetRayTracingTextureParam(_shader, _outputTargetShaderId, outputTarget);
          cmd.SetRayTracingTextureParam(_shader, "_cubemap", _asset.mp);
          cmd.SetRayTracingVectorParam(_shader, _outputTargetSizeShaderId, outputTargetSize);
          cmd.DispatchRays(_shader, "CornellBoxGenShader", (uint) outputTarget.rt.width,
            (uint) outputTarget.rt.height, 1, camera);
        }

        context.ExecuteCommandBuffer(cmd);
        if (camera.cameraType == CameraType.Game)
          _frameIndex++;
      }

            cmd.Clear();
       using (new ProfilingSample(cmd, "Finappp"))
       {
         mat = new Material(Shader.Find("Hidden/tyiop"));
         cmd.Blit(outputTarget, outputTarget12,mat);
       }


      using (new ProfilingSample(cmd, "FinalBlit"))
      {
        cmd.Blit(outputTarget12, BuiltinRenderTextureType.CameraTarget);
      }

      context.ExecuteCommandBuffer(cmd);
    }
   // finally
    {
     
      CommandBufferPool.Release(cmd);
    }
        RenderTexture.ReleaseTemporary(outputTarget12);
        RenderTexture.ReleaseTemporary(outputTarget13);
  }
}

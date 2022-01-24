using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering.HighDefinition;
/// <summary>
/// the ray tracing tutorial asset.
/// </summary>
public abstract class RayTracingTutorialAsset : ScriptableObject
{
  /// <summary>
  /// the ray tracing shader.
  /// </summary>
  public RayTracingShader shader;
  public Cubemap mp;

  // Volumetric lighting / Fog.
    public bool EnableFog;

  public float _MaxFogDistance;
  public Color _FogColor; // color in rgb
  public Vector4 _MipFogParameters;
  public float _HeightFogBaseExtinction;
  public float _HeightFogBaseHeight;
  public float _MaximumHeight;
  public float _GlobalFogAnisotropy;
  public float AngularDiameter;

  public Texture2D owenScrambled256Tex;
  public Texture2D scramblingTile8SPP;
  public Texture2D rankingTile8SPP;
  public Texture2D scramblingTex;
  public DiffusionProfileSettings diffusionProfileSettings;
  public HDRenderPipelineRayTracingResources PipelineRayTracingResources;

    /// <summary>
    /// the focus distance.
    /// </summary>
    public float focusDistance = 10.0f;
    /// <summary>
    /// the len aperture.
    /// </summary>
    public float aperture = 1.0f;
    /// <summary>
    /// create tutorial.
    /// </summary>
    /// <returns>the tutorial.</returns>
    public abstract RayTracingTutorial CreateTutorial();
}

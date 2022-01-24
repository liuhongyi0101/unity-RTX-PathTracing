struct LightVolume
{
    int active;
    int shape;
    float3 position;
    float3 range;
    uint lightType;
    uint lightIndex;
};

//GLOBAL_CBUFFER_START(ShaderVariablesRaytracingLightLoop, b4)
float3 _MinClusterPos;
uint _LightPerCellCount;
float3 _MaxClusterPos;
uint _PunctualLightCountRT;
uint _AreaLightCountRT;
uint _EnvLightCountRT;
//CBUFFER_END



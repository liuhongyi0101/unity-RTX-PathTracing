using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SetMaterial : MonoBehaviour
{
    // Start is called before the first frame update
    public DiffusionProfileSettings diffusionProfileSettings;
    private Material material;
    void Start()
    {
        material = GetComponent<Renderer>().sharedMaterial;
    }

    // Update is called once per frame
    void Update()
    {
        material.SetVector("_ShapeParamsAndMaxScatterDists", diffusionProfileSettings.shapeParamAndMaxScatterDist);
        material.SetVector("_worldScaleAndFilterRadiusAndThicknessRemap", diffusionProfileSettings.worldScaleAndFilterRadiusAndThicknessRemap);
        material.SetVector("_transmissionTintAndFresnel0", diffusionProfileSettings.transmissionTintAndFresnel0);
        material.SetVector("_disabledTransmissionTintAndFresnel0", diffusionProfileSettings.disabledTransmissionTintAndFresnel0);
    }
}

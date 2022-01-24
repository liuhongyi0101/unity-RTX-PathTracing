//
// CameraUtilsEditor.cs
//
// Author:
//       fourjiong <jiong@studio-symphonie.org>
//
// Copyright (c) 2017 fourjiong
//
// See the document "TERMS OF USE" included in the project folder for licencing details.
using UnityEngine;
using System.Collections;
using UnityEditor;

[CustomEditor(typeof(AlignToEditorCamera))]
public class AlignToEditorCameraEditor : Editor
{
	public override void OnInspectorGUI()
	{
		base.DrawDefaultInspector();
	}

	public void OnSceneGUI()
	{
		AlignToEditorCamera camreaUtils = (AlignToEditorCamera)target;

		if (!camreaUtils.enabled)
			return;

		if (camreaUtils.autoAlignPosition)
		{
			camreaUtils.transform.position = SceneView.lastActiveSceneView.camera.transform.position;
		}

		if (camreaUtils.autoAlignRotation)
		{
			camreaUtils.transform.rotation = SceneView.lastActiveSceneView.camera.transform.rotation;
		}
	}
}


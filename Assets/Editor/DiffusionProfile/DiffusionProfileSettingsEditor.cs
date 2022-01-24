using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

   // [CustomEditor(typeof(DiffusionProfileSettings))]
    partial class DiffusionProfileSettingsEditor : Editor
{
        sealed class Profile
        {
            internal SerializedProperty self;
            internal DiffusionProfile objReference;

            internal SerializedProperty scatteringDistance;
            internal SerializedProperty transmissionTint;
            internal SerializedProperty texturingMode;
            internal SerializedProperty transmissionMode;
            internal SerializedProperty thicknessRemap;
            internal SerializedProperty worldScale;
            internal SerializedProperty ior;

            // Render preview
            internal RenderTexture profileRT;
            internal RenderTexture transmittanceRT;

            internal Profile()
            {
                profileRT       = new RenderTexture(256, 256, 0, RenderTextureFormat.DefaultHDR);
                transmittanceRT = new RenderTexture(16, 256, 0, RenderTextureFormat.DefaultHDR);
            }

            internal void Release()
            {
                CoreUtils.Destroy(profileRT);
                CoreUtils.Destroy(transmittanceRT);
            }
        }

        Profile m_Profile;



        void OnEnable()
        {
           
                //scatteringDistance = rp.Find(x => x.scatteringDistance),
                //transmissionTint = rp.Find(x => x.transmissionTint),
                //texturingMode = rp.Find(x => x.texturingMode),
                //transmissionMode = rp.Find(x => x.transmissionMode),
                //thicknessRemap = rp.Find(x => x.thicknessRemap),
                //worldScale = rp.Find(x => x.worldScale),
                //ior = rp.Find(x => x.ior)
     
           // Undo.undoRedoPerformed += UpdateProfile;
        }

        void OnDisable()
        {
         
            m_Profile.Release();

            m_Profile = null;

          //  Undo.undoRedoPerformed -= UpdateProfile;
        }

        public override void OnInspectorGUI()
        {
            CheckStyles();

            serializedObject.Update();

            EditorGUILayout.Space();

            var profile = m_Profile;

            EditorGUI.indentLevel++;

            using (var scope = new EditorGUI.ChangeCheckScope())
            {
                EditorGUILayout.PropertyField(profile.scatteringDistance, s_Styles.profileScatteringDistance);

                using (new EditorGUI.DisabledScope(true))
                    EditorGUILayout.FloatField(s_Styles.profileMaxRadius, profile.objReference.filterRadius);

                EditorGUILayout.Slider(profile.ior, 1.0f, 2.0f, s_Styles.profileIor);
                EditorGUILayout.PropertyField(profile.worldScale, s_Styles.profileWorldScale);

                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.SubsurfaceScatteringLabel, EditorStyles.boldLabel);

                profile.texturingMode.intValue = EditorGUILayout.Popup(s_Styles.texturingMode, profile.texturingMode.intValue, s_Styles.texturingModeOptions);

                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.TransmissionLabel, EditorStyles.boldLabel);

                profile.transmissionMode.intValue = EditorGUILayout.Popup(s_Styles.profileTransmissionMode, profile.transmissionMode.intValue, s_Styles.transmissionModeOptions);

                EditorGUILayout.PropertyField(profile.transmissionTint, s_Styles.profileTransmissionTint);
                EditorGUILayout.PropertyField(profile.thicknessRemap, s_Styles.profileMinMaxThickness);
                var thicknessRemap = profile.thicknessRemap.vector2Value;
                EditorGUILayout.MinMaxSlider(s_Styles.profileThicknessRemap, ref thicknessRemap.x, ref thicknessRemap.y, 0f, 50f);
                profile.thicknessRemap.vector2Value = thicknessRemap;

                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.profilePreview0, s_Styles.centeredMiniBoldLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview1, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview2, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview3, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.Space();

                serializedObject.ApplyModifiedProperties();

     
            }

           // RenderPreview(profile);

            EditorGUILayout.Space();
            EditorGUI.indentLevel--;

            serializedObject.ApplyModifiedProperties();
        }

   
    }


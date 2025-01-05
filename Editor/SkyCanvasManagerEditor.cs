using UnityEngine;
using VRC.SDK3.Components;
using VRC.SDKBase;
using VRC.Udon;

#if !COMPILER_UDONSHARP && UNITY_EDITOR // These using statements must be wrapped in this check to prevent issues on builds
using UnityEditor;
using UdonSharpEditor;
#endif

namespace SilentTools
{
#if !COMPILER_UDONSHARP && UNITY_EDITOR 
[CustomEditor(typeof(SkyCanvasManager))]
public class SkyCanvasManagerEditor : Editor
{
    SkyCanvasManager lastManager = null;

    public override void OnInspectorGUI()
    {
        SkyCanvasManager manager = (SkyCanvasManager)target;
        lastManager = manager;

        // Show warning if the object isn't on a light.
        Light thisGOLight = manager.transform.GetComponent<Light>();
        if (thisGOLight == null || thisGOLight != manager._sunOverride)
        {
            EditorGUILayout.HelpBox("To see live updates in the scene as the sun moves around, place the manager script on the main directional light.", MessageType.Warning);
        }

        manager._atmosphereCloudsCRTMaterial = (Material)EditorGUILayout.ObjectField("Atmosphere Clouds CRT Material", manager._atmosphereCloudsCRTMaterial, typeof(Material), true);
        manager._atmosphereSkyCRTMaterial = (Material)EditorGUILayout.ObjectField("Atmosphere Sky CRT Material", manager._atmosphereSkyCRTMaterial, typeof(Material), true);
        manager._sunOverride = (Light)EditorGUILayout.ObjectField("Sun Override", manager._sunOverride, typeof(Light), true);
        manager._CloudSpeed = EditorGUILayout.Slider("Cloud Speed", manager._CloudSpeed, 0.0f, 12.0f);

        
        manager.UpdateMaterialProperties();
    }

    public void OnEnable()
    {
        SkyCanvasManager manager = (SkyCanvasManager)target;
        lastManager = manager;

        manager.UpdateMaterialProperties();
    }

    #if UNITY_EDITOR && !COMPILER_UDONSHARP
            private void OnValidate()
            {
                EditorApplication.delayCall += () =>
                {
                    if (lastManager == null) return;
                    lastManager.UpdateMaterialProperties();
                };
            }
    #endif

}
#endif
}

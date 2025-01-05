using System;
using UnityEngine;
#if UNITY_EDITOR && !COMPILER_UDONSHARP
using UnityEditor;
#endif

namespace SilentTools
{    
    using static VRC.SDKBase.VRCShader;

    using UdonSharp;

    using VRC.SDK3.Rendering;
    using VRC.SDKBase;

    [ExecuteInEditMode]
    [UdonBehaviourSyncMode(BehaviourSyncMode.None)]
    public class SkyCanvasManager : UdonSharpBehaviour
{
    public Material _atmosphereCloudsCRTMaterial;
    public Material _atmosphereSkyCRTMaterial;
    public Light _sunOverride;
    [Space][Range(0.0f, 12.0f)]
    public float _CloudSpeed = 1.0f;
    private VRCPlayerApi _localPlayer;
    private Vector3 _cameraPos;
    private Vector4 _sunPos;
    private Vector4 _localTime;


    private int _id_CameraPositionOffset;
    private int _id_OverrideSun;
    private int _id_OverrideTime;
    private bool _IsInitialized = false;

    private void InitIDs()
    {
        if (_IsInitialized)
            return;

        _id_CameraPositionOffset = PropertyToID("_CameraPositionOffset");
        _id_OverrideSun = PropertyToID("_OverrideSun");
        _id_OverrideTime = PropertyToID("_OverrideTime");
        
        _IsInitialized = true;
    }

    private Vector4 ConvertSunLightToVector4(Light light)
    {
        if (light == null)
        {   
            // If the W component is 0, the override is ignored.
            return Vector4.zero;
        }

        Vector3 sunPos = -light.transform.forward.normalized;
        Vector4 sunPosNorm = new Vector4(
            sunPos.x,
            sunPos.y,
            sunPos.z,
            1.0f
        );
        return sunPosNorm;
    }

    private Vector4 GetConvertedVectorTime()
    {
        // Rather than using the scene time, we can sync to the UTC time and have 
        // similar clouds across users...
        double utcTime = (double)DateTime.UtcNow.TimeOfDay.TotalSeconds;
        double secondsInADay = 86400.0;
        // Interval is 10
        double windSpeedA = (_CloudSpeed * utcTime / 20.0) % (secondsInADay/2.0);
        double windSpeedB = (_CloudSpeed * utcTime) % (secondsInADay/2.0);
        return new Vector4((float)windSpeedA, (float)windSpeedB, 0.0f, 1.0f);
    }

    private void UpdateAtmosphereParameters()
    {
        InitIDs();
        Vector4 cameraPosSend = new Vector4(_cameraPos.x, _cameraPos.y, _cameraPos.z, 1.0f);
        _atmosphereCloudsCRTMaterial.SetVector(_id_CameraPositionOffset, cameraPosSend);
        _atmosphereSkyCRTMaterial.SetVector(_id_CameraPositionOffset, cameraPosSend);

        Vector4 sunPosSend = _sunPos;
        _atmosphereCloudsCRTMaterial.SetVector(_id_OverrideSun, sunPosSend);
        _atmosphereSkyCRTMaterial.SetVector(_id_OverrideSun, sunPosSend);

        _atmosphereCloudsCRTMaterial.SetVector(_id_OverrideTime, _localTime);
        _atmosphereSkyCRTMaterial.SetVector(_id_OverrideTime, _localTime);
    }

    public void UpdateMaterialProperties()
    {
        _sunPos = ConvertSunLightToVector4(_sunOverride);
        _localTime = GetConvertedVectorTime();
        UpdateAtmosphereParameters();
    }

    public void Start()
    {
        if (_sunOverride == null)
        {
            _sunOverride = RenderSettings.sun;
        }
        UpdateAtmosphereParameters();
    }

    public void Update()
    {
        if (VRC.SDKBase.Utilities.IsValid(_localPlayer))
        {
            _cameraPos = _localPlayer.GetTrackingData(VRCPlayerApi.TrackingDataType.Head).position;
        }
        UpdateMaterialProperties();
    }

#if UNITY_EDITOR && !COMPILER_UDONSHARP
        private void OnValidate()
        {
            EditorApplication.delayCall += () =>
            {
                if (this == null) return;
                UpdateAtmosphereParameters();
            };
        }
#endif

}

}
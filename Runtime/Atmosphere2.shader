Shader "Silent/Skybox/Atmosphere2"
{
    Properties
    {
        [NoScaleOffset]_SkyTexture ("Sky Texture", 3D) = "" {}
        [Header(Night Sky)]
        [ToggleUI]_UseStars("Use Procedural Stars", Float) = 1.0
        _StarIntensity("Stars Intensity", Range(0, 10)) = 1.0
        [ToggleUI]_UseStarsTexture("Use Star Texture", Float) = 0.0
        _StarTexture("Star Texture", Cube) = "" {}
        _StarTextureIntensity("Stars Texture Intensity", Range(0, 10)) = 0.1

		// Cloud parameters
		[Header(TowelCloud)]
		_noiseMap("Cloud Noise Map", 2D) = "white" {}
		_scale ("Cloud Size (Higher: less repetition)", Float) = 55
		_cloudy ("Cloudiness", Range (0, 1)) = 0.5
		_soft ("Cloud Softness", Range (0.0001, 0.9999)) = 0.4
		[Header(Horizon)]
		[Toggle]_underFade ("underFade: Fade out clouds at the bottom", Float) = 1
		_underFadeStart ("underFadeStart: Start fading position", Range (-1, 1)) = -0.5
		_underFadeWidth ("underFadeWidth: Fade gradient width", Range (0.0001, 0.9999)) = 0.2
		[Header(Movement)]
		_moveRotation ("moveRotation: Cloud movement direction", Range (0, 360)) = 0
		_speed_parameter ("speed: Cloud speed", Float) = 1
		_shapeSpeed_parameter ("shapeSpeed: Cloud deformation amount", Float) = 1
		_speedOffset ("speedOffset: Speed difference in fine parts of clouds", Float) = 0.2
		_speedSlide ("speedSlide: Lateral speed of fine parts of clouds", Float) = 0.1
		[Header(Surface Wind)]
		_faceWindScale_parameter ("faceWindScale: Surface wind size", Float) = 1
		_faceWindForce_parameter ("faceWindForce: Surface wind strength", Float) = 1
		_faceWindMove ("faceWindMove: Surface wind movement speed", Float) = 1.3
		_faceWindMoveSlide ("faceWindMoveSlide: Movement speed of fine parts of surface wind", Float) = 1.8
		[Header(Distant Wind)]
		_farWindDivision ("farWindDivision: Number of divisions for distant wind", Int) = 35
		_farWindForce_parameter ("farWindForce: Distant wind strength", Float) = 1
		_farWindMove ("farWindMove: Distant wind movement speed", Float) = 2
		_farWindTopEnd ("farWindTopEnd: Position where distant wind disappears at the top", Float) = 0.5
		_farWindTopStart ("farWindTopStart: Position where distant wind starts to weaken at the top", Float) = 0.3
		_farWindBottomStart ("farWindBottomStart: Position where distant wind starts to weaken at the bottom", Float) = 0.1
		_farWindBottomEnd ("farWindBottomEnd: Position where distant wind disappears at the bottom", Float) = -0.1
		[Header(Airflow)]
		[Toggle] _stream ("stream: Airflow", Float) = 1
		_streamForce ("streamForce: Airflow strength", Float) = 5
		_streamScale ("streamScale: Airflow size", Float) = 5
		_streamMove ("streamMove: Airflow movement speed", Float) = 1.5
		[Header(Etc)]
		_fbmScaleUnder ("fbmScaleUnder: Deformation value of fine parts of clouds", Float) = 0.43
		_chine ("chine: Softness of cloud ridges", Float) = 0.5

        // Unused parameters.
		// [Header(Rimlight)]
		// _rimForce ("rimForce: Strength of edge light", Float) = 0.5
		// _rimNarrow ("rimNarrow: Narrowness of edge light", Float) = 2
		// [Header(Scattering)]
		// [Toggle] _scattering ("scattering: Use diffuse light", Float) = 0
		// _scatteringColor ("scatteringColor: Diffuse light color", Color) = (1, 1, 1, 1)
		// _scatteringForce ("scatteringForce: Diffuse light strength", Range (0, 3)) = 0.8
		// _scatteringRange ("scatteringRange: Range affected by diffuse light", Range (0, 1)) = 0.3
		// _scatteringNarrow ("scatteringNarrow: Narrowness of diffuse light edge", Float) = 1

    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "IsEmissive" = "true" }
        Cull Off ZWrite Off
        LOD 100
        CGINCLUDE
            #pragma shader_feature_local _STREAM_ON

            #include "UnityCG.cginc"
            #include "AtmosphereCommon.hlsl"
            #include "NightSkyFunctions.hlsl"
            #include "CloudFunctions.hlsl"
        ENDCG

        Pass
        {
            Name "FORWARD"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag


			// Unity inbuilt parameters.
			float4 _LightColor0;

            struct appdata_t
            {
                float4 vertex : POSITION;
                float3  uvw : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4  pos : SV_POSITION;
                float3 view_ray : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler3D _SkyTexture;
            float4 _SkyTexture_ST;

            UNITY_DECLARE_TEXCUBE(_StarTexture);

            float _UseStars;
            float _UseStarsTexture;
            float _StarIntensity;
            float _StarTextureIntensity;

            v2f vert (appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID( v );
                UNITY_INITIALIZE_OUTPUT( v2f, o );
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO( o );
                o.pos = UnityObjectToClipPos(v.vertex);
                o.view_ray = v.uvw;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 ray_dir = normalize(i.view_ray);
                float3 sun_dir = normalize(_WorldSpaceLightPos0);

                float _Exposure = 10.0;

                // Prepare some useful data.                 
                float3 reoriented_ray_dir = ray_dir.xzy;
                reoriented_ray_dir.z *= -1;
                float3 ray_origin = float3(0.0, 0.0, EYE_DISTANCE_TO_EARTH_CENTER);
                float atmos_dist  = ray_sphere_intersection(ray_origin, reoriented_ray_dir, ATMOSPHERE_RADIUS);
                float ground_dist = ray_sphere_intersection(ray_origin, reoriented_ray_dir, EARTH_RADIUS);
                float t_d;
                if (EYE_ALTITUDE < ATMOSPHERE_THICKNESS) {
                    // We are inside the atmosphere
                    if (ground_dist < 0.0) {
                        // No ground collision, use the distance to the outer atmosphere
                        t_d = atmos_dist;
                    } else {
                        // We have a collision with the ground, use the distance to it
                        t_d = ground_dist;
                    }
                }

                float skyGroundFactor = saturate(atmos_dist/1000 - 1);
                
                // Clouds first, as the sky radiance sampling depends on the cloud thickness.
            
				CloudOutputData cloud = (CloudOutputData)0;
                if (atmos_dist > 1000)
                {
                    float3 ray_dir = normalize(i.view_ray);
                    float3 ray_origin = float3(0.0, 0.0, EYE_DISTANCE_TO_EARTH_CENTER);
                    cloud = GetCloudAtmosphere(ray_origin, -ray_dir);
                }

                // Sky radiance sampling 
                float phi = atan2(ray_dir.z, ray_dir.x);
                float theta = asin(ray_dir.y);
                
                float azimuth = phi / PI * 0.5 + 0.5;

                // Undo the non-linear transformation from the sky-view LUT
                float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;

                float4 skyRadiance = tex3D(_SkyTexture, float3(azimuth, elev, cloud.power));

                // Cloud lighting
				float3 invY = float3(1, -1, 1);
				float3 cloudLightDirection = sun_dir; 
				float cloudNoL = dot(cloud.worldNormal, cloudLightDirection);
				float cloudNoLRemap = saturate(cloudNoL * 0.5 + 0.5);
				float cloudNoV = dot(ray_dir, cloudLightDirection) * 0.5 + 0.5;
				float cloudOcclusion = 1-(cloudNoLRemap * cloud.power);

                
                float skyOcclusion = (1.0 - cloud.power) * cloudOcclusion;

                skyRadiance += skyRadiance * cloudNoL * cloud.power * 0.5;

                // Stars and night sky
                
				float3 nightSky = 0.0;
                
                if (_UseStars)
                {
                    float2 sp = convertToSphericalCoordinates(ray_dir.xzy).yz;

                    nightSky += stars(sp, 0) * _StarIntensity;
                    nightSky *= nightSky;
                }

                if (_UseStarsTexture)
                {
                    nightSky += UNITY_SAMPLE_TEXCUBE(_StarTexture, ray_dir) * _StarTextureIntensity;
                }
                
                // Fade out at horizon smoothly
                nightSky *= skyGroundFactor;
                // Fade out at cloud edges
                nightSky *= skyOcclusion * skyOcclusion;

                // If the view ray intersects the Sun, add the Sun radiance.
                
				// When baking reflection probes, the skybox is not told the colour of the sun
				// to avoid doubled sun reflections. However, this can look bad visually, especially
				// when a realtime light is not present in the scene. To avoid this, Unity's regular
				// procedural skybox uses this workaround which clamps the max intensity of the sky's sun. 
            	half lightColorIntensity = clamp(length(_LightColor0.xyz), 0.25, 1) ;
				float3 sunRadiance = _LightColor0.xyz / lightColorIntensity; 

				float sunAttenuation = smoothstep(0.9999891, 1, dot(ray_dir, sun_dir));
                sunAttenuation *= skyGroundFactor;
                sunAttenuation *= skyOcclusion * skyOcclusion;

                float4 output = 0;
                skyRadiance.xyz +=  sunAttenuation * _LightColor0.xyz * 50.0;

                output.xyz = skyRadiance;

                // In real life, stars are always visible, but the atmosphere is too bright for us to see them.
                // As a workaround we can attenuate the stars by the sky brightness. This avoids needing to deal
                // with realistic light ranges, which are difficult to calibrate. 
                float skyLum = dot(skyRadiance.rgb, 1.0/3.0);
                output.xyz += (nightSky * 1) / max(1, skyLum * 1000);

                output *= _Exposure;

                output.a = 1.0;
                return output;
            }
            ENDCG
        }
    }
}

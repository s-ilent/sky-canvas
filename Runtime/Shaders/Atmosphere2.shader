Shader "Silent/Skybox/Sky Canvas"
{
    Properties
    {
        [NoScaleOffset]_SkyTexture ("Sky Texture", 3D) = "" {}
        [NoScaleOffset]_CloudTexture ("Cloud Texture", 2D) = "" {}

        [Header(Cloud Settings are in the cloud CRT)]
        _Exposure("Main Exposure", Range(0, 10)) = 1.0

        [Header(Night Sky)]
        [ToggleUI]_UseStars("Use Procedural Stars", Float) = 1.0
        _StarIntensity("Stars Intensity", Range(0, 10)) = 1.0
        [ToggleUI]_UseStarsTexture("Use Star Texture", Float) = 0.0
        _StarTexture("Star Texture", Cube) = "" {}
        _StarTextureIntensity("Stars Texture Intensity", Range(0, 10)) = 0.1
        
        [HideInInspector][NonModifiableTextureData]_TANoiseTex ("TANoise", 2D) = "white" {}
        [HideInInspector][NonModifiableTextureData]_blueNoise("Blue Noise", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" "IsEmissive" = "true" }
        Cull Off ZWrite Off
        LOD 100

        CGINCLUDE
        // Some code from https://gist.github.com/pimaker/3344dc9957e20d4c8525446b465bc022
        #include "UnityCG.cginc"
        #include "tanoise/tanoise.cginc"
        #include "AtmosphereCommon.hlsl"
        #include "CloudCommon.hlsl"
        #include "NightSkyFunctions.hlsl" 
        ENDCG

        Pass
        {
            Name "FORWARD"

            CGPROGRAM
            // UNITY_SHADER_NO_UPGRADE
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0


            struct appdata
            {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 objectOrigin : ORIGIN;
                float3 rayOrigin : RAYORIGIN;
                float3 rayDir : RAYDIR;
                float3 screenPos : SCREENPOS;
                UNITY_VERTEX_OUTPUT_STEREO
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            sampler3D _SkyTexture;
            float4 _SkyTexture_ST;

            sampler2D _CloudTexture;
            float4 _CloudTexture_TexelSize;

            float4 _LightColor0;

            UNITY_DECLARE_TEXCUBE(_StarTexture);

            float _UseStars;
            float _UseStarsTexture;
            float _StarIntensity;
            float _StarTextureIntensity;

            float _Exposure;

            sampler2D _NoiseMap;
            float _NoiseScale;
            float _NoisePow;

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID( v );
                UNITY_INITIALIZE_OUTPUT( v2f, o );
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO( o );

                o.vertex = UnityObjectToClipPos(v.vertex);
                o.objectOrigin = mul(unity_ObjectToWorld, float4(0.0,0.0,0.0,1.0) );

                // I saw these ortho shadow substitutions in a few places, but bgolus explains them
                // https://bgolus.medium.com/rendering-a-sphere-on-a-quad-13c92025570c
                float howOrtho = UNITY_MATRIX_P._m33; // instead of unity_OrthoParams.w
                float3 worldSpaceCameraPos = UNITY_MATRIX_I_V._m03_m13_m23; // instead of _WorldSpaceCameraPos
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
                float3 cameraToVertex = worldPos - worldSpaceCameraPos;
                float3 orthoFwd = -UNITY_MATRIX_I_V._m02_m12_m22; // often seen: -UNITY_MATRIX_V[2].xyz;
                float3 orthoRayDir = orthoFwd * dot(cameraToVertex, orthoFwd);
                // start from the camera plane (can also just start from o.vertex if your scene is contained within the geometry)
                float3 orthoCameraPos = worldPos - orthoRayDir;
                o.rayOrigin = lerp(worldSpaceCameraPos, orthoCameraPos, howOrtho );
                o.rayDir = ( lerp( cameraToVertex, orthoRayDir, howOrtho ) );
                o.screenPos = ComputeNonStereoScreenPos(o.vertex).xyw;

                return o;
            }
    
            float2 GetOppositeSunAzimuthElev(float3 sunDir) {
                float3 oppSunDir = -sunDir;

                float phi = atan2(oppSunDir.z, oppSunDir.x);
                float theta = asin(oppSunDir.y);

                float azimuth = phi / PI * 0.5 + 0.5;
                float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;
                return float2(azimuth, elev);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 rayDir = normalize(i.rayDir);
                float3 sunDir = normalize(_WorldSpaceLightPos0);

                // Prepare some useful data.                 
                float3 reoriented_ray_dir = rayDir.xzy;
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
                
                // Sky radiance sampling 
                float phi = atan2(rayDir.z, rayDir.x);
                float theta = asin(rayDir.y);
                
                float azimuth = phi / PI * 0.5 + 0.5;

                // Undo the non-linear transformation from the sky-view LUT
                float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;

                // We could sample the sky once but twice is easier to mess with for clouds
                float4 skyCol = tex3D(_SkyTexture, float3(azimuth, elev, 0));
                float4 denseCol = tex3D(_SkyTexture, float3(azimuth, elev, 1));
                
				// When baking reflection probes, the skybox is not told the colour of the sun
				// to avoid doubled sun reflections. However, this can look bad visually, especially
				// when a realtime light is not present in the scene. To avoid this, Unity's regular
				// procedural skybox uses this workaround which clamps the max intensity of the sky's sun. 
            	half lightColorIntensity = clamp(length(_LightColor0.xyz), 0.25, 1) ;
				float3 sunRadiance = _LightColor0.xyz / lightColorIntensity; 

				float sunAttenuation = smoothstep(0.9999891, 1, dot(rayDir, sunDir));
                sunAttenuation *= skyGroundFactor;

                // Clouds 
                float2 cloudUVs = directionToGbufferUV(rayDir);

                // Use a noise texture to warp the top of the sky, where the pixellation is most obvious.
                float skyUp = (saturate(rayDir.y));
				float skyDown = (saturate(-rayDir.y));
                // ((rayDir.xz*_NoiseScale*0.125) / max(skyUp, skyDown))+rayDir.xz
                float2 noiseUVs = SampleBlueNoise(
                    cloudUVs, 
                    float4(i.screenPos.xy, i.vertex.z, i.screenPos.z), 
                    float4((1).xx, (0).xx), 
                    _CloudTexture_TexelSize);

                float3 col = 0;
                float4 clouds = tex2D(_CloudTexture, noiseUVs);
                clouds *= (rayDir.y > 0) * skyGroundFactor;
                
                float distanceToCloud, sunLighting, ambientLighting, alpha;
                distanceToCloud = clouds.r;
                sunLighting = clouds.g;
                ambientLighting = clouds.b;
                alpha = clouds.a;

                // Stars and night sky
				float3 nightSky = 0.0;
                if (_UseStars)
                {
                    float2 sp = convertToSphericalCoordinates(rayDir.xzy).yz;

                    nightSky += stars(sp, 0) * _StarIntensity;
                    nightSky = saturate(pow(nightSky, 2.0));
                }
                if (_UseStarsTexture)
                {
                    nightSky += UNITY_SAMPLE_TEXCUBE(_StarTexture, rayDir) * _StarTextureIntensity;
                }
                // Fade out at horizon smoothly
                nightSky *= skyGroundFactor;
                // Fade out at cloud edges
                nightSky *= 1-alpha;

                float3 directCol = sunLighting * sunRadiance * denseCol; //tex3D(_SkyTexture, float3(azimuth, elev, sunLighting*10));
                //float3 ambientCol = lerp(skyCol, denseCol, ambientLighting) * lerp(0.8, 1.0, ambientLighting); 
                float3 ambientCol = skyCol; 
                ambientCol = lerp(ambientCol, 1.0, (ambientLighting)); 
                // todo: at night time, use 1-ambientLighting 

                skyCol.xyz += (1-alpha) * sunAttenuation * _LightColor0.xyz * 50.0;
                
                // In real life, stars are always visible, but the atmosphere is too bright for us to see them.
                // As a workaround we can attenuate the stars by the sky brightness. This avoids needing to deal
                // with realistic light ranges, which are difficult to calibrate. 
                float skyLum = dot(skyCol.rgb, 1.0/3.0);
                skyCol.xyz += (nightSky * 1) / max(1, skyLum * 2000);

                //col.rgb = lerp(skyCol, directCol + ambientCol, alpha);
                col.rgb = skyCol * (1.0 - alpha) + ambientCol + directCol;

                col *= _Exposure;

                return float4(col, 1.0);
            }
            ENDCG
        }
    }
}

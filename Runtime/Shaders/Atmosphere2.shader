Shader "Silent/Skybox/Sky Canvas"
{
    Properties
    {
        [NoScaleOffset]_SkyTexture ("Sky Texture", 3D) = "black" {}
        [NoScaleOffset]_CloudTexture ("Cloud Texture", 2D) = "black" {}

        _Exposure("Main Exposure", Range(0, 10)) = 1.0
        _SunIntensity("Sun Disc Intensity", Range(1, 100)) = 50
        _SunSize("Sun Disc Size", Range(0, 10)) = 1.0
        [ToggleUI]_UseMainLightForSun("Use Main Light for Sun Colour", Float) = 0.0
        [Space]
        [Enum(None, 0, Mirror, 1, Only Mirror, 2)]_SkyReflection("Flip Sky Under Horizon", Float) = 0.0
        _SkyDensity ("Sky Density (dark cloudiness)", Range(0, 1)) = 0.0

        [Header(Cloud settings ... simulation settings are in the cloud CRT)]
        [ToggleUI]_HideClouds("Hide Clouds", Float) = 0.0
        [Enum(None, 0, Mirror, 1, Only Mirror, 2)]_CloudReflection("Flip Clouds Under Horizon", Float) = 1.0

        [Space]
        _CloudAmbientColDay("Cloud Ambient Colour Daytime", Color) = (1, 1, 1, 1)
        _CloudAmbientColNight("Cloud Ambient Colour Night", Color) = (0.1, 0.1, 0.1, 1)
        _CloudAmbientColMidnight("Cloud Ambient Colour Midnight", Color) = (0.1, 0.1, 0.1, 1)
        [Space]
        _CloudInteriorDarkening("Cloud Interior Darkening", Range(0, 1)) = 1.0

		[Header(Clouds Extra Noise)]
		_NoiseMap ("Noise Map for Clouds", 2D) = "white" {}
        _NoiseScale("Noise Scale", Float) = 1.0
        _NoisePow("Noise Strength", Float) = 1.0

        [Header(Night Sky)]
        [ToggleUI]_UseStars("Use Procedural Stars", Float) = 1.0
        _StarIntensity("Stars Intensity", Range(0, 10)) = 1.0
        [ToggleUI]_UseStarsTexture("Use Star Texture", Float) = 0.0
        _StarTexture("Star Texture", Cube) = "" {}
        _StarTextureIntensity("Stars Texture Intensity", Range(0, 10)) = 0.1
        _RotationParams("Rotation Params (axis, angle)", Vector) = (1, 0, 0, 0)
        
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
                //float4 objectOrigin : ORIGIN;
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
            
            float _CloudReflection;
            float4 _CloudAmbientColDay;
            float4 _CloudAmbientColNight;
            float4 _CloudAmbientColMidnight;
            float _HideClouds;

            float4 _LightColor0;
            float _SunIntensity;
            float _SunSize;
            float _SkyReflection;
            float _UseMainLightForSun;

            UNITY_DECLARE_TEXCUBE(_StarTexture);

            float _UseStars;
            float _UseStarsTexture;
            float _StarIntensity;
            float _StarTextureIntensity;

            float _Exposure;
            float _SkyDensity;
            float4 _RotationParams;

            sampler2D _NoiseMap;
            float _NoiseScale;
            float _NoisePow;

            float _CloudInteriorDarkening;


            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID( v );
                UNITY_INITIALIZE_OUTPUT( v2f, o );
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO( o );

                o.vertex = UnityObjectToClipPos(v.vertex);
                //o.objectOrigin = mul(unity_ObjectToWorld, float4(0.0,0.0,0.0,1.0) );

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

            float2 directionToSkyUv(float3 rayDir)
            {
                float phi = atan2(rayDir.z, rayDir.x);
                float theta = asin(rayDir.y);
                
                float azimuth = phi / PI * 0.5 + 0.5;

                // Undo the non-linear transformation from the sky-view LUT
                float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;
                return float2(azimuth, elev);
            }
    
            float2 GetOppositeSunAzimuthElev(float3 sunDir) {
                float3 oppSunDir = -sunDir;

                float phi = atan2(oppSunDir.z, oppSunDir.x);
                float theta = asin(oppSunDir.y);

                float azimuth = phi / PI * 0.5 + 0.5;
                float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;
                return float2(azimuth, elev);
            }

            float3 rotateVector(float3 target, float3 axis, float angle)
            {
                float3x3 rotationMatrix;
                float cosAngle = cos(angle);
                float sinAngle = sin(angle);
                float oneMinusCosAngle = 1.0 - cosAngle;

                rotationMatrix[0][0] = cosAngle + axis.x * axis.x * oneMinusCosAngle;
                rotationMatrix[0][1] = axis.x * axis.y * oneMinusCosAngle - axis.z * sinAngle;
                rotationMatrix[0][2] = axis.x * axis.z * oneMinusCosAngle + axis.y * sinAngle;

                rotationMatrix[1][0] = axis.y * axis.x * oneMinusCosAngle + axis.z * sinAngle;
                rotationMatrix[1][1] = cosAngle + axis.y * axis.y * oneMinusCosAngle;
                rotationMatrix[1][2] = axis.y * axis.z * oneMinusCosAngle - axis.x * sinAngle;

                rotationMatrix[2][0] = axis.z * axis.x * oneMinusCosAngle - axis.y * sinAngle;
                rotationMatrix[2][1] = axis.z * axis.y * oneMinusCosAngle + axis.x * sinAngle;
                rotationMatrix[2][2] = cosAngle + axis.z * axis.z * oneMinusCosAngle;

                return mul(rotationMatrix, target);
            }

            // https://www.shadertoy.com/view/WtyXRy
            // MIT License - Copyright © 2020 Inigo Quilez

            float4 textureQuadratic(sampler2D samLinear, float2 p, float4 texelSize)
            {
                float texSize = texelSize.zw;

                //return tex2D(samLinear, p);
                
                #if 1
                    // Roger/iq style
                    p = p * texSize;
                    float2 i = floor(p);
                    float2 f = frac(p);
                    p = i + f * 0.5;
                    p /= texSize;
                    //f = f * f * (3.0 - 2.0 * f); // optional for extra sweet
                    float w = 0.5 / texSize;
                    return lerp(lerp(tex2D(samLinear, p + float2(0, 0)),
                                    tex2D(samLinear, p + float2(w, 0)), f.x),
                                lerp(tex2D(samLinear, p + float2(0, w)),
                                    tex2D(samLinear, p + float2(w, w)), f.x), f.y);
                
                #else
                    // paniq style (https://www.shadertoy.com/view/wtXXDl)
                    float2 f = frac(p * texSize);
                    float2 c = (f * (f - 1.0) + 0.5) / texSize;
                    float2 w0 = p - c;
                    float2 w1 = p + c;
                    return (tex2D(samLinear, float2(w0.x, w0.y)) +
                            tex2D(samLinear, float2(w0.x, w1.y)) +
                            tex2D(samLinear, float2(w1.x, w1.y)) +
                            tex2D(samLinear, float2(w1.x, w0.y))) / 4.0;
                #endif    
            }

            struct SkyData
            {
                float4 transmittance;
                float4 skyCol;
                float4 denseCol;
            };

            SkyData getSky(float3 rayDir)
            {
                const float3 rayDirMirrored = float3(rayDir.x, abs(rayDir.y), rayDir.z);
                const float3 rayDirFlipped = float3(rayDir.x, -rayDir.y, rayDir.z);
                float2 skyUVs = directionToSkyUv(_SkyReflection > 1 ? rayDirFlipped : _SkyReflection ? rayDirMirrored : rayDir);
                
                SkyData sky = (SkyData)0;

                sky.transmittance = tex3D(_SkyTexture, float3(skyUVs, 0.0));
                sky.skyCol = tex3D(_SkyTexture, float3(skyUVs, lerp(0.5, 1.0, _SkyDensity)));
                sky.denseCol = tex3D(_SkyTexture, float3(skyUVs, 1.0));

                return sky;
            }

            struct CloudData
            {
                float distance;
                float direct;
                float ambient;
                float alpha;
            };

			inline float revertOrZero (float value)
			{
				float revert = 1 / value;
				if (value == 0) return 0;
				return revert;
			}

			inline float4 createTextureNoise (float2 coord, float totalScale, float2 speed)
			{
				float totalSmallness = revertOrZero(totalScale);
			    static const float scaleBase = 10; 
				return tex2D(_NoiseMap, (coord + speed + totalScale * scaleBase) * totalSmallness);
			}

            CloudData getClouds(float3 rayDir, v2f i, float skyGroundFactor)
            {
                if (_HideClouds) return (CloudData)0;
                const float3 rayDirMirrored = float3(rayDir.x, abs(rayDir.y), rayDir.z);
                const float3 rayDirFlipped = float3(rayDir.x, -rayDir.y, rayDir.z);

                rayDir = _CloudReflection > 1 ? rayDirFlipped : _CloudReflection ? rayDirMirrored : rayDir;
                
                
				float sideAngle = atan2(rayDir.x, rayDir.z) / (PI * 2);
                float2 farWindUV = frac(sideAngle * float2(35, rayDir.y * 35));
				float4 farWindNoise = createTextureNoise(_NoiseScale * farWindUV * 2, 1, float2(_Time.y * 0.0012, _Time.y * 0.0012)) * 2 - 1;
				float4 ovalWindNoise = createTextureNoise(_NoiseScale * rayDir.xz * 2, 1, float2(_Time.y * 0.03, _Time.y * 0.03)) * 2 - 1;
				rayDir += normalize(lerp(farWindNoise, ovalWindNoise, saturate(rayDir.y))) * 0.01 * _NoisePow;
                rayDir = normalize(rayDir);

                float2 cloudUVs = directionToGbufferUV(rayDir);

                // Offset intertexel position with blue noise to hide interpolation artifacts
                float2 cloudUVsNoisy = SampleBlueNoise(
                    cloudUVs, 
                    float4(i.screenPos.xy, i.vertex.z, i.screenPos.z), 
                    float4((1).xx, (0).xx), 
                    _CloudTexture_TexelSize);

                float4 cloudTex = textureQuadratic(_CloudTexture, cloudUVsNoisy, _CloudTexture_TexelSize);

                // Originally used (rayDir.y > 0) but looks too harsh. Clouds continue below the horizon a bit.
                if (_CloudReflection < 0.5) cloudTex *= saturate(skyGroundFactor*12);
                if (_CloudReflection > 1.5) cloudTex *= 1 - saturate(skyGroundFactor*12);
                
                CloudData clouds = (CloudData)0;
                clouds.distance = cloudTex.r;
                clouds.direct = cloudTex.g;
                clouds.ambient = cloudTex.b;
                clouds.alpha = cloudTex.a;

                return clouds;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 rayDir = normalize(i.rayDir);
                float3 sunDir = normalize(_WorldSpaceLightPos0);

                // Sky calculations take place in a different coordinate space
                float3 reoriented_ray_dir = rayDir.xzy;
                reoriented_ray_dir.z *= -1;
                float3 sky_ray_origin = float3(0.0, 0.0, EYE_DISTANCE_TO_EARTH_CENTER);
                float atmos_dist  = ray_sphere_intersection(sky_ray_origin, reoriented_ray_dir, ATMOSPHERE_RADIUS);
                float ground_dist = ray_sphere_intersection(sky_ray_origin, reoriented_ray_dir, EARTH_RADIUS);
                float distanceToSurface;
                if (EYE_ALTITUDE < ATMOSPHERE_THICKNESS) {
                    // We are inside the atmosphere
                    if (ground_dist < 0.0) {
                        // No ground collision, use the distance to the outer atmosphere
                        distanceToSurface = atmos_dist;
                    } else {
                        // We have a collision with the ground, use the distance to it
                        distanceToSurface = ground_dist;
                    }
                }

                float dayNightFactor = clamp(dot(sunDir, float3(0, 1, 0)), -1, 1);
                float dayFactor = saturate(dayNightFactor);
                float nightFactor = saturate(-dayNightFactor);
                float skyGroundFactor = saturate(atmos_dist/1070 - 1); 
                float sunGroundFactor = saturate(atmos_dist/1200 - 1); 

                // When the user raises the density, the sky should get darker to simulate greater degrees of cloudiness.
                float cloudyLightFactor = lerp(0.01, 1.0, saturate(pow(1.0 - _SkyDensity, 8.0)));
                
                // Sky radiance sampling 
                SkyData sky = getSky(rayDir);

                float3 sunRadiance = sky.transmittance;
                
                if (_UseMainLightForSun)
                {
                    // When baking reflection probes, the skybox is not told the colour of the sun
                    // to avoid doubled sun reflections. However, this can look bad visually, especially with baked
                    // light when a realtime light is not present in the scene. To avoid this, Unity's regular
                    // procedural skybox uses this workaround which clamps the max intensity of the sky's sun. 
                    half lightColorIntensity = clamp(length(_LightColor0.xyz), 0.25, 1) ;
                    float3 sunRadiance = _LightColor0.xyz / lightColorIntensity; 

                    if (length(_LightColor0.xyz == 0.0)) sunRadiance = 4.0;
                }

				float sunAttenuation = GetSunDisc(rayDir, sunDir, _SunSize);
                sunAttenuation *= sunGroundFactor * cloudyLightFactor;

                // Clouds 
                float3 cloudAmbientIntensity = lerp(_CloudAmbientColNight, _CloudAmbientColDay, dayFactor);
                cloudAmbientIntensity = lerp(cloudAmbientIntensity, _CloudAmbientColMidnight, nightFactor);

                CloudData clouds = getClouds(rayDir, i, skyGroundFactor);

                // Fudged value to fade out clouds far away.
                // Todo: Make tuneable
                float cloudFadeOut = exp2(-0.0004 * clouds.distance);
                //cloudAlpha = lerp(0, cloudAlpha, cloudFadeOut);
                float cloudOcclusion = 1.0 - saturate(clouds.alpha * 1);//pow(1.0 - cloudAlpha, 1.0);


                // Stars and night sky
				float3 nightSky = 0.0;
                // float3 nightRayDir = rotateVector(rayDir, cross(sunDir, float3(0, 1, 0)), _SinTime * 2.0 * PI );
                float3 nightRayDir = rotateVector(rayDir, _RotationParams.xyz, _RotationParams.w * 2.0 * PI );

                float cloudOcc3 = cloudOcclusion * cloudOcclusion * cloudOcclusion;
                
                if (_UseStars)
                {
                    float2 sp = convertToSphericalCoordinates(nightRayDir.xzy).yz;

                    // Stars are very far away, so occlusion should be done before the intensity tweaking. 
                    nightSky += stars(sp, 0) * cloudOcc3;
                    nightSky = (pow(nightSky, 3.0)) * 0.001;
                    nightSky *= _StarIntensity * skyGroundFactor;
                }
                if (_UseStarsTexture)
                {
                    nightSky += UNITY_SAMPLE_TEXCUBE(_StarTexture, nightRayDir) * 0.001 * _StarTextureIntensity * cloudOcc3;
                }
                
                // Fade out at horizon smoothly
                nightSky *= skyGroundFactor;
                // Fade out at cloud edges
                nightSky *= cloudOcclusion;
                
                float3 finalSky = 0;

                // Use the alpha of the clouds as a hint towards their density to darken their insides 
                // and make the sunlight spreading through the edges more apparent
                float cloudFakeShadowPow = lerp(1.0, 1.0 - clouds.alpha, _CloudInteriorDarkening);
                float cloudFade = clouds.alpha * cloudFadeOut;
                float3 cloudCol = clouds.direct * sky.transmittance * sky.denseCol * cloudFakeShadowPow;
                cloudCol += clouds.ambient * sky.denseCol * cloudFakeShadowPow;

                finalSky = sky.skyCol;
                finalSky += sunAttenuation * cloudFakeShadowPow * sunRadiance * _SunIntensity;

                finalSky = lerp(finalSky + cloudCol, cloudCol, cloudFade);
                finalSky += lerp(clouds.direct, 0, clouds.alpha) * sky.transmittance * sky.denseCol;
                finalSky += lerp(clouds.ambient, 0, clouds.alpha) * sky.transmittance * cloudAmbientIntensity;

                // In the real world, stars are always visible, but the atmosphere is too bright for us to see them.
                // As a workaround we can attenuate the stars by the sky brightness. This avoids needing to deal
                // with realistic light ranges, which are difficult to calibrate. 
                float skyLum = dot(sky.skyCol.rgb, 1.0/3.0);
                finalSky.xyz += nightSky / max(1, skyLum * 2000);

                finalSky *= exp2(_Exposure) * cloudyLightFactor;

                return float4(finalSky, 1.0);
            }
            ENDCG
        }
    }
}

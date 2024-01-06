Shader "Hidden/Silent/Atmosphere2/RT/Sky"
{
    Properties
    {
        // Clamp to atmosphere thickness
        _EyeAltitude("Eye Altitude (km)", Range(0.5, 100.0)) = 0.5
        [IntRange]_Month("Month", Range(0, 11)) = 0.0
        _AerosolTurbidity("Aerosol Turbidity", Float) = 1.0
        _GroundAlbedo("Ground Albedo", Color) = (0.3, 0.3, 0.3, 0.3)

        _Transmittance("Transmittance LUT", 2D) = "white" {}
    }

    SubShader
    {
        Lighting On
        Blend One Zero

        CGINCLUDE
            #include "AtmosphereCommon.hlsl"
            sampler2D _Transmittance;

            // Tacked on the option to return "for clouds", which warps the altitude to be zero
            // which gives an appropriate colour for use in cloud rendering. 
            float4 compute_inscattering(float3 ray_origin, float3 ray_dir, float t_d, bool forCloud, out float4 transmittance)
            {
                float3 sun_dir = get_sun_direction(_Time.y);
                float cos_theta = dot(-ray_dir, sun_dir);

                float molecular_phase = molecular_phase_function(cos_theta);
                float aerosol_phase = aerosol_phase_function(cos_theta);

                float dt = t_d / float(IN_SCATTERING_STEPS);

                float4 L_inscattering = (0.0);
                transmittance = (1.0);

                for (int i = 0; i < IN_SCATTERING_STEPS; ++i) {
                    float t = (float(i) + 0.5) * dt;
                    float3 x_t = ray_origin + ray_dir * t;

                    float distance_to_earth_center = length(x_t);
                    float3 zenith_dir = x_t / distance_to_earth_center;
                    float altitude = forCloud ? 0 : distance_to_earth_center - EARTH_RADIUS;
                    float normalized_altitude = altitude / ATMOSPHERE_THICKNESS;

                    float sample_cos_theta = dot(zenith_dir, sun_dir);

                    float4 aerosol_absorption, aerosol_scattering;
                    float4 molecular_absorption, molecular_scattering;
                    float4 extinction;
                    get_atmosphere_collision_coefficients(
                        altitude,
                        aerosol_absorption, aerosol_scattering,
                        molecular_absorption, molecular_scattering,
                        extinction);

                    float4 transmittance_to_sun = transmittance_from_lut(
                        _Transmittance, sample_cos_theta, normalized_altitude);

                    float4 ms = get_multiple_scattering(
                        _Transmittance, sample_cos_theta, normalized_altitude,
                        distance_to_earth_center);

                    float4 S = sun_spectral_irradiance *
                        (molecular_scattering * (molecular_phase * transmittance_to_sun + ms) +
                        aerosol_scattering   * (aerosol_phase   * transmittance_to_sun + ms));

                    float4 step_transmittance = exp(-dt * extinction);

                    // Energy-conserving analytical integration
                    // "Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite"
                    // by Sébastien Hillaire
                    float4 S_int = (S - S * step_transmittance) / max(extinction, 1e-7);
                    L_inscattering += transmittance * S_int;
                    transmittance *= step_transmittance;
                }

                return L_inscattering;
            }
        ENDCG

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float4 fragColor = 0;

                float2 uv = IN.localTexcoord.xy;

                float azimuth = 2.0 * PI * uv.x;

                // Apply a non-linear transformation to the elevation to dedicate more
                // texels to the horizon, where having more detail matters.
                float l = uv.y * 2.0 - 1.0;
                float elev = l*l * sign(l) * PI * 0.5; // [-pi/2, pi/2]

                float3 ray_dir = float3(cos(elev) * cos(azimuth),
                                    cos(elev) * sin(azimuth),
                                    sin(elev));

                float3 ray_origin = float3(0.0, 0.0, EYE_DISTANCE_TO_EARTH_CENTER);

                // This looks bad if we're not at full resolution.
                // ray_origin += _WorldSpaceCameraPos;

                float atmos_dist  = ray_sphere_intersection(ray_origin, ray_dir, ATMOSPHERE_RADIUS);
                float ground_dist = ray_sphere_intersection(ray_origin, ray_dir, EARTH_RADIUS);
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
                } else {
                    // We are in outer space
                    if (atmos_dist < 0.0) {
                        // No collision with the atmosphere, just return black
                        fragColor = float4(0.0, 0.0, 0.0, 1.0);
                        return fragColor;
                    } else {
                        // Move the ray origin to the atmosphere intersection
                        ray_origin = ray_origin + ray_dir * (atmos_dist + 1e-3);
                        if (ground_dist < 0.0) {
                            // No collision with the ground, so the ray is exiting through
                            // the atmosphere.
                            float second_atmos_dist = ray_sphere_intersection(
                                ray_origin, ray_dir, ATMOSPHERE_RADIUS);
                            t_d = second_atmos_dist;
                        } else {
                            t_d = ground_dist - atmos_dist;
                        }
                    }
                }

                // Determine what we're outputting
                const float numLayers = 2.0;
                float layerID = floor(IN.localTexcoord.z * numLayers);

                float4 transmittance;
                float4 L = compute_inscattering(ray_origin, ray_dir, t_d, layerID>=1, transmittance);

            #if ENABLE_SPECTRAL == 1
                fragColor = float4(linear_srgb_from_spectral_samples(L), 1.0);
            #else
                fragColor = float4(L.rgb, 1.0);
            #endif

                return fragColor;
            }
            ENDCG
            }
    }
}
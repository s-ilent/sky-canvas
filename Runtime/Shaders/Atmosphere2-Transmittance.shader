Shader "Hidden/Silent/Atmosphere2/RT/Transmittance"
{
    Properties
    {
    }

    SubShader
    {
        Lighting Off
        Blend One Zero

        Pass
        {
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            #include "AtmosphereCommon.hlsl"

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 uv = IN.localTexcoord.xy;

                float sun_cos_theta = uv.x * 2.0 - 1.0;
                float3 sun_dir = float3(-sqrt(1.0 - sun_cos_theta*sun_cos_theta), 0.0, sun_cos_theta);

                float distance_to_earth_center = lerp(EARTH_RADIUS, ATMOSPHERE_RADIUS, uv.y);
                float3 ray_origin = float3(0.0, 0.0, distance_to_earth_center);

                float t_d = ray_sphere_intersection(ray_origin, sun_dir, ATMOSPHERE_RADIUS);
                float dt = t_d / float(TRANSMITTANCE_STEPS);

                float4 result = (0.0);

                for (int i = 0; i < TRANSMITTANCE_STEPS; ++i) {
                    float t = (float(i) + 0.5) * dt;
                    float3 x_t = ray_origin + sun_dir * t;

                    float altitude = length(x_t) - EARTH_RADIUS;

                    float4 aerosol_absorption, aerosol_scattering;
                    float4 molecular_absorption, molecular_scattering;
                    float4 extinction;
                    get_atmosphere_collision_coefficients(
                        altitude,
                        aerosol_absorption, aerosol_scattering,
                        molecular_absorption, molecular_scattering,
                        extinction);

                    result += extinction * dt;
                }

                float4 transmittance = exp(-result);
                return transmittance;
            }
            ENDCG
            }
    }
}
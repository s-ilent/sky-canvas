#ifndef ATMOSPHERE_COMMON_INCLUDED
#define ATMOSPHERE_COMMON_INCLUDED
// https://www.shadertoy.com/view/msXXDS
/*
 * Copyright (c) 2023 Fernando García Liñán
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

// Configurable parameters

float4 _OverrideSun;

float3 get_sun_direction() // for atmosphere
{
    float3 ldir = (_OverrideSun.w > 0.5) ? normalize(_OverrideSun.xyz) : normalize(_WorldSpaceLightPos0);
    float3 sun_dir = -ldir.xzy;
    sun_dir.z *= -1;
    return sun_dir;
}

float3 getLightDirection() // for clouds
{
    return _OverrideSun.w > 0.5 ? normalize(_OverrideSun.xyz) : normalize(_WorldSpaceLightPos0);
}

float _EyeAltitude;
int _Month;
float _AerosolTurbidity;
float4 _GroundAlbedo;

// 0=Background, 1=Desert Dust, 2=Maritime Clean, 3=Maritime Mineral,
// 4=Polar Antarctic, 5=Polar Artic, 6=Remote Continental, 7=Rural, 8=Urban
// #define AEROSOL_TYPE 8
float _AerosolType;

#if 0
static const float EYE_ALTITUDE          = 0.5;    // km
static const int   MONTH                 = 0;      // 0-11, January to December
static const float AEROSOL_TURBIDITY     = 1.0;
static const float4  GROUND_ALBEDO       = 0.3;
#else
#define EYE_ALTITUDE         _EyeAltitude
#define MONTH                _Month
#define AEROSOL_TURBIDITY    _AerosolTurbidity
#define GROUND_ALBEDO        _GroundAlbedo
#endif
// Ray marching steps. More steps mean better accuracy but worse performance
static const int TRANSMITTANCE_STEPS     = 32;
static const int IN_SCATTERING_STEPS     = 32;

// Debug
#define ENABLE_SPECTRAL 1
#define ENABLE_MULTIPLE_SCATTERING 1
#define ENABLE_AEROSOLS 1

//-----------------------------------------------------------------------------
// Constants

// All parameters that depend on wavelength (float4) are sampled at
// 630, 560, 490, 430 nanometers

static const float PI = 3.14159265358979323846;
static const float INV_PI = 0.31830988618379067154;
static const float INV_4PI = 0.25 * INV_PI;
static const float PHASE_ISOTROPIC = INV_4PI;
static const float RAYLEIGH_PHASE_SCALE = (3.0 / 16.0) * INV_PI;
static const float g = 0.8;
static const float gg = g*g;

static const float EARTH_RADIUS = 6371.0; // km
static const float ATMOSPHERE_THICKNESS = 100.0; // km
static const float ATMOSPHERE_RADIUS = EARTH_RADIUS + ATMOSPHERE_THICKNESS;
static const float EYE_DISTANCE_TO_EARTH_CENTER = EARTH_RADIUS + EYE_ALTITUDE;

#if ENABLE_SPECTRAL == 1
// Extraterrestial Solar Irradiance Spectra, units W * m^-2 * nm^-1
// https://www.nrel.gov/grid/solar-resource/spectra.html
static const float4 sun_spectral_irradiance = float4(1.679, 1.828, 1.986, 1.307);
// Rayleigh scattering coefficient at sea level, units km^-1
// "Rayleigh-scattering calculations for the terrestrial atmosphere"
// by Anthony Bucholtz (1995).
static const float4 molecular_scattering_coefficient_base = float4(6.605e-3, 1.067e-2, 1.842e-2, 3.156e-2);
// Ozone absorption cross section, units m^2 / molecules
// "High spectral resolution ozone absorption cross-sections"
// by V. Gorshelev et al. (2014).
static const float4 ozone_absorption_cross_section = float4(3.472e-21, 3.914e-21, 1.349e-21, 11.03e-23) * 1e-4f;
#else
// Same as above but for the following "RGB" wavelengths: 680, 550, 440 nm
// The Sun spectral irradiance is also multiplied by a constant factor to
// compensate for the fact that we use the spectral samples directly as RGB,
// which is incorrect.
static const float4 sun_spectral_irradiance = float4(1.500, 1.864, 1.715, 0.0) * 150.0;
static const float4 molecular_scattering_coefficient_base = float4(4.847e-3, 1.149e-2, 2.870e-2, 0.0);
static const float4 ozone_absorption_cross_section = float4(3.36e-21f, 3.08e-21f, 20.6e-23f, 0.0) * 1e-4f;
#endif

// Mean ozone concentration in Dobson for each month of the year.
static const float ozone_mean_monthly_dobson[] = {
    347.0, // January
    370.0, // February
    381.0, // March
    384.0, // April
    372.0, // May
    352.0, // June
    333.0, // July
    317.0, // August
    298.0, // September
    285.0, // October
    290.0, // November
    315.0  // December
};

/*
 * Every aerosol type expects 5 parameters:
 * - Scattering cross section
 * - Absorption cross section
 * - Base density (km^-3)
 * - Background density (km^-3)
 * - Height scaling parameter
 * These parameters can be sent as uniforms.
 *
 * This model for aerosols and their corresponding parameters come from
 * "A Physically-Based Spatio-Temporal Sky Model"
 * by Guimera et al. (2018).
 */
struct Aerosol {
    float4 absorption_cross_section;
    float4 scattering_cross_section;
    float base_density;
    float background_density;
    float height_scale;
};

Aerosol getAerosol(int AEROSOL_TYPE) {
    Aerosol aerosol = (Aerosol)0;
    switch (AEROSOL_TYPE) {
        case 0: // Background
            aerosol.absorption_cross_section = float4(4.5517e-19, 5.9269e-19, 6.9143e-19, 8.5228e-19);
            aerosol.scattering_cross_section = float4(1.8921e-26, 1.6951e-26, 1.7436e-26, 2.1158e-26);
            aerosol.base_density = 2.584e17;
            aerosol.background_density = 2e6;
            break;
        case 1: // Desert Dust
            aerosol.absorption_cross_section = float4(4.6758e-16, 4.4654e-16, 4.1989e-16, 4.1493e-16);
            aerosol.scattering_cross_section = float4(2.9144e-16, 3.1463e-16, 3.3902e-16, 3.4298e-16);
            aerosol.base_density = 1.8662e18;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 2.0;
            break;
        case 2: // Maritime Clean
            aerosol.absorption_cross_section = float4(6.3312e-19, 7.5567e-19, 9.2627e-19, 1.0391e-18);
            aerosol.scattering_cross_section = float4(4.6539e-26, 2.721e-26, 4.1104e-26, 5.6249e-26);
            aerosol.base_density = 2.0266e17;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 0.9;
            break;
        case 3: // Maritime Mineral
            aerosol.absorption_cross_section = float4(6.9365e-19, 7.5951e-19, 8.2423e-19, 8.9101e-19);
            aerosol.scattering_cross_section = float4(2.3699e-19, 2.2439e-19, 2.2126e-19, 2.021e-19);
            aerosol.base_density = 2.0266e17;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 2.0;
            break;
        case 4: // Polar Antarctic
            aerosol.absorption_cross_section = float4(1.3399e-16, 1.3178e-16, 1.2909e-16, 1.3006e-16);
            aerosol.scattering_cross_section = float4(1.5506e-19, 1.809e-19, 2.3069e-19, 2.5804e-19);
            aerosol.base_density = 2.3864e16;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 30.0;
            break;
        case 5: // Polar Arctic
            aerosol.absorption_cross_section = float4(1.0364e-16, 1.0609e-16, 1.0193e-16, 1.0092e-16);
            aerosol.scattering_cross_section = float4(2.1609e-17, 2.2759e-17, 2.5089e-17, 2.6323e-17);
            aerosol.base_density = 2.3864e16;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 30.0;
            break;
        case 6: // Remote Continental
            aerosol.absorption_cross_section = float4(4.5307e-18, 5.0662e-18, 4.4877e-18, 3.7917e-18);
            aerosol.scattering_cross_section = float4(1.8764e-18, 1.746e-18, 1.6902e-18, 1.479e-18);
            aerosol.base_density = 6.103e18;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 0.73;
            break;
        case 7: // Rural
            aerosol.absorption_cross_section = float4(5.0393e-23, 8.0765e-23, 1.3823e-22, 2.3383e-22);
            aerosol.scattering_cross_section = float4(2.6004e-22, 2.4844e-22, 2.8362e-22, 2.7494e-22);
            aerosol.base_density = 8.544e18;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 0.73;
            break;
        case 8: // Urban
            aerosol.absorption_cross_section = float4(2.8722e-24, 4.6168e-24, 7.9706e-24, 1.3578e-23);
            aerosol.scattering_cross_section = float4(1.5908e-22, 1.7711e-22, 2.0942e-22, 2.4033e-22);
            aerosol.base_density = 1.3681e20;
            aerosol.background_density = 2e6;
            aerosol.height_scale = 0.73;
            break;
        default:
            // Handle invalid AEROSOL_TYPE here
            break;
    }
    return aerosol;
}

//static const float aerosol_background_divided_by_base_density = aerosol_background_density / aerosol_base_density;

//-----------------------------------------------------------------------------


/*
 * Helper function to obtain the transmittance to the top of the atmosphere
 * from the lookup table.
 */
float4 transmittance_from_lut(sampler2D lut, float cos_theta, float normalized_altitude)
{
    float u = clamp(cos_theta * 0.5 + 0.5, 0.0, 1.0);
    float v = clamp(normalized_altitude, 0.0, 1.0);
    return tex2D(lut, float2(u, v));
}

/*
 * Returns the distance between ro and the first intersection with the sphere
 * or -1.0 if there is no intersection. The sphere's origin is (0,0,0).
 * -1.0 is also returned if the ray is pointing away from the sphere.
 */
float ray_sphere_intersection(float3 ro, float3 rd, float radius)
{
    float b = dot(ro, rd);
    float c = dot(ro, ro) - radius*radius;
    if (c > 0.0 && b > 0.0) return -1.0;
    float d = b*b - c;
    if (d < 0.0) return -1.0;
    if (d > b*b) return (-b+sqrt(d));
    return (-b-sqrt(d));
}

/*
 * Rayleigh phase function.
 */
float molecular_phase_function(float cos_theta)
{
    return RAYLEIGH_PHASE_SCALE * (1.0 + cos_theta*cos_theta);
}

/*
 * Henyey-Greenstrein phase function.
 */
float aerosol_phase_function(float cos_theta)
{
    float den = 1.0 + gg + 2.0 * g * cos_theta;
    return INV_4PI * (1.0 - gg) / (den * sqrt(den));
}

float4 get_multiple_scattering(sampler2D transmittance_lut, float cos_theta, float normalized_height, float d)
{
#if ENABLE_MULTIPLE_SCATTERING == 1
    // Solid angle subtended by the planet from a point at d distance
    // from the planet center.
    float omega = 2.0 * PI * (1.0 - sqrt(d*d - EARTH_RADIUS*EARTH_RADIUS) / d);

    float4 T_to_ground = transmittance_from_lut(transmittance_lut, cos_theta, 0.0);

    float4 T_ground_to_sample =
        transmittance_from_lut(transmittance_lut, 1.0, 0.0) /
        transmittance_from_lut(transmittance_lut, 1.0, normalized_height);

    // 2nd order scattering from the ground
    float4 L_ground = PHASE_ISOTROPIC * omega * (GROUND_ALBEDO / PI) * T_to_ground * T_ground_to_sample * cos_theta;

    // Fit of Earth's multiple scattering coming from other points in the atmosphere
    float4 L_ms = 0.02 * float4(0.217, 0.347, 0.594, 1.0) * (1.0 / (1.0 + 5.0 * exp(-17.92 * cos_theta)));

    return L_ms + L_ground;
#else
    return float4(0.0);
#endif
}

/*
 * Return the molecular volume scattering coefficient (km^-1) for a given altitude
 * in kilometers.
 */
float4 get_molecular_scattering_coefficient(float h)
{
    return molecular_scattering_coefficient_base * exp(-0.07771971 * pow(h, 1.16364243));
}

/*
 * Return the molecular volume absorption coefficient (km^-1) for a given altitude
 * in kilometers.
 */
float4 get_molecular_absorption_coefficient(float h)
{
    h += 1e-4; // Avoid division by 0
    float t = log(h) - 3.22261;
    float density = 3.78547397e20 * (1.0 / h) * exp(-t * t * 5.55555555);
    return ozone_absorption_cross_section * ozone_mean_monthly_dobson[MONTH] * density;
}

float get_aerosol_density(float h, Aerosol aerosol)
{
    if (aerosol.height_scale == 0.0) { // Only for the Background aerosol type, no dependency on height
        return aerosol.base_density * (1.0 + aerosol.background_density / aerosol.base_density);
    } else {
        return aerosol.base_density * (exp(-h / aerosol.height_scale)
            + aerosol.background_density / aerosol.base_density);
    }
}

/*
 * Get the collision coefficients (scattering and absorption) of the
 * atmospheric medium for a given point at an altitude h.
 */
void get_atmosphere_collision_coefficients(in float h,
                                           out float4 aerosol_absorption,
                                           out float4 aerosol_scattering,
                                           out float4 molecular_absorption,
                                           out float4 molecular_scattering,
                                           out float4 extinction,
                                           Aerosol aerosol)
{
    h = max(h, 0.0); // In case height is negative
#if ENABLE_AEROSOLS == 0
    aerosol_absorption = (0.0);
    aerosol_scattering = (0.0);
#else
    float aerosol_density = get_aerosol_density(h, aerosol);
    aerosol_absorption = aerosol.absorption_cross_section * aerosol_density * AEROSOL_TURBIDITY;
    aerosol_scattering = aerosol.scattering_cross_section * aerosol_density * AEROSOL_TURBIDITY;
#endif
    molecular_absorption = get_molecular_absorption_coefficient(h);
    molecular_scattering = get_molecular_scattering_coefficient(h);
    extinction = aerosol_absorption + aerosol_scattering + molecular_absorption + molecular_scattering;
}

//-----------------------------------------------------------------------------
// Spectral rendering stuff

const float3x4 M = transpose(float4x3(
    137.672389239975, -8.632904716299537, -1.7181567391931372,
    32.549094028629234, 91.29801417199785, -12.005406444382531,
    -38.91428392614275, 34.31665471469816, 29.89044807197628,
    8.572844237945445, -11.103384660054624, 117.47585277566478
));

float3 linear_srgb_from_spectral_samples(float4 L)
{
    return mul(M, L);
}

//-----------------------------------------------------------------------------
// Sampling hack stuff
float2 UnStereo(float2 UV)
{
    #if UNITY_SINGLE_PASS_STEREO
    float4 scaleOffset = unity_StereoScaleOffset[unity_StereoEyeIndex];
    UV.xy = (UV.xy - scaleOffset.zw) / scaleOffset.xy;
    #endif
    return UV;
}

sampler2D _blueNoise;
float4 _blueNoise_TexelSize;

float2 SampleBlueNoise(float2 texcoords, float4 screenPos, float4 scaleOffset, float4 texelSize)
{
    texcoords = texcoords * scaleOffset.xy + scaleOffset.zw;
    float2 uv_scaled = texcoords * texelSize.zw;

    float4 screenPosNorm = screenPos / screenPos.w;
    screenPosNorm.z = (UNITY_NEAR_CLIP_VALUE >= 0) ? screenPosNorm.z : screenPosNorm.z * 0.5 + 0.5;
    float2 UV = UnStereo(screenPosNorm.xy);

    UV = floor(UV * _ScreenParams);
    UV += floor(_Time.x * _blueNoise_TexelSize.zw);

    float4 blueNoise = tex2D(_blueNoise, UV * _blueNoise_TexelSize.xy);
    float timeScaled = frac(_Time.y * 3.0);

    float2 lerpResult = lerp(blueNoise, blueNoise.gb, saturate(floor((timeScaled % 0.3333333) * 12.0)));
    lerpResult = lerp(lerpResult, blueNoise.br, saturate(floor((timeScaled % 0.3333333) * 6.0)));

    float2 uv_gradient = float2(ddx(texcoords.x), ddy(texcoords.y));
    float2 uv_clamped = clamp(0.125 / (abs(uv_gradient) * texelSize.zw), float2(-1, -1), float2(1, 1));

    return texelSize * float4(floor(uv_scaled) + frac(uv_scaled) + (lerpResult.rg - 0.5) * uv_clamped, 0.0, 0.0);
}

//-----------------------------------------------------------------------------
// Code from https://www.shadertoy.com/view/4XffzH
// MIT License - Copyright (c) 2024 Felix Westin

float GetSunDisc(float3 rayDir, float3 lightDir, float sunDiscSize = 1.0)
{
    const float A = cos(0.00436 * sunDiscSize);
	float costh = dot(rayDir, lightDir);
	float disc = sqrt(smoothstep(A, 1.0, costh));
	return disc;
}

//-----------------------------------------------------------------------------
float3 r3_modified(in float idx, in float3 seed)
{
    return frac(seed + float(idx) * float3(0.180827486604, 0.328956393296, 0.450299522098));
}

#endif // ATMOSPHERE_COMMON_INCLUDED
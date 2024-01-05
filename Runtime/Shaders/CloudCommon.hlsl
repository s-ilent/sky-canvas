// Common vars
/*
        static const float PI = 3.14159265358979323846;
        static const float INV_PI = 0.31830988618379067154;
        static const float INV_4PI = 0.25 * INV_PI;
        static const float PHASE_ISOTROPIC = INV_4PI;
        static const float RAYLEIGH_PHASE_SCALE = (3.0 / 16.0) * INV_PI;
        static const float g = 0.8;
        static const float gg = g*g;

        static const float EYE_ALTITUDE          = 0.5;    // km

        static const float EARTH_RADIUS = 6371.0; // km
        static const float ATMOSPHERE_THICKNESS = 100.0; // km
        static const float ATMOSPHERE_RADIUS = EARTH_RADIUS + ATMOSPHERE_THICKNESS;
        static const float EYE_DISTANCE_TO_EARTH_CENTER = EARTH_RADIUS + EYE_ALTITUDE;
*/
        static const float km = 1000.0;
        static const int noiseLoop = 5; // Number of noise loops, higher values increase quality but make processing heavier
        static const float planetR_km = 6000;// Planet radius (in km)
        static const float cloudHeight_km = 10;// Height from the ground where clouds are generated
        static const float adjustRate_km = 15;// Reference value for cloud adjustment process (lower values make it more detailed but discontinuous)
        static const float adjustOffset = 1; // Number of times the cloud adjustment process is not performed (higher values mean it won't be performed for closer clouds)
        static const float adjustMax = 4; // Maximum number of cloud adjustment processes (higher values cause striped patterns to appear below the horizon, lower values make the area near the horizon more detailed)
        static const float scaleBase = 10; // Change in resolution base of size
        
        // Approximately earth sizes
        static const float g_radius = 6000000.0; //ground radius
        static const float sky_b_radius = 6001500.0;//bottom of cloud layer
        static const float sky_t_radius = 6004000.0;//top of cloud layer

// Functions

float interleavedGradientNoise(float2 n) {
    float f = 0.06711056 * n.x + 0.00583715 * n.y;
    return frac(52.9829189 * frac(f));
}

// From: https://www.shadertoy.com/view/4sfGzS credit to iq
float hash(float3 p) {
	p  = frac( p * 0.3183099 + 0.1 );
	p *= 17.0;
	return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Utility function that maps a value from one range to another. 
float remap(float originalValue,  float originalMin,  float originalMax,  float newMin,  float newMax) {
	return newMin + (((originalValue - originalMin) / (originalMax - originalMin)) * (newMax - newMin));
}

// plane degined by p (p.xyz must be normalized)
float plaIntersect( in float3 ro, in float3 rd, in float4 p )
{
    return -(dot(ro,p.xyz)+p.w)/dot(rd,p.xyz);
}

float2 sphIntersect( in float3 ro, in float3 rd, in float3 ce, float ra )
{
    float3 oc = ro - ce;
    float b = dot( oc, rd );
    float3 qc = oc - b*rd;
    float h = ra*ra - dot( qc, qc );
    if( h<0.0 ) return (-1.0); // no intersection
    h = sqrt( h );
    float t0 = -b-h;
    float t1 = -b+h;
    //if (t0 < 0.0) t0 = t1; // if t0 is negative, use t1 instead
    return float2(t0, t1);
}

float intersectSphere(float3 pos, float3 dir,float r) {
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, pos);
    float c = dot(pos, pos) - (r * r);
	float d = sqrt((b*b) - 4.0*a*c);
	float p = -b - d;
	float p2 = -b + d;
    return max(p, p2) / (2.0 * a);
}

// https://s3.amazonaws.com/gran-turismo.com/pdi_publications/GDC2023_GT7_SKY_RENDERING.pdf
float2 gbufferUVtoPolarCoordinates(float u, float v)
{
    u -= 0.5f;
    v -= 0.5f;
    const float phi = atan2(v, u);
    const float R = 0.5f / cos(fmod(phi + PI/4 + 2*PI, PI/2) - PI/4);
    const float x01 = sqrt(length(float2(u, v)) / R);
    const float theta = x01 * (PI/2);
    return float2(theta, phi);
}

float2 directionToGbufferUV(float3 direction)
{
    const float PI = 3.14159265358979323846f;
    float theta = acos(direction.y); // zenith angle
    float phi = atan2(direction.z, direction.x); // azimuthal angle
    if (phi < 0.0f)
        phi += 2.0f * PI; // ensure azimuthal angle is in [0, 2PI]
    float R = 0.5f / cos(fmod(phi + PI/4 + 2*PI, PI/2) - PI/4);
    float x01 = theta / (PI/2);
    float len = x01 * x01 * R;
    float u = len * cos(phi) + 0.5f;
    float v = len * sin(phi) + 0.5f;
    return float2(u, v);
}

float3 polarCoordinatesToDirection(float theta, float phi)
{
    const float PI = 3.14159265358979323846f;
    float3 direction;
    direction.x = sin(theta) * cos(phi);
    direction.y = cos(theta);
    direction.z = sin(theta) * sin(phi);
    return direction;
}


// Henyey-Greenstein
// adapted from: https://github.com/SebLague/Clouds/blob/master/Assets/Scripts/Clouds/Shaders/Clouds.shader
float hg(float a, float g)
{
    float g2 = g*g;
    return (1.0f-g2) / (4.0f*PI*pow(1.0f+g2-2.0f*g*a, 1.5f));
}
float phase(float a, float forwardScattering, float backScattering, float phaseFactor)
{
    float blend = 0.5f;
    float hgBlend = hg(a,forwardScattering) * (1-blend) + hg(a,backScattering) * blend;
    return hgBlend*phaseFactor;
}

// From https://github.com/clayjohn/godot-volumetric-cloud-demo
// Cloud Raymarching based on: A. Schneider. “The Real-Time Volumetric Cloudscapes Of Horizon: Zero Dawn”. ACM SIGGRAPH. Los Angeles, CA: ACM SIGGRAPH, 2015. Web. 26 Aug. 2015.

// Phase function
float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

float GetHeightFractionForPoint(float inPosition) { 
	float height_fraction = (inPosition -  sky_b_radius) / (sky_t_radius - sky_b_radius); 
	return saturate(height_fraction);
}

float4 mixGradients(float cloudType){
	const float4 STRATUS_GRADIENT = float4(0.02f, 0.05f, 0.09f, 0.11f);
	const float4 STRATOCUMULUS_GRADIENT = float4(0.02f, 0.2f, 0.48f, 0.625f);
	const float4 CUMULUS_GRADIENT = float4(0.01f, 0.0625f, 0.78f, 1.0f);
	float stratus = 1.0f - clamp(cloudType * 2.0f, 0.0, 1.0);
	float stratocumulus = 1.0f - abs(cloudType - 0.5f) * 2.0f;
	float cumulus = saturate(cloudType - 0.5f) * 2.0f;
	return STRATUS_GRADIENT * stratus + STRATOCUMULUS_GRADIENT * stratocumulus + CUMULUS_GRADIENT * cumulus;
}

float densityHeightGradient(float heightFrac, float cloudType) {
	float4 cloudGradient = mixGradients(cloudType);
	return smoothstep(cloudGradient.x, cloudGradient.y, heightFrac) - smoothstep(cloudGradient.z, cloudGradient.w, heightFrac);
}


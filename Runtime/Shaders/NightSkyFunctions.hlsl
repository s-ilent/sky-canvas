/*
Stars and galaxy 
Created by mrange in 2022-04-10

License CC0: Stars and galaxy
Bit of sunday tinkering lead to stars and a galaxy
Didn't turn out as I envisioned but it turned out to something
that I liked so sharing it.
*/

#define glsl_mod(x,y) (((x)-(y)*floor((x)/(y))))

float tanh_approx(float x)
{
    float x2 = x*x;
    return clamp(x*(27.+x2)/(27.+9.*x2), -1., 1.);
}

static const float4 hsv2rgb_K = float4(1., 2./3., 1./3., 3.);
float3 hsv2rgb(float3 c)
{
    float3 p = abs(frac(c.xxx+hsv2rgb_K.xyz)*6.-hsv2rgb_K.www);
    return c.z*lerp(hsv2rgb_K.xxx, clamp(p-hsv2rgb_K.xxx, 0., 1.), c.y);
}

float2 mod2(inout float2 p, float2 size)
{
    float2 c = floor((p+size*0.5)/size);
    p = glsl_mod(p+size*0.5, size)-size*0.5;
    return c;
}
float2 hash2(float2 p)
{
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return frac(sin(p)*43758.547);
}
float2 shash2(float2 p)
{
    return -1.+2.*hash2(p);
}

float3 convertToSphericalCoordinates(float3 cartesianCoordinates)
{
    float radius = length(cartesianCoordinates);
    float theta = acos(cartesianCoordinates.z / radius);
    float phi = atan2(cartesianCoordinates.y, cartesianCoordinates.x);
    return float3(radius, theta, phi);
}

float3 calculateBlackbodyRadiationColor(float temperature)
{
    float3 color = float3(255, 255, 255);
    color.x = 56100000.0 * pow(temperature, -1.5) + 148.0;
    color.y = 100.04 * log(temperature) - 623.6;

    if (temperature > 6500.0)
    {
        color.y = 35200000.0 * pow(temperature, -1.5) + 184.0;
    }

    color.z = 194.18 * log(temperature) - 1448.6;
    color = clamp(color, 0.0, 255.0) / 255.0;

    if (temperature < 1000.0)
    {
        color *= temperature / 1000.0;
    }

    return color;
}


float3 stars(float2 sp, float hh)
{
    float3 color = float3(0, 0, 0);
    const float numLayers = 5.0; // Number of star layers

    hh = tanh_approx(20.0 * hh);

    for (float i = 0.0; i < numLayers; ++i)
    {
        float2 position = sp + 0.5 * i;
        float layerFraction = i / (numLayers - 1.0);
        float2 dimension = lerp(0.05, 0.003, layerFraction) * PI;
        float2 normalizedPosition = mod2(position, dimension);
        float2 hashValue = hash2(normalizedPosition + 127.0 + i);
        float2 offset = -1.0 + 2.0 * hashValue;
        float y = sin(sp.x);
        position += offset * dimension * 0.5;
        position.y *= y;
        float pLength = length(position);
        float hash1 = frac(hashValue.x * 1667.0);
        float hash2 = frac(hashValue.x * 1887.0);
        float hash3 = frac(hashValue.x * 2997.0);
        float3 starColor = lerp(8.0 * hash2, 0.25 * hash2 * hash2, layerFraction) 
            * calculateBlackbodyRadiationColor(lerp(3000.0, 22000.0, hash1 * hash1));
        float3 combinedColor = color + exp(-(lerp(6000.0, 2000.0, hh) / lerp(2.0, 0.25, layerFraction)) 
            * max(pLength - 0.001, 0.0)) * starColor;
        color = hash3 < y ? combinedColor : color;
    }

    return color;
}


float3 sky(float3 ro, float3 rd, float2 sp, float3 lp, out float cf)
{
    cf = 0;
    float ld = max(dot(normalize(lp-ro), rd), 0.);
    float y = -0.5+sp.x/PI;
    y = max(abs(y)-0.02, 0.)+0.1*smoothstep(0.5, PI, abs(sp.y));
    float3 blue = hsv2rgb(float3(0.6, 0.75, 0.35*exp(-15.*y)));
    float ci = pow(ld, 10.)*2.*exp(-25.*y);
    float3 yellow = calculateBlackbodyRadiationColor(1500.)*ci;
    cf = ci;
    return blue+yellow;
}

float2 raySphere(float3 ro, float3 rd, float4 sph)
{
    float3 oc = ro-sph.xyz;
    float b = dot(oc, rd);
    float c = dot(oc, oc)-sph.w*sph.w;
    float h = b*b-c;
    if (h<0.)
        return ((float2)-1.);
        
    h = sqrt(h);
    return float2(-b-h, -b+h);
}

float4 moon(float3 ro, float3 rd, float2 sp, float3 lp, float4 md)
{
    float2 mi = raySphere(ro, rd, md);
    float3 p = ro+mi.x*rd;
    float3 n = normalize(p-md.xyz);
    float3 r = reflect(rd, n);
    float3 ld = normalize(lp-p);
    float fre = dot(n, rd)+1.;
    fre = pow(fre, 15.);
    float dif = max(dot(ld, n), 0.);
    float spe = pow(max(dot(ld, r), 0.), 8.);
    float i = 0.5*tanh_approx(20.*fre*spe+0.05*dif);
    float3 col = calculateBlackbodyRadiationColor(1500.)*i+hsv2rgb(float3(0.6, lerp(0.6, 0., i), i));
    float t = tanh_approx(0.25*(mi.y-mi.x));
    return float4(((float3)col), t);
}

float3 getNightSky(float3 ro, float3 rd)
{
    float2 sp = convertToSphericalCoordinates(rd.xzy).yz;
    float sf = 0.;
    float cf = 0.;

	return stars(sp, sf)*(1.-tanh_approx(2.*cf));
}

float3 getNightHaze(float3 ro, float3 rd, float3 lp_in)
{
    float2 sp = convertToSphericalCoordinates(rd.xzy).yz;
    float sf = 0.;
    float cf = 0.;
	//float3 lp = float3(1., -0.25, 0.) + 500.0;
    float3 lp = lp_in + 500.0;

	return sky(ro, rd, sp, lp, cf);
}

float4 getMoon(float3 ro, float3 rd)
{
    float2 sp = convertToSphericalCoordinates(rd.xzy).yz;
	float3 lp = 500.*float3(1., -0.25, 0.);
	float4 md = 50.*float4(float3(1., 1., -0.6), 0.5);

	return moon(ro, rd, sp, lp, md);
}

#undef glsl_mod
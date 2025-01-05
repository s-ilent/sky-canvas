Shader "Silent/CustomRenderTexture/Clouds"
{
    Properties
    {
        _WorlNoise("Worley Noise", 3D) = "white" {}
        _PerlWorlNoise("Perlin-Worley Noise", 3D) = "white" {}
        _WeatherMap("Weather Map", 2D) = "red" {}
        [Space]
        _WindDirection("Wind Direction", Vector) = (1, 0, 0, 0)
        _WindSpeed("Wind Speed", Range(0.0, 20.0)) = 1.0
        _Density("Density", Range(0.01, 0.2)) = 0.05
        _CloudCoverage("Cloud Coverage", Range(0.1, 1.0)) = 0.25
        [Space]
        _CloudHeightOffset("Cloud Height Offset (km) (not recommended)", Float) = 0.5
        _CameraPositionOffset("Camera Position Offset", Vector) = (0,0,0,0)
        [Space]
        _OverrideSun("Override Sun Position", Vector) = (0,0,0,0)
        // Needed to avoid weird editor bug
        _OverrideTime("Override Time", Vector) = (0,0,0,0)

        [Toggle(_TEMPORAL_FILTER)]_TemporalFilter("Temporal Filter (requires double-buffering)", Float) = 0

        [HideInInspector][NonModifiableTextureData]_TANoiseTex ("TANoise", 2D) = "white" {}
    }

    SubShader
    {
        Lighting Off
        Blend One Zero
        CGINCLUDE
        #pragma shader_feature _ _TEMPORAL_FILTER
        #include "tanoise/tanoise.cginc"
        #include "AtmosphereCommon.hlsl"
        #include "CloudCommon.hlsl"

        #define MIP_QUAD_OPTIMIZATION 0
        #include "QuadIntrinsics.cginc"

        float _CloudThickness;

        sampler3D _WorlNoise;
        sampler3D _PerlWorlNoise;
        sampler2D _WeatherMap;
        float2 _WindDirection;
        float _WindSpeed;
        float _Density;
        float _CloudCoverage;
        float _CloudHeightOffset;
        float4 _CameraPositionOffset;
        float4 _OverrideTime;

        sampler3D _SkyTexture;

float3 atmosphere(float3 rayDir)
{
    // Sky radiance sampling 
    float phi = atan2(rayDir.z, rayDir.x);
    float theta = asin(rayDir.y);

    float azimuth = phi / PI * 0.5 + 0.5;   // Undo the non-linear transformation from the sky-view LUT
    float elev = sqrt(abs(theta) / (PI * 0.5)) * sign(theta) * 0.5 + 0.5;   
    return tex3D(_SkyTexture, float3(azimuth, elev, 0));
}

// Use a global to avoid comparison within the density loop
// This ends up being needed to avoid problems with the editor not setting _Time properly for CRTs
// although technically "Time since level load" is invalid in Editor anyway. 
float4 localTime;

// Cloud rendering based on https://github.com/clayjohn/godot-volumetric-cloud-demo
// Cloud Raymarching based on: A. Schneider. “The Real-Time Volumetric Cloudscapes Of Horizon: Zero Dawn”. ACM SIGGRAPH. Los Angeles, CA: ACM SIGGRAPH, 2015. Web. 26 Aug. 2015.
// Additions based on "Realistic Real-Time Sky Dome Rendering in 'Gran Turismo 7'" by Kentaro Suzuki, Kenichiro Yasutomi

// Returns density at a given point
// Heavily based on method from Schneider
float density(float3 pip, float3 weather, float mip) {
	float time = localTime.y;
	float3 p = pip;
	float height_fraction = GetHeightFractionForPoint(length(p));
	p.xz += time * 20.0 * normalize(_WindDirection) * _WindSpeed * 0.6;
	float4 n = tex3Dlod(_PerlWorlNoise, float4(p.xyz*0.00008, mip-2.0));
	float fbm = n.g*0.625+n.b*0.25+n.a*0.125;
	float g = densityHeightGradient(height_fraction, weather.r);
	float base_cloud = remap(n.r, -(1.0-fbm), 1.0, 0.0, 1.0);
	float weather_coverage = _CloudCoverage*weather.b;
	base_cloud = remap(base_cloud*g, 1.0-(weather_coverage), 1.0, 0.0, 1.0);
	base_cloud *= weather_coverage;
	p.xz -= time * normalize(_WindDirection) * 40.;
	p.y -= time * 40.;
	float3 hn = tex3Dlod(_WorlNoise, float4(p*0.001, mip)).rgb;
	float hfbm = hn.r*0.625+hn.g*0.25+hn.b*0.125;
	hfbm = lerp(hfbm, 1.0-hfbm, clamp(height_fraction*4.0, 0.0, 1.0));
	base_cloud = remap(base_cloud, hfbm*0.4 * height_fraction, 1.0, 0.0, 1.0);
	return pow(clamp(base_cloud, 0.0, 1.0), (1.0 - height_fraction) * 0.8 + 0.5);
}

float4 march(float3 pos,  float3 end, float3 dir, int depth) {
	const float3 RANDOM_VECTORS[6] = 
        {   float3( 0.38051305f,  0.92453449f, -0.02111345f),
            float3(-0.50625799f, -0.03590792f, -0.86163418f),
            float3(-0.32509218f, -0.94557439f,  0.01428793f),
            float3( 0.09026238f, -0.27376545f,  0.95755165f),
            float3( 0.28128598f,  0.42443639f, -0.86065785f),
            float3(-0.16852403f,  0.14748697f,  0.97460106f)    };
	float T = 1.0;
	float alpha = 0.0;
	float ss = length(dir);
	dir = normalize(dir);
	float3 p = pos + dir * hash(pos * 10.0) * ss;
	const float t_dist = sky_t_radius-sky_b_radius;
	float lss = (t_dist / 36.0);
	float3 ldir = getLightDirection();
	float3 L = (0.0);
	int count=0;
	float t = 1.0;
	float costheta = dot(ldir, dir);
	// Stack multiple phase functions to emulate some backscattering
	float phase = max(max(henyey_greenstein(costheta, 0.6), henyey_greenstein(costheta, (0.4 - 1.4 * ldir.y))), henyey_greenstein(costheta, -0.2));
	
	const float weather_scale = 0.00006;
	float time = localTime.x;
	float2 weather_pos = time * normalize(_WindDirection) * _WindSpeed;
    
    float distanceToCloud = 0.0;
    float distanceTraveled = 0.0;
    
    float sunLighting = 0.0;
    float ambientLighting = 0.0;
	
	for (int i = 0; i < depth; i++) {
		p += dir * ss;
        distanceTraveled += ss;
		float3 weather_sample = tex2Dlod(_WeatherMap, float4(p.xz * weather_scale + 0.5 + weather_pos, 0, 0)).xyz;
		float height_fraction = GetHeightFractionForPoint(length(p));

		t = density(p, weather_sample, 0.0);
		float dt = exp(-_Density*t*ss);
		T *= dt;
		float3 lp = p;
		float lt = 1.0;
		float cd = 0.0;

		if (t > 0.0) { //calculate lighting, but only when we are in the cloud
			float lheight_fraction = 0.0;
			for (int j = 0; j < 6; j++) {
				lp += (ldir + RANDOM_VECTORS[j]*float(j))*lss;
				lheight_fraction = GetHeightFractionForPoint(length(lp));
				float3 lweather = tex2Dlod(_WeatherMap, float4(lp.xz * weather_scale + 0.5 + weather_pos, 0, 0)).xyz;
				lt = density(lp, lweather, float(j));
				cd += lt;
			}
			
			// Take a single distant sample
			lp = p + ldir * 18.0 * lss;
			lheight_fraction = GetHeightFractionForPoint(length(lp));
			float3 lweather = tex2Dlod(_WeatherMap, float4(lp.xz * weather_scale + 0.5, 0, 0)).xyz;
			lt = pow(density(lp, lweather, 5.0), (1.0 - lheight_fraction) * 0.8 + 0.5);
			cd += lt;
			
			// captures the direct lighting from the sun
			float beers = exp(-_Density * cd * lss);
			float beers2 = exp(-_Density * cd * lss * 0.25) * 0.7;
			float beers_total = max(beers, beers2);

            // approximate ambient lighting by cloud height
            // todo: better approximation
            float ambient = height_fraction;

			alpha += (1.0 - dt) * (1.0 - alpha);
            sunLighting += beers_total * phase * alpha * T * t;
            ambientLighting += ambient * t * T; 
            distanceToCloud = distanceTraveled;
		}
	}
    return float4(distanceToCloud, sunLighting, ambientLighting, alpha);
}

        ENDCG

        Pass
        {
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 5.0

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                // The origin of the ray-marching is the center of the world, then the upper hemisphere is rendered from the origin.
                // Here, we optimize the texel distributions so that more texels are assigned near the horizon.
                float2 position = gbufferUVtoPolarCoordinates(IN.localTexcoord.x, IN.localTexcoord.y); 

                #if MIP_QUAD_OPTIMIZATION
                SETUP_QUAD_INTRINSICS(IN.vertex);
                #endif

                float3 rayDir = polarCoordinatesToDirection(position.x, position.y);
                float3 rayOrigin = 0;

                float3 dir = rayDir;
                
                #if MIP_QUAD_OPTIMIZATION
                dir = QuadSum(dir) * 0.25f;
                #endif

                localTime = _OverrideTime.w > 0.5 ? _OverrideTime : _Time;


                float3 camPos = float3(0.0, g_radius, 0.0);
                camPos += _CameraPositionOffset;
                camPos.y += _CloudHeightOffset * 1000.0;

                #if _TEMPORAL_FILTER
                float3 camNoise = r3_modified(_Time.y * 100, 0) * 6 - 3;
                camPos += camNoise;
                #endif

                float3 start = camPos + dir * intersectSphere(camPos, dir, sky_b_radius);
                float3 end = camPos + dir * intersectSphere(camPos, dir, sky_t_radius);
                float shelldist = (length(end-start));
                // Take fewer steps towards horizon
                float steps = 96.0; //(lerp(96.0, 54.0, clamp(dot(dir, float3(0.0, 1.0, 0.0)), 0.0, 1.0)));
                float3 raystep = dir * shelldist / steps;
                
                #if MIP_QUAD_OPTIMIZATION
                    int quadID =  (QuadGetLaneID() + 1.0);
                    // ray interleaving within mip quad
                    float forward = raystep * quadID;
                    start += forward;
                    end += forward;
                    steps /= 4.0f; 
                #endif

                float4 clouds = march(start, end, raystep, int(steps));
                
                #if MIP_QUAD_OPTIMIZATION
                clouds = QuadSum(clouds) * 0.25f;
                #endif

                #if _TEMPORAL_FILTER
                float4 minColor = 9999.0, maxColor = -9999.0;
                float4 previousColor = tex2D(_SelfTexture2D, IN.localTexcoord); 
                
                for(int x = -1; x <= 1; ++x)
                {
                    for(int y = -1; y <= 1; ++y)
                    {
                        float4 color = tex2D(_SelfTexture2D, IN.localTexcoord + float2(x, y) / float2(_CustomRenderTextureWidth, _CustomRenderTextureHeight)); 
                        minColor = min(minColor, color); 
                        maxColor = max(maxColor, color);
                    }
                }
                
                float4 previousColorClamped = clamp(previousColor, minColor, maxColor);
                float4 output = clouds * 0.1 + previousColorClamped * 0.9;
                return output;
                #endif

                return clouds;
            }
        ENDCG
        }
    }
}
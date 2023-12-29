#ifndef ATMOSPHERE_CLOUDS_INCLUDED
#define ATMOSPHERE_CLOUDS_INCLUDED

/*
	=================================================
	TowelCloud

	Copyright (c) 2020-2022 towel_funnel

	This software is released under the Zlib License.
	https://opensource.org/licenses/zlib-license

	このコードはZlibライセンスです
	https://ja.wikipedia.org/wiki/Zlib_License
	=================================================

	ライセンスに関する補足（以下はライセンス文ではありません）
	このコードはとくに改変をしない場合、商用非商用問わず自由に使うことができます
	改変する場合の注意事項は上記Wikipediaを参考にしてください
	利用した空間内で著作者表示をする義務はありません
	もし表示する場合はshader名「TowelCloud」 作者名「towel_funnel」としてください
*/

#include "SimplexNoise3D.hlsl"
#include "Quaternion.hlsl"
#include "Easing.hlsl"

	uniform sampler2D _noiseMap;
	uniform float _scale;
	uniform float _cloudy;
	uniform float _soft;
	// cloud
	uniform float _farMixRate;
	uniform float _farMixLength;
	uniform float4 _cloudFogColor;
	uniform float _cloudFogLength;
	// horizon
	uniform float _yMirror;
	uniform float _underFade;
	uniform float _underFadeStart;
	uniform float _underFadeWidth;
	uniform float _groundFill;
	uniform float4 _groundFillColor;
	// move
	uniform float _moveRotation;
	uniform float _speed_parameter;
	uniform float _shapeSpeed_parameter;
	uniform float _speedOffset;
	uniform float _speedSlide;
	// rim
	uniform float _rimForce;
	uniform float _rimNarrow;
	// scattering
	uniform float _scattering;
	uniform float4 _scatteringColor;
	uniform float _scatteringForce;
	uniform float _scatteringPassRate;
	uniform float _scatteringRange;
	uniform float _scatteringNarrow;
	// faceWind
	uniform float _faceWindScale_parameter;
	uniform float _faceWindForce_parameter;
	uniform float _faceWindMove;
	uniform float _faceWindMoveSlide;
	// farWind
	uniform int _farWindDivision;
	uniform float _farWindForce_parameter;
	uniform float _farWindMove;
	uniform float _farWindTopEnd;
	uniform float _farWindTopStart;
	uniform float _farWindBottomStart;
	uniform float _farWindBottomEnd;
	// stream
	uniform float _streamScale;
	uniform float _streamForce;
	uniform float _streamMove;
	// etc
	uniform float _fbmScaleUnder;
	uniform float _chine;

// ==== Constants ====
	static const float _speed_base = 0.1;
	static const float _shapeSpeed_base = 0.1;
	static const float _faceWindScale_base = 0.015;
	static const float _faceWindForce_base = 0.15;
	static const float _farWindForce_base = 0.0012;
	// ==== var ====
    static const float km = 1000.0;
	static const int noiseLoop = 5; // ノイズのループ数、高いと品質が上がるが処理が重くなる
	static const float planetR_km = 6000;// 惑星半径（km表示）
	static const float cloudHeight_km = 10;// 雲の生成される地上からの高さ
	static const float adjustRate_km = 15;// 雲の調節処理が行われる基準値（低いほど細かく行われるが、非連続になる）
	static const float adjustOffset = 1; // 雲の調節処理を行わない回数（高いほど近くの雲で行わなくなる）
	static const float adjustMax = 4; // 雲の調節処理の最大数（高いと水平線以下に縞模様が出現、低いと水平線近くが細かくなってしまう）
	static const float scaleBase = 10; // 大きさの解像度ベースの変更

// ==== Math Functions ====
	inline float remap(float value, float minOld, float maxOld, float minNew, float maxNew)
	{
		float rangeOld = (maxOld - minOld);
		if (rangeOld == 0)	// Avoid division by zero
		{
			return minNew;
		}
		return minNew + (value - minOld) * (maxNew - minNew) / rangeOld;
	}

// ==== Fragment Functions ====
	// spherical lerp
	float3 slerpFloat3(float3 start, float3 end, float rate)
	{
		float _dot = dot(start, end);
		clamp(_dot, -1, 1);
		float theta = acos(_dot) * rate;
		float3 relative = normalize(end - start * _dot);
		return (start * cos(theta)) + (relative * sin(theta));
	}
// Function to create a view direction vector from a given world position
float3 createViewDirectionVector(float3 worldPosition)
{
    float3 worldViewDirection = UnityWorldSpaceViewDir(worldPosition);
    return normalize(worldViewDirection);
}

// Function to calculate total smallness
float calculateTotalSmallness(float totalScale, float smallnessRate, int noiseLoop)
{
    if (totalScale == 0) // Avoid division by zero
    {
        return 0;
    }
    return 1 / totalScale * pow(smallnessRate, -noiseLoop);
}

// Function to generate Fractional Brownian Motion (fBm) noise
float4 createFbmNoise(float3 coord, float totalScale, float3 totalOffset, float3 fbmOffset, float3 speed, float fbmAdjust, 
    float swingRate, float smallnessRate)  
{
    float3 offset;
    float swing = 1;
	float currentSwing;
    float smallness = 1; // reScale
    float totalSwing = 0;
    float totalSmallness = calculateTotalSmallness(totalScale, smallnessRate, noiseLoop);
    float4 noise = float4(0, 0, 0, 0);
    float baseOffset = totalScale * scaleBase;
    coord.xz += totalOffset;
    fbmOffset /= noiseLoop;

    float adjustBase = floor(fbmAdjust);
    float adjustSmallRate = frac(fbmAdjust);
    float adjustLargeRate = 1 - adjustSmallRate;
    smallness = pow(smallnessRate, adjustBase);
    swing /= swingRate;
    smallness /= smallnessRate;
    for (int loopIndex = 0; loopIndex < noiseLoop; loopIndex++)
    {
        float adjustIndex = adjustBase + loopIndex;
        swing *= swingRate;
        currentSwing = swing;
        if (loopIndex == 0)
        {
            currentSwing *= adjustLargeRate;
        }
        if (loopIndex == noiseLoop - 1)
        {
            currentSwing *= adjustSmallRate;
        }
        smallness *= smallnessRate;
        offset = -fbmOffset * length(speed.xz) * (adjustIndex - noiseLoop) + speed + baseOffset;
        float4 currentNoise = snoise3d_grad((coord + offset) * smallness * totalSmallness, _chine);
        noise += currentNoise * currentSwing;
        totalSwing += currentSwing;
    }
    noise /= totalSwing;
    return noise;
}

// Function to revert a value or return zero if the value is zero
float revertOrZero(float value)
{
    if (value == 0) // Avoid division by zero
    {
        return 0;
    }
    return 1 / value;
}

// Function to generate single layer noise
float4 createSingleLayerNoise(float3 coord, float totalScale, float3 totalOffset, float3 speed)
{
    float totalSmallness = revertOrZero(totalScale);
    return snoise3d_grad((coord + speed + totalScale * scaleBase) * totalSmallness, 0.5);
}

// Function to generate noise using a 2D texture
float4 createTextureNoise(float2 coord, float totalScale, float2 speed)
{
    float totalSmallness = revertOrZero(totalScale);
    return tex2D(_noiseMap, (coord + speed + totalScale * scaleBase) * totalSmallness);
}


// Function to calculate lateral grid
float3 calculateLateralGrid(float3 viewDir, float farWindDivision, 
    float farWindTopStart, float farWindTopEnd, 
    float farWindBottomStart, float farWindBottomEnd)
{
    float farWindVerticalRate = 1.0 / 6.0;
    float sideAngle = atan2(viewDir.x, viewDir.z) / (PI * 2);
    float farGridX = frac(sideAngle * farWindDivision);
    float farGridY = frac(viewDir.y * farWindDivision * farWindVerticalRate);
    float2 farGrid = float2(farGridX, farGridY);
    float farRateBase = -viewDir.y;
    float farTopStep = step(farWindTopStart, farRateBase);
    float farGridRate = saturate(farTopStep * (farRateBase - farWindTopEnd) / (farWindTopStart - farWindTopEnd) +
        (1 - farTopStep) * (farRateBase - farWindBottomEnd) / (farWindBottomStart - farWindBottomEnd));
    return float3(farGrid, farGridRate);
}

// Function to shift the distant sky within angular space
float3 shiftDistantSkyRate(float2 farGrid, float farGridRate, float farWindMove_param, float farWindForce)
{
	float farWindMove = 0.03 * farWindMove_param;
    float4 farWindNoise = createTextureNoise(farGrid * 2, 1, float2(_Time.y * farWindMove, _Time.y * farWindMove)) * 2 - 1;
    float3 farSlide = normalize(farWindNoise.xyz) * farGridRate * farWindForce;
    return farSlide;
}

// Function to calculate semicircular celestial sphere
float3 calculateSemicircularCelestialSphere(float3 reViewDir, float3 worldPos, float planetR, float cloudHeight, float adjustRate)
{
    float totalR = cloudHeight + planetR;
    float vy = reViewDir.y;
    float viewDistance = sqrt(totalR * totalR - (1 - vy * vy) * (planetR * planetR)) - vy * planetR;
    float3 ovalCoord = reViewDir * viewDistance;
    ovalCoord += worldPos;
    return ovalCoord;
}

// Function to create surface wind
float3 createSurfaceWind(float3 ovalCoord, float3 speed, float faceWindScale, float faceWindForce, float scale)
{
    float2 faceWindSpeed = speed.xz * _faceWindMove;
    float2 faceWindSpeedSlide = speed.xz * _faceWindMoveSlide;
    float4 faceWindNoise = createTextureNoise(ovalCoord.xz, faceWindScale * 2 * scale * km, faceWindSpeedSlide);
    float4 faceWindNoise2 = createTextureNoise(ovalCoord.xz, faceWindScale * scale * km, faceWindSpeed);
    float faceWindOctaveRate = 1.9;
    float3 slide = normalize(faceWindNoise.xyz + faceWindNoise2.xyz * faceWindOctaveRate);
    ovalCoord += faceWindNoise.xyz * faceWindForce * faceWindOctaveRate * km;
    ovalCoord += slide * faceWindForce * km;
    return ovalCoord;
}

// Function to generate real noise and calculate cloud noise power
float calculateCloudNoisePower(float3 ovalCoord, float3 speed, float3 fbmOffset, 
    float adjustBase, float underFade, float underFadeStart,
    float underFadeWidth, float topRate)
{
    float4 noise = createFbmNoise(ovalCoord, _scale * km, 1 * km, fbmOffset, speed, adjustBase, 2, _fbmScaleUnder);
    float cloudNoisePower = clamp(noise.w, -1, 1) * 0.5 + 0.5;
    if (underFade == 1)
    {
        float fadeMax = (1 - underFadeStart) * underFadeWidth + underFadeStart;
        float fadeRate = remap(topRate, underFadeStart, fadeMax, 0, 1);
        cloudNoisePower *= saturate(fadeRate);
    }
    return cloudNoisePower;
}

// Function to calculate cloud power and cloud area rate
float2 calculateCloudPowerAndAreaRate(float cloudNoisePower, float soft, float cloudy)
{
    float soft2 = soft * soft;
    float cloudSoftUnder = 1 - cloudy - soft2 * 1;
    float cloudSoftTop = cloudSoftUnder + soft2 * 2;
    float power = saturate(remap(cloudNoisePower, cloudSoftUnder, cloudSoftTop, 0, 1));
    power = cubicInOut(saturate(power));
    float areaRate = saturate(remap(cloudNoisePower, cloudSoftUnder, 1, 0, 1));
    return float2(power, areaRate);
}

// Function to adjust normal vector
// Assuming the destination of the force space is the center of the cloud, 
// the normalization in the opposite direction can be the cloud surface
// but since the value we get is a cutoff of the atmospheric surface, 
// we need to correct for the fact that the darker parts of the cloud are more frontally oriented.
float3 adjustNormalVector(float3 worldNormal, float3 ovalCoord, float cloudHeight, float areaRate)
{
    float3 earthCenterDir = ovalCoord;
    earthCenterDir.y += cloudHeight * 3;
    earthCenterDir = normalize(earthCenterDir);
    float3 underVector = float3(0, -1, 0);
    float4 viewQuaternion = from_to_rotation(underVector, earthCenterDir);
    float4 viewQuaternionR = q_inverse(viewQuaternion);
    float quadAreaRate = areaRate;
    quadAreaRate = quadOut(saturate(quadAreaRate));
    worldNormal.xz *= -1;
    worldNormal = rotate_vector(worldNormal, viewQuaternion);
    worldNormal.y = areaRate;
    worldNormal = rotate_vector(worldNormal, viewQuaternionR);
    worldNormal.xz *= -1;
    return worldNormal;
}

struct CloudOutputData
{
	float3 worldNormal;
	float areaRate;
	float power;
};

CloudOutputData GetCloudAtmosphere(float3 worldPos, float3 viewDir)
{
    // Tweak parameters
    float speedParam = _speed_base * _speed_parameter;
    float shapeSpeed = _shapeSpeed_base * _shapeSpeed_parameter;
    float faceWindScale = _faceWindScale_base * _faceWindScale_parameter;
    float faceWindForce = _faceWindForce_base * _faceWindForce_parameter;
    float farWindForce = _farWindForce_base * _farWindForce_parameter;

    // Preprocessing
    float planetR = planetR_km * km;
    float cloudHeight = cloudHeight_km * km;
    float adjustRate = adjustRate_km * km;
    float3 viewDirOrigin = viewDir;
    /*
    // Disabled, as the atmosphere shader clips the sky at the horizon.
    if (_yMirror == 1 && 0 < viewDir.y)
    {
        viewDir.y *= -1;
    }
    */

    // Calculate lateral grid
    float3 farGrid = calculateLateralGrid(viewDir, _farWindDivision, _farWindTopStart, _farWindTopEnd, _farWindBottomStart, _farWindBottomEnd);

    // Shift the distant sky within angular space
    viewDir += shiftDistantSkyRate(farGrid.xy, farGrid.z, _farWindMove, farWindForce);

    // Preprocessing 2
    float3 reViewDir = -viewDir;
	float topRate = asin(clamp(reViewDir.y, -1, 1)) * 2 / PI;

    // Calculate semicircular celestial sphere
    float3 ovalCoord = calculateSemicircularCelestialSphere(reViewDir, worldPos, planetR, cloudHeight, adjustRate);
    float ovalCoordLength = length(ovalCoord);
    float adjustBase = pow(ovalCoordLength / adjustRate, 0.55);
    adjustBase = clamp(adjustBase - adjustOffset, 0, adjustMax);

    // Noise generation
    float4 moveQuaternion =  rotate_angle_axis(_moveRotation * PI / 180, float3(0, 1, 0));
    float3 fbmOffset = float3(_speedOffset, 0, _speedSlide);
    float3 speed = _Time.y * float3(speedParam, shapeSpeed, 0) * km;
    speed = rotate_vector(speed, moveQuaternion);
    fbmOffset = rotate_vector(fbmOffset, moveQuaternion);

    // Create surface wind
    ovalCoord = createSurfaceWind(ovalCoord, speed, faceWindScale, faceWindForce, _scale);

    // Create turbulence
    #ifdef _STREAM_ON
        float3 streamSpeed = speed * _streamMove;
        float4 streamNoise = createSingleLayerNoise(ovalCoord, _streamScale * _scale * km, 1 * km, streamSpeed);
        ovalCoord += streamNoise.xyz * _streamForce * km;
    #endif

    // Generate real noise and calculate cloud noise power
    float cloudNoisePower = calculateCloudNoisePower(ovalCoord, speed, fbmOffset, adjustBase, _underFade, _underFadeStart, _underFadeWidth, topRate);

    // Calculate cloud power and cloud area rate
    float2 cloudPowerAndAreaRate = calculateCloudPowerAndAreaRate(cloudNoisePower, _soft, _cloudy);
    float power = cloudPowerAndAreaRate.x;
    float areaRate = cloudPowerAndAreaRate.y;

    // Find the normal direction from the force space
    float3 worldNormal = -createFbmNoise(ovalCoord, _scale * km, 1 * km, fbmOffset, speed, adjustBase, 2, _fbmScaleUnder).xyz;

    // Adjust normal vector
    worldNormal = adjustNormalVector(worldNormal, ovalCoord, cloudHeight, areaRate);

    CloudOutputData output = (CloudOutputData)0;
    output.areaRate = areaRate;
    output.worldNormal = worldNormal;
    output.power = power;
    return output;
} 


#endif // ATMOSPHERE_CLOUDS_INCLUDED
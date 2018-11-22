#version 450

#include "compiled.inc"
#include "std/gbuffer.glsl"
#include "std/math.glsl"
#include "std/brdf.glsl"
#ifdef _Clusters
#include "std/clusters.glsl"
#endif
#ifdef _ShadowMap
#include "std/shadows.glsl"
#endif
#ifdef _Irr
#include "std/shirr.glsl"
#endif
#ifdef _VoxelGI
#include "std/conetrace.glsl"
#endif
#ifdef _VoxelAOvar
#include "std/conetrace.glsl"
#endif
#ifdef _SSS
#include "std/sss.glsl"
#endif
#ifdef _SSRS
#include "std/ssrs.glsl"
#endif
#ifdef _LightIES
#include "std/ies.glsl"
#endif
#ifdef _LTC
#include "std/ltc.glsl"
#endif

// uniform sampler2D gbufferD;
uniform sampler2D gbuffer0;
uniform sampler2D gbuffer1;

#ifdef _VoxelGI
uniform sampler3D voxels;
#endif
#ifdef _VoxelAOvar
uniform sampler3D voxels;
#endif
#ifdef _VoxelGITemporal
uniform sampler3D voxelsLast;
uniform float voxelBlend;
#endif
#ifdef _VoxelGICam
uniform vec3 eyeSnap;
#endif

uniform float envmapStrength;
#ifdef _Irr
//!uniform vec4 shirr[7];
#endif
#ifdef _Brdf
uniform sampler2D senvmapBrdf;
#endif
#ifdef _Rad
uniform sampler2D senvmapRadiance;
uniform int envmapNumMipmaps;
#endif
#ifdef _EnvCol
uniform vec3 backgroundCol;
#endif

#ifdef _SSAO
uniform sampler2D ssaotex;
#endif

#ifdef _SSS
uniform vec2 lightPlane;
#endif

#ifdef _SSRS
//!uniform mat4 VP;
uniform mat4 invVP;
#endif

#ifdef _LightIES
//!uniform sampler2D texIES;
#endif

#ifdef _SMSizeUniform
uniform vec2 smSizeUniform;
#endif

#ifdef _LTC
uniform vec3 lightArea0;
uniform vec3 lightArea1;
uniform vec3 lightArea2;
uniform vec3 lightArea3;
uniform sampler2D sltcMat;
uniform sampler2D sltcMag;
#endif

uniform vec2 cameraProj;
uniform vec3 eye;
uniform vec3 eyeLook;

#ifdef _Clusters
uniform vec4 lightsArray[maxLights * 2];
	#ifdef _Spot
	uniform vec4 lightsArraySpot[maxLights];
	#endif
uniform sampler2D clustersData;
uniform vec2 cameraPlane;
const float clusterNear = 3.0;
const vec3 clusterSlices = vec3(16, 16, 16);
#ifdef _ShadowMap
	#ifdef _ShadowMapCube
	uniform vec2 lightProj;
	uniform samplerCube shadowMap0;
	// uniform samplerCube shadowMap1;
	// uniform samplerCube shadowMap2;
	// uniform samplerCube shadowMap3;
	#else
	uniform sampler2D shadowMap0;
	// uniform sampler2D shadowMap1;
	// uniform sampler2D shadowMap2;
	// uniform sampler2D shadowMap3;
	uniform mat4 LWVP0;
	// uniform mat4 LWVP1;
	// uniform mat4 LWVP2;
	// uniform mat4 LWVP3;
	#endif
	#ifdef _Spot
	uniform sampler2D shadowMapSpot0;
	// uniform sampler2D shadowMapSpot1;
	// uniform sampler2D shadowMapSpot2;
	// uniform sampler2D shadowMapSpot3;
	uniform mat4 LWVPSpot0;
	// uniform mat4 LWVPSpot1;
	// uniform mat4 LWVPSpot2;
	// uniform mat4 LWVPSpot3;
	#endif
#endif
#endif

#ifdef _Sun
uniform vec3 sunDir;
uniform vec3 sunCol;
	#ifdef _ShadowMap
	uniform sampler2D shadowMap;
	uniform float shadowsBias;
	#ifdef _CSM
	//!uniform vec4 casData[shadowmapCascades * 4 + 4];
	#else
	uniform mat4 LWVP;
	#endif
	// #ifdef _SoftShadows
	// uniform sampler2D svisibility;
	// #else
	#endif // _ShadowMap
#endif

#ifdef _LightClouds
uniform sampler2D texClouds;
uniform float time;
#endif

in vec2 texCoord;
in vec3 viewRay;
out vec4 fragColor;

void main() {
	vec4 g0 = texture(gbuffer0, texCoord); // Normal.xy, metallic/roughness, depth
	
	vec3 n;
	n.z = 1.0 - abs(g0.x) - abs(g0.y);
	n.xy = n.z >= 0.0 ? g0.xy : octahedronWrap(g0.xy);
	n = normalize(n);

	vec2 metrough = unpackFloat(g0.b);
	vec4 g1 = texture(gbuffer1, texCoord); // Basecolor.rgb, spec/occ
	vec2 occspec = unpackFloat2(g1.a);
	vec3 albedo = surfaceAlbedo(g1.rgb, metrough.x); // g1.rgb - basecolor
	vec3 f0 = surfaceF0(g1.rgb, metrough.x);

	// #ifdef _InvY // D3D
	// float depth = texture(gbufferD, texCoord).r * 2.0 - 1.0;
	// #else
	float depth = (1.0 - g0.a) * 2.0 - 1.0;
	// #endif
	vec3 p = getPos(eye, eyeLook, viewRay, depth, cameraProj);
	vec3 v = normalize(eye - p);
	float dotNV = max(dot(n, v), 0.0);

#ifdef _Brdf
	vec2 envBRDF = texture(senvmapBrdf, vec2(metrough.y, 1.0 - dotNV)).xy;
#endif

#ifdef _VoxelGI
	#ifdef _VoxelGICam
	vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
	#else
	vec3 voxpos = p / voxelgiHalfExtents;
	#endif

	#ifdef _VoxelGITemporal
	vec4 indirectDiffuse = traceDiffuse(voxpos, n, voxels) * voxelBlend + traceDiffuse(voxpos, n, voxelsLast) * (1.0 - voxelBlend);
	#else
	vec4 indirectDiffuse = traceDiffuse(voxpos, n, voxels);
	#endif

	fragColor.rgb = indirectDiffuse.rgb * voxelgiDiff * g1.rgb;

	if (occspec.y > 0.0) {
		vec3 indirectSpecular = traceSpecular(voxels, voxpos, n, v, metrough.y);
		indirectSpecular *= f0 * envBRDF.x + envBRDF.y;
		fragColor.rgb += indirectSpecular * voxelgiSpec * occspec.y;
	}

	// if (!isInsideCube(voxpos)) fragColor = vec4(1.0); // Show bounds
#endif

	// Envmap
#ifdef _Irr
	vec3 envl = shIrradiance(n);
	#ifdef _EnvTex
	envl /= PI;
	#endif
#else
	vec3 envl = vec3(1.0);
#endif

#ifdef _Rad
	vec3 reflectionWorld = reflect(-v, n);
	float lod = getMipFromRoughness(metrough.y, envmapNumMipmaps);
	vec3 prefilteredColor = textureLod(senvmapRadiance, envMapEquirect(reflectionWorld), lod).rgb;
#endif

#ifdef _EnvLDR
	envl.rgb = pow(envl.rgb, vec3(2.2));
	#ifdef _Rad
		prefilteredColor = pow(prefilteredColor, vec3(2.2));
	#endif
#endif

	envl.rgb *= albedo;
	
#ifdef _Rad // Indirect specular
	envl.rgb += prefilteredColor * (f0 * envBRDF.x + envBRDF.y) * 1.5 * occspec.y;
#else
	#ifdef _EnvCol
	envl.rgb += backgroundCol * surfaceF0(g1.rgb, metrough.x); // f0
	#endif
#endif

	envl.rgb *= envmapStrength * occspec.x;

#ifdef _VoxelAOvar

	#ifdef _VoxelGICam
	vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
	#else
	vec3 voxpos = p / voxelgiHalfExtents;
	#endif
	
	#ifdef _VoxelGITemporal
	envl.rgb *= 1.0 - (traceAO(voxpos, n, voxels) * voxelBlend + traceAO(voxpos, n, voxelsLast) * (1.0 - voxelBlend));
	#else
	envl.rgb *= 1.0 - traceAO(voxpos, n, voxels);
	#endif
	
#endif

#ifdef _VoxelGI
	fragColor.rgb += envl * voxelgiEnv;
#else
	fragColor.rgb = envl;
#endif

#ifdef _SSAO
	#ifdef _RTGI
	fragColor.rgb *= texture(ssaotex, texCoord).rgb;
	#else
	fragColor.rgb *= texture(ssaotex, texCoord).r;
	#endif
#endif

	// Show voxels
	// vec3 origin = vec3(texCoord * 2.0 - 1.0, 0.99);
	// vec3 direction = vec3(0.0, 0.0, -1.0);
	// vec4 color = vec4(0.0f);
	// for(uint step = 0; step < 400 && color.a < 0.99f; ++step) {
	// 	vec3 point = origin + 0.005 * step * direction;
	// 	color += (1.0f - color.a) * textureLod(voxels, point * 0.5 + 0.5, 0);
	// } 
	// fragColor.rgb += color.rgb;

	// Show SSAO
	// fragColor.rgb = texture(ssaotex, texCoord).rrr;

#ifdef _Sun
	vec3 sh = normalize(v + sunDir);
	float sdotNH = dot(n, sh);
	float sdotVH = dot(v, sh);
	float sdotNL = dot(n, sunDir);
	float svisibility = 1.0;
	vec3 sdirect = lambertDiffuseBRDF(albedo, sdotNL) +
				   specularBRDF(f0, metrough.y, sdotNL, sdotNH, dotNV, sdotVH) * occspec.y;

	// #ifdef _SoftShadows
	// svisibility = texture(svisibility, texCoord).r;
	// #endif

	// if (lightShadow == 1) {
		#ifdef _CSM
		svisibility = shadowTestCascade(shadowMap, eye, p + n * shadowsBias * 10, shadowsBias, shadowmapSize * vec2(shadowmapCascades, 1.0));
		#else
		vec4 lPos = LWVP * vec4(p + n * shadowsBias * 100, 1.0);
		if (lPos.w > 0.0) svisibility = shadowTest(shadowMap, lPos.xyz / lPos.w, shadowsBias, shadowmapSize);
		#endif
	// }

	#ifdef _VoxelGIShadow // #else
		#ifdef _VoxelGICam
		vec3 voxpos = (p - eyeSnap) / voxelgiHalfExtents;
		#else
		vec3 voxpos = p / voxelgiHalfExtents;
		#endif
		if (dotNL > 0.0) svisibility = max(0, 1.0 - traceShadow(voxels, voxpos, l, 0.1, 10.0, n));
	#endif

	fragColor.rgb += sdirect * svisibility * sunCol;
#endif

// #ifdef _Hair // Aniso
// 	if (texture(gbuffer2, texCoord).a == 2) {
// 		const float shinyParallel = metrough.y;
// 		const float shinyPerpendicular = 0.1;
// 		const vec3 v = vec3(0.99146, 0.11664, 0.05832);
// 		vec3 T = abs(dot(n, v)) > 0.99999 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, v);
// 		fragColor.rgb = orenNayarDiffuseBRDF(albedo, metrough.y, dotNV, dotNL, dotVH) + wardSpecular(n, h, dotNL, dotNV, dotNH, T, shinyParallel, shinyPerpendicular) * spec;
// 	}
// 	else fragColor.rgb = lambertDiffuseBRDF(albedo, dotNL) + specularBRDF(f0, metrough.y, dotNL, dotNH, dotNV, dotVH) * spec;
// #endif

#ifdef _LightClouds
	visibility *= texture(texClouds, vec2(p.xy / 100.0 + time / 80.0)).r * dot(n, vec3(0,0,1));
#endif

#ifdef _SSS
	if (texture(gbuffer2, texCoord).a == 2) {
		#ifdef _CSM
		int casi, casindex;
		mat4 LWVP = getCascadeMat(distance(eye, p), casi, casindex);
		#endif
		fragColor.rgb += fragColor.rgb * SSSSTransmittance(LWVP, p, n, l, lightPlane.y, shadowMap);
	}
#endif

#ifdef _SSRS
	float tvis = traceShadowSS(-l, p, gbuffer0, invVP, eye);
	// vec2 coords = getProjectedCoord(hitCoord);
	// vec2 deltaCoords = abs(vec2(0.5, 0.5) - coords.xy);
	// float screenEdgeFactor = clamp(1.0 - (deltaCoords.x + deltaCoords.y), 0.0, 1.0);
	// tvis *= screenEdgeFactor;
	visibility *= tvis;
#endif

#ifdef _Clusters

	float depthl = linearize(depth * 0.5 + 0.5, cameraProj);
	int sliceZ = 0;
	if (depthl >= clusterNear) {
		float z = log(depthl - clusterNear + 1.0) / log(cameraPlane.y - clusterNear + 1.0);
		sliceZ = int(z * (clusterSlices.z - 1)) + 1;
	}
	int clusterI = int(texCoord.x * clusterSlices.x) +
				   int(int(texCoord.y * clusterSlices.y) * clusterSlices.x) +
				   int(sliceZ * clusterSlices.x * clusterSlices.y);

	int numLights = int(texelFetch(clustersData, ivec2(clusterI, 0), 0).r * 255);

	#ifdef _Spot
	int numSpots = int(texelFetch(clustersData, ivec2(clusterI, 1 + maxLightsCluster), 0).r * 255);
	int numPoints = numLights - numSpots;
	#endif

	for (int i = 0; i < numLights; i++) {
		int li = int(texelFetch(clustersData, ivec2(clusterI, i + 1), 0).r * 255);

		// pos
		// lightsArray[li * 2    ]
		// color
		// lightsArray[li * 2 + 1]
		// spot - dir
		// lightsArraySpot[li]

		vec3 lp = lightsArray[li * 2].xyz;
		vec3 ld = lp - p;
		vec3 l = normalize(ld);
		vec3 h = normalize(v + l);
		float dotNH = dot(n, h);
		float dotVH = dot(v, h);
		float dotNL = dot(n, l);

		vec3 direct = lambertDiffuseBRDF(albedo, dotNL) +
					  specularBRDF(f0, metrough.y, dotNL, dotNH, dotNV, dotVH) * occspec.y;

		direct *= lightsArray[li * 2 + 1].xyz;

		float visibility = attenuate(distance(p, lp));

		#ifdef _Spot
		if (i > numPoints - 1) {
			float spotEffect = dot(lightsArraySpot[li].xyz, l); // lightDir
			// x - cutoff, y - cutoff - exponent
			if (spotEffect < lightsArray[li * 2 + 1].w) {
				visibility *= smoothstep(lightsArraySpot[li].w, lightsArray[li * 2 + 1].w, spotEffect);
			}
		}
		#endif

		#ifdef _LightIES
		visibility *= iesAttenuation(-l);
		#endif

		// #ifdef _LTC
		// if (lightType == 3) { // Area
		// 	float theta = acos(dotNV);
		// 	vec2 tuv = vec2(metrough.y, theta / (0.5 * PI));
		// 	tuv = tuv * LUT_SCALE + LUT_BIAS;
		// 	vec4 t = texture(sltcMat, tuv);
		// 	mat3 invM = mat3(
		// 		vec3(1.0, 0.0, t.y),
		// 		vec3(0.0, t.z, 0.0),
		// 		vec3(t.w, 0.0, t.x));

		// 	float ltcspec = ltcEvaluate(n, v, dotNV, p, invM, lightArea0, lightArea1, lightArea2, lightArea3);
		// 	ltcspec *= texture(sltcMag, tuv).a;
		// 	float ltcdiff = ltcEvaluate(n, v, dotNV, p, mat3(1.0), lightArea0, lightArea1, lightArea2, lightArea3);
		// 	fragColor.rgb = albedo * ltcdiff + ltcspec * spec;
		// }
		// #endif

		#ifdef _ShadowMap
		// if (lightShadow == 1) {
			float bias = lightsArray[li * 2].w;
			#ifdef _ShadowMapCube
			visibility *= PCFCube(shadowMap0, ld, -l, bias, lightProj, n);
			#else
			vec4 lPos = LWVP0 * vec4(p + n * shadowsBias * 10, 1.0);
			if (lPos.w > 0.0) {
				#ifdef _SMSizeUniform
				visibility *= shadowTest(shadowMap0, lPos.xyz / lPos.w, bias, smSizeUniform);
				#else
				visibility *= shadowTest(shadowMap0, lPos.xyz / lPos.w, bias, shadowmapSize);
				#endif
			}
			#endif
		// }
		#endif // _ShadowMap

		fragColor.rgb += direct * visibility;
	}

#endif
}

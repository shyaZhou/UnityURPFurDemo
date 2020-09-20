struct Attributes
{
    float4 positionOS: POSITION;
    float2 uv        : TEXCOORD0;
    half2 lightmapUV : TEXCOORD1;
    float4 tangent   : TANGENT;
    float3 normal    : NORMAL;
};

struct Varyings
{
    float4 positionHCS                   : SV_POSITION;
    float4 uv                            : TEXCOORD0;
    float3 posWS                         : TEXCOORD1;
    float3 eyeVec                        : TEXCOORD2;
    float4 tangentToWorldAndPackedData[3]: TEXCOORD3;
    half4  ambientOrLightmapUV           : TEXCOORD6;
    float3 normalWS                      : TEXCOORD7;
    float4 shadowCoord                   : TEXCOORD8;
    float4 lightmapUVOrVertexSH          : TEXCOORD9;
    float3 viewWS                        : TEXCOORD10;
    half4 fogFactorAndVertexLight        : TEXCOORD11;
    float4 screenPos                     : TEXCOORD12;
    //TODO
    //     UNITY_SHADOW_COORDS(6)
    //     UNITY_FOG_COORDS(7)
    // #else
    //     UNITY_LIGHTING_COORDS(6,7)
    //     UNITY_FOG_COORDS(8)
};



#include "UtilsInclude.hlsl"
// #define DIRLIGHTMAP_COMBINED


Varyings vert (Attributes IN, half FUR_OFFSET =0)
{
    UNITY_SETUP_INSTANCE_ID(IN);
    Varyings OUT;
    OUT = (Varyings)0;
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
    
    //Transform vertexPos by normal
    //短绒毛
    half3 direction = lerp(IN.normal, _Gravity * _GravityStrength + IN.normal * (1 - _GravityStrength), _FUR_OFFSET);
    //长毛
    // half3 direction = lerp(IN.normal, _Gravity * _GravityStrength + IN.normal, _FUR_OFFSET);
    IN.positionOS.xyz += direction * _FurLength * _FUR_OFFSET;
    OUT.posWS = TransformObjectToWorld(IN.positionOS);
    float3 positionWS = TransformObjectToWorld( IN.positionOS.xyz );
	float4 positionCS = TransformWorldToHClip( positionWS );
    OUT.screenPos = ComputeScreenPos(positionCS);
    
    OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
    OUT.uv.xy = TRANSFORM_TEX(IN.uv, _MainTex);
    OUT.viewWS = normalize( _WorldSpaceCameraPos - OUT.posWS);
    VertexNormalInputs normalInput = GetVertexNormalInputs( IN.normal, IN.tangent );
    half3 vertexLight = VertexLighting( positionWS, normalInput.normalWS );
    half fogFactor = ComputeFogFactor( positionCS.z );
    OUT.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
    OUT.eyeVec = NormalizePerVertexNormal(OUT.posWS.xyz - _WorldSpaceCameraPos);
    half3 normalWS = TransformObjectToWorldNormal(IN.normal);
    OUT.normalWS = normalWS;
    #ifdef _TANGENT_TO_WORLD
        float4 tangentWorld = float4(TransformObjectToWorldDir(IN.tangent.xyz), IN.tangent.w);
        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWS, tangentWorld.xyz, tangentWorld.w);
        OUT.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        OUT.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        OUT.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        OUT.tangentToWorldAndPackedData[0].xyz = 0;
        OUT.tangentToWorldAndPackedData[1].xyz = 0;
        OUT.tangentToWorldAndPackedData[2].xyz = normalWS;
    #endif

    #ifdef _PARALLAXMAP
        TANGENT_SPACE_ROTATION;
        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(IN.positionOS));
        OUT.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        OUT.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        OUT.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

    VertexPositionInputs vertexInput = (VertexPositionInputs)0;
	vertexInput.positionWS = positionWS;
	vertexInput.positionCS = positionCS;
    OUTPUT_LIGHTMAP_UV(IN.lightmapUV, unity_LightmapST, OUT.lightmapUVOrVertexSH.xy);
    OUTPUT_SH(normalWS, OUT.lightmapUVOrVertexSH.xyz);

    OUT.ambientOrLightmapUV = VertexGIForward(IN, OUT.posWS, normalWS);
    //TODO Fog
    //TODO Shadow
    OUT.shadowCoord = GetShadowCoord( vertexInput );
    OUT.shadowCoord = TransformWorldToShadowCoord(positionWS);

    return OUT;
}

half4 frag (Varyings IN, half FUR_OFFSET = 0) : SV_Target
{
    //Data
    float3 Albedo = float3(0.5, 0.5, 0.5);
    float Metallic = 0;
    float3 Specular = 0.5;
    float Smoothness = 0.5;
    float Occlusion = 1;
    float3 Emission = 0;
    float Alpha = 1;
    float3 BakedGI = 0;

    InputData inputData;
	inputData.positionWS = IN.posWS;
	inputData.viewDirectionWS = IN.viewWS;
	inputData.shadowCoord = IN.shadowCoord;
	inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
    inputData.normalWS = IN.normalWS;
    inputData.fogCoord = IN.fogFactorAndVertexLight.x;
	inputData.bakedGI = 0;
	#ifdef _GI_ON
	inputData.bakedGI = SAMPLE_GI( IN.lightmapUVOrVertexSH.xy, IN.lightmapUVOrVertexSH.xyz, IN.normalWS );
	#endif

    half4 color = UniversalFragmentPBR(
    inputData, 
    _Albedo, 
    _Metallic, 
    _Specular, 
    _Smoothness, 
    _Occlusion, 
    _Emission, 
    _Alpha);

    #ifdef _REFRACTION_ASE
		float4 projScreenPos = ScreenPos / ScreenPos.w;
		float3 refractionOffset = ( RefractionIndex - 1.0 ) * mul( UNITY_MATRIX_V, WorldNormal ).xyz * ( 1.0 - dot( WorldNormal, WorldViewDirection ) );
		projScreenPos.xy += refractionOffset.xy;
		float3 refraction = SHADERGRAPH_SAMPLE_SCENE_COLOR( projScreenPos ) * RefractionColor;
		color.rgb = lerp( refraction, color.rgb, color.a );
		color.a = 1;
	#endif

	#ifdef ASE_FOG
		#ifdef TERRAIN_SPLAT_ADDPASS
			color.rgb = MixFogColor(color.rgb, half3( 0, 0, 0 ), IN.fogFactorAndVertexLight.x );
		#else
			color.rgb = MixFog(color.rgb, IN.fogFactorAndVertexLight.x);
		#endif
	#endif

    //
    //Dither
    //UnityApplyDitherCrossFade(IN.positionHCS.xy);
    half facing = dot(-IN.eyeVec, IN.tangentToWorldAndPackedData[2].xyz);
    facing = saturate(ceil(facing)) * 2 - 1;

    FRAGMENT_SETUP(s)
    UNITY_SETUP_INSTANCE_ID(IN);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

    Light mainLight = GetMainLight (IN.shadowCoord);
    half occlusion = CalOcclusion(IN.uv.xy);

    // #ifdef _GI_ON
    // inputData.bakedGI = SAMPLE_GI(IN.lightmapUVOrVertexSH.xy, IN.lightmapUVOrVertexSH.xyz, IN.normalWS);
    // #endif
    //PBR
    BRDFData brdfData;
    half3 albedo = 0.5;
    half3 specular = .5;
    half brdfAlpha = 1;
    InitializeBRDFData(albedo,0,specular,0.5, brdfAlpha, brdfData);
	#ifdef _RECEIVE_SHADOWS
    half lightAttenuation = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
	#else
	half lightAttenuation = 1;
	#endif
    half NdotL = saturate(dot(inputData.normalWS, mainLight.direction));
    half3 radiance = mainLight.color * (lightAttenuation * NdotL);
    // half3 GIcolor = GlobalIllumination(brdfData, inputData.bakedGI, occlusion, inputData.normalWS, inputData.viewDirectionWS);
    // half3 BRDFColor = LightingPhysicallyBased(brdfData, mainLight, inputData.normalWS, inputData.viewDirectionWS);
    //

    half4 c = FABRIC_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, mainLight, inputData, lightAttenuation);

    c.rgb += CalEmission(IN.uv.xy);

    //UNITY_APPLY_FOG(i.fogCoord, c.rgb);
    // half alpha = tex2D(_LayerTex, TRANSFORM_TEX(IN.uv.xy, _LayerTex)).r;
    float2 uvoffset = tex2D(_FlowMap, IN.uv).rg*2-1;
    // return tex2D(_FlowMap, IN.uv);
    half alpha = tex2D(_LayerTex, TRANSFORM_TEX(IN.uv.xy, _LayerTex) + _UVOffset * uvoffset * _FUR_OFFSET).r;
    alpha = step(lerp(0, _CutoffEnd, _FUR_OFFSET), alpha);
    c.a = 1 - _FUR_OFFSET * _FUR_OFFSET;
    c.a += dot(-s.eyeVec, s.normalWorld) - _EdgeFade;
    c.a = max(0, c.a);
    c.a *= alpha;
	c = half4(c.rgb * lerp(lerp(_ShadowColor, 1, _FUR_OFFSET), 1, _ShadowLerp), c.a);
    // float3 mainAtten = mainLight.color * mainLight.distanceAttenuation;
    // mainAtten = lerp( mainAtten, mainAtten * mainLight.shadowAttenuation, shadow );

    // return half4(GIcolor+BRDFColor,1);
    // return half4(mainLight.color * mainLight.distanceAttenuation,1);
    // #ifdef MAIN_LIGHT_CALCULATE_SHADOWS
    // return 1;
    // #else 
    // return 0;
    
    // #endif
    return c;
}
Varyings vert_LayerBase(Attributes IN)
{
    return vert(IN, 0);
}
Varyings vert_Layer(Attributes IN)
{
    return vert(IN, .1);
}
half4 frag_LayerBase(Varyings IN) : SV_Target
{
    return frag(IN, .0);
}
half4 frag_Layer(Varyings IN) : SV_Target
{
    return frag(IN, .1);
}


//-----------------------------------------------------------------------
float SchlickFresnel(float u)
//-----------------------------------------------------------------------
{
	float m = clamp(1.0 - u, 0.0, 1.0);
	float m2 = m * m;
	return m2 * m2 * m; // pow(m,5)
}

//-----------------------------------------------------------------------
float GTR2(float NDotH, float a)
//-----------------------------------------------------------------------
{
	float a2 = a * a;
	float t = 1.0 + (a2 - 1.0) * NDotH * NDotH;
	return a2 / (M_PI * t * t);
}

//-----------------------------------------------------------------------
float SmithG_GGX(float NDotv, float alphaG)
//-----------------------------------------------------------------------
{
	float a = alphaG * alphaG;
	float b = NDotv * NDotv;
	return 1.0 / (NDotv + sqrt(a + b - a * b));
}

//-----------------------------------------------------------------------
float UE4Pdf(float3 wi, float3 wo, float3 N, float matellical, float roughness)
//-----------------------------------------------------------------------
{
	float3 n = N;
	float3 V = wi;
	float3 L = wo;

	float specularAlpha =1-max(0.001, roughness);

	float diffuseRatio = 0.5 * (1.0 - matellical);
	float specularRatio = 1.0 - diffuseRatio;

	float3 halfVec = normalize(L + V);

	float cosTheta = abs(dot(halfVec, n));
	float pdfGTR2 = GTR2(cosTheta, specularAlpha) * cosTheta;

	// calculate diffuse and specular pdfs and mix ratio
	float pdfSpec = pdfGTR2 / (4.0 * abs(dot(L, halfVec)));
	float pdfDiff = abs(dot(L, n)) * (1.0 / M_PI);

	// weight pdfs according to ratios
	return diffuseRatio * pdfDiff + specularRatio * pdfSpec;
}

//-----------------------------------------------------------------------
float3 UE4Eval(float3 wi, float3 wo, float3 N,float3 albedo,float matellical,float roughness)
//-----------------------------------------------------------------------
{

	float3 V = wo;
	float3 L = wi;

	float NDotL = dot(N, L);
	float NDotV = dot(N, V);

	if (NDotL <= 0.0 || NDotV <= 0.0)
		return 0.0;

	float3 H = normalize(L + V);
	float NDotH = dot(N, H);
	float LDotH = dot(L, H);

	// specular	
	float specular =1.0;
	float3 specularCol = lerp(0.08 * specular, albedo, matellical);
	float a = 1.0-max(0.001, roughness);
	float Ds = GTR2(NDotH, a);
	float FH = SchlickFresnel(LDotH);
	float3 Fs = lerp(specularCol, 1.0, FH);
	float roughg = (roughness * 0.5 + 0.5);
	roughg = roughg * roughg;
	float Gs = SmithG_GGX(NDotL, roughg) * SmithG_GGX(NDotV, roughg);

	return (albedo / M_PI) * (1.0 - matellical) + Gs * Fs * Ds;
}

float4 CosineSampleHemisphere(float2 E) {
	float Phi = 2 * M_PI * E.x;
	float CosTheta = sqrt(E.y);
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;

	float PDF = CosTheta / M_PI;
	return float4(H, PDF);
}

float4 ImportanceSampleGGX(float2 E, float Roughness) {
	float m = Roughness * Roughness;
	float m2 = m * m;

	float Phi = 2 * M_PI * E.x;
	float CosTheta = sqrt((1 - E.y) / (1 + (m2 - 1) * E.y));
	float SinTheta = sqrt(1 - CosTheta * CosTheta);

	float3 H;
	H.x = SinTheta * cos(Phi);
	H.y = SinTheta * sin(Phi);
	H.z = CosTheta;

	float d = (CosTheta * m2 - CosTheta) * CosTheta + 1;
	float D = m2 / (M_PI * d * d);

	float PDF = D * CosTheta;
	return float4(H, PDF);
}

float4 brdfSampling(inout uint4 states, float3 N, float3 V, float matellical, float Smoothness)
{
	float probability = GetRandomValue(states);
	float diffuseRatio = 0.5 * (1 - matellical);


	float3 UpVector = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
	float3 TangentX = normalize(cross(UpVector, N));
	float3 TangentY = cross(N, TangentX);

	float r1 = GetRandomValue(states);
	float r2 = GetRandomValue(states);

	ONB uvw;
	ONBBuildFromW(uvw, N);
	float4  Hpdf = 0;
	if (probability < diffuseRatio)
	{
		Hpdf = CosineSampleHemisphere(float2(r1, r2));
	}
	else
	{
		float a = 1.0 - Smoothness;
		a = max(0.00001, a);
		Hpdf= ImportanceSampleGGX(float2(r1,r2),a);
		
	}
	Hpdf.xyz = ONBLocal(uvw, Hpdf.xyz);
	return Hpdf;
}



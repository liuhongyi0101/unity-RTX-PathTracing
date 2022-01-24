#define M_PI (3.14159265358979323846264338327950288)
#define M_1_PI_F 0.318309886183790
RWStructuredBuffer<uint4> _PRNGStates;

inline float cbrt(float d)
{
  return pow(d, 1.0f / 3.0f);
}

uint TausStep(inout uint z, int S1, int S2, int S3, uint M)
{
  uint b = (((z << S1) ^ z) >> S2);
  return z = (((z & M) << S3) ^ b);
}

uint LCGStep(inout uint z)
{
  return z = (1664525 * z + 1013904223);
}

float GetRandomValueTauswortheUniform(inout uint4 states)
{
  uint taus = TausStep(states.x, 13, 19, 12, 4294967294UL) ^ TausStep(states.y, 2, 25, 4, 4294967288UL) ^ TausStep(states.z, 3, 11, 17, 4294967280UL);
  uint lcg = LCGStep(states.w);

  return 2.3283064365387e-10f * (taus ^ lcg); // taus+
}

float GetRandomValue(inout uint4 states)
{
  float rand = GetRandomValueTauswortheUniform(states);
  return rand;
}

float3 GetRandomInUnitSphere(inout uint4 states)
{
  float u = GetRandomValue(states);
  float v = GetRandomValue(states);
  float theta = u * 2.f * (float)M_PI;
  float phi = acos(2.f * v - 1.f);
  float r = cbrt(GetRandomValue(states));
  float sinTheta = sin(theta);
  float cosTheta = cos(theta);
  float sinPhi = sin(phi);
  float cosPhi = cos(phi);
  float x = r * sinPhi * cosTheta;
  float y = r * sinPhi * sinTheta;
  float z = r * cosPhi;
  return float3(x, y, z);
}
//// Based on http://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_slides.pdf
//float3 importanceSample_GGX(inout uint4 states, float roughness, float3 normal)
//{
//	// Maps a 2D point to a hemisphere with spread based on roughness
//	float2 Xi = float2(GetRandomValue(states), GetRandomValue(states));
//	float alpha = roughness * roughness;
//	float phi = 2.0 * M_PI * Xi.x + random(normal.xz) * 0.1;
//	float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (alpha * alpha - 1.0) * Xi.y));
//	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
//	float3 H = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
//
//	// Tangent space
//	float3 up = abs(normal.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
//	float3 tangentX = normalize(cross(up, normal));
//	float3 tangentY = normalize(cross(normal, tangentX));
//
//	// Convert to world Space
//	return normalize(tangentX * H.x + tangentY * H.y + normal * H.z);
//}
float3 GetRandomOnUnitSphere(inout uint4 states)
{
  float r1 = GetRandomValue(states);
  float r2 = GetRandomValue(states);
  float x = cos(2.0f * (float)M_PI * r1) * 2.0f * sqrt(r2 * (1.0f - r2));
  float y = sin(2.0f * (float)M_PI * r1) * 2.0f * sqrt(r2 * (1.0f - r2));
  float z = 1.0f - 2.0f * r2;
  return float3(x, y, z);
}

float2 GetRandomInUnitDisk(inout uint4 states) {
  float a = GetRandomValue(states) * 2.0f * (float)M_PI;
  float r = sqrt(GetRandomValue(states));

  return float2(r * cos(a), r * sin(a));
}

float3 GetRandomCosineDirection(inout uint4 states) {
  float r1 = GetRandomValue(states);
  float r2 = GetRandomValue(states);
  float z = sqrt(1.0f - r2);
  float phi = 2.0f * M_PI * r1;
  float x = cos(phi) * sqrt(r2);
  float y = sin(phi) * sqrt(r2);


  return float3(x, y, z);
}

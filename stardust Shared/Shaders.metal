//
//  Shaders.metal
//  stardust Shared
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

// Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

#import "ShaderTypes.h"

using namespace metal;

// MARK: - Matrix utilities

float4x4 translation(float3 t)
{
    return (float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { t.x, t.y, t.z,  1 }
    }};
}

// MARK: - Compute shader

// Simulate gravitational forces between instances by computing the velocity
kernel
void simulate_physics(
                      device InstanceUniforms *instanceUniforms [[ buffer(BufferIndexInstanceUniforms) ]],
                      constant SharedUniforms &sharedUniforms [[ buffer(BufferIndexSharedUniforms) ]],
                      uint i [[ thread_position_in_grid ]]
                      )
{
    device InstanceUniforms* current = instanceUniforms + i;
    vector_float3 acceleration = { 0.f, 0.f, 0.f };
    for (unsigned int j = 0; j < INSTANCE_COUNT; j++)
    {
        if (i == j) continue;

        device InstanceUniforms* other = instanceUniforms + j;
        const float r2 = distance_squared(current->position, other->position);
        if (r2 > 1.0f) {
            const float acceleration_magnitude = 9.8f /* G * mass */ / r2;
            const float3 acceleration_unit = normalize(other->position - current->position);
            acceleration += acceleration_magnitude * acceleration_unit;
        }
    }
    current->velocity += acceleration * sharedUniforms.deltaTime;
}

// MARK: - Render Shader

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;

vertex
ColorInOut vertexShader(
                        Vertex in [[stage_in]],
                        constant InstanceUniforms *instanceUniforms [[ buffer(BufferIndexInstanceUniforms) ]],
                        constant SharedUniforms &sharedUniforms [[ buffer(BufferIndexSharedUniforms) ]],
                        ushort instanceId [[instance_id]]
                        )
{
    ColorInOut out;
    float4 position = float4(in.position, 1.0);
    InstanceUniforms instance = instanceUniforms[instanceId];
    float4x4 translationMatrix = translation(instance.position);
    float4x4 modelMatrix = translationMatrix;
    out.position = sharedUniforms.viewProjectionMatrix * modelMatrix  * position;
    out.texCoord = in.texCoord;
    return out;
}

fragment
float4 fragmentShader(
                      ColorInOut in [[stage_in]],
                      texture2d<half> colorMap [[ texture(TextureIndexColor) ]]
                      )
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    half4 colorSample = colorMap.sample(colorSampler, in.texCoord.xy);
    return float4(colorSample);
}

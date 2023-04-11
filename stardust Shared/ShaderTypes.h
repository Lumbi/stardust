//
//  ShaderTypes.h
//  stardust Shared
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

#define INSTANCE_COUNT 10000

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexSharedUniforms = 2,
    BufferIndexInstanceUniforms = 3
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition = 0,
    VertexAttributeTexcoord = 1,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexColor = 0,
};

typedef struct
{;
    vector_float3 position;
    vector_float3 velocity;
} InstanceUniforms;


typedef struct
{
    matrix_float4x4 viewProjectionMatrix;
    float deltaTime;
} SharedUniforms;

#endif /* ShaderTypes_h */


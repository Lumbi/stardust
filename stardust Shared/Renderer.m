//
//  Renderer.m
//  stardust Shared
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "Renderer.h"
#import "ShaderTypes.h"

#include <time.h>

struct Physics {
    vector_float3 _position;
    vector_float3 _velocity;
};

@implementation Renderer
{
    dispatch_semaphore_t _inFlightSemaphore;
    id <MTLDevice> _device;
    id <MTLCommandQueue> _commandQueue;

    id <MTLBuffer> _instanceUniformBuffer;
    id <MTLBuffer> _sharedUniformBuffer;
    id <MTLComputePipelineState> _physicsPipelineState;
    id <MTLRenderPipelineState> _pipelineState;
    id <MTLDepthStencilState> _depthState;
    id <MTLTexture> _colorMap;
    MTLVertexDescriptor *_mtlVertexDescriptor;

    MTKMesh *_mesh;

    matrix_float4x4 _viewProjectionMatrix;

    float _aspect;

    float _camera_pitch;
    float _camera_yaw;
    vector_float3 _camera_position;

    float _frameDuration;
}

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *) view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        _inFlightSemaphore = dispatch_semaphore_create(1);
        [self _loadMetalWithView:view];
        [self _loadAssets];
        [self _initPhysics];
        [self _initCamera];
    }

    return self;
}

- (void)_loadMetalWithView:(nonnull MTKView *) view;
{
    // Load Metal state objects and initialize renderer dependent view properties

    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    view.sampleCount = 1;

    _mtlVertexDescriptor = [[MTLVertexDescriptor alloc] init];

    _mtlVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormatFloat3;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexMeshPositions;

    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].format = MTLVertexFormatFloat2;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].offset = 0;
    _mtlVertexDescriptor.attributes[VertexAttributeTexcoord].bufferIndex = BufferIndexMeshGenerics;

    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stride = 12;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshPositions].stepFunction = MTLVertexStepFunctionPerVertex;

    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stride = 8;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepRate = 1;
    _mtlVertexDescriptor.layouts[BufferIndexMeshGenerics].stepFunction = MTLVertexStepFunctionPerVertex;

    id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
    NSError *error = NULL;

    id<MTLFunction> physicsFunction = [defaultLibrary newFunctionWithName:@"simulate_physics"];
    _physicsPipelineState = [_device newComputePipelineStateWithFunction:physicsFunction
                                                                   error:&error];
    if (!_physicsPipelineState) {
        NSLog(@"Failed to create physics pipeline state, error %@", error);
    }

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = _mtlVertexDescriptor;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor: pipelineStateDescriptor error: &error];
    if (!_pipelineState) {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = true;

    _depthState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    // Uniforms

    _sharedUniformBuffer = [_device newBufferWithLength:sizeof(SharedUniforms)
                                                options:MTLResourceStorageModeShared];

    _instanceUniformBuffer = [_device newBufferWithLength:sizeof(InstanceUniforms) * INSTANCE_COUNT
                                                  options:MTLResourceStorageModeShared];
    _instanceUniformBuffer.label = @"Instance Uniform Buffer";

    _commandQueue = [_device newCommandQueue];
}

- (void)_loadAssets
{
    /// Load assets into metal objects

    NSError *error;

    MTKMeshBufferAllocator *metalAllocator = [[MTKMeshBufferAllocator alloc]
                                              initWithDevice: _device];

    MDLMesh *mdlMesh = [MDLMesh newBoxWithDimensions: vector3(1.0f, 1.0f, 1.0f)
                                            segments: vector3(1u, 1u, 1u)
                                        geometryType: MDLGeometryTypeTriangles
                                       inwardNormals: NO
                                           allocator: metalAllocator];

    MDLVertexDescriptor *mdlVertexDescriptor =
    MTKModelIOVertexDescriptorFromMetal(_mtlVertexDescriptor);

    mdlVertexDescriptor.attributes[VertexAttributePosition].name = MDLVertexAttributePosition;
    mdlVertexDescriptor.attributes[VertexAttributeTexcoord].name = MDLVertexAttributeTextureCoordinate;

    mdlMesh.vertexDescriptor = mdlVertexDescriptor;

    _mesh = [[MTKMesh alloc] initWithMesh: mdlMesh
                                   device: _device
                                    error: &error];

    if(!_mesh || error)
    {
        NSLog(@"Error creating MetalKit mesh %@", error.localizedDescription);
    }

    MTKTextureLoader* textureLoader = [[MTKTextureLoader alloc] initWithDevice: _device];

    NSDictionary *textureLoaderOptions =
    @{
        MTKTextureLoaderOptionTextureUsage : @(MTLTextureUsageShaderRead),
        MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
    };

    _colorMap = [textureLoader newTextureWithName: @"ColorMap"
                                      scaleFactor: 1.0
                                           bundle: nil
                                          options: textureLoaderOptions
                                            error: &error];

    if(!_colorMap || error)
    {
        NSLog(@"Error creating texture %@", error.localizedDescription);
    }
}

- (void)_initPhysics
{
    for (unsigned int i = 0; i < INSTANCE_COUNT; i++)
    {
        InstanceUniforms *instance = [self _instanceUniform:i];
        float x = rand() % 100 - 50.f;
        float y = rand() % 100 - 50.f;
        float z = rand() % 100 - 50.f;
        instance->position = vector3(x * sinf(i), y * cosf(i), z * sinf(i));
        instance->velocity = vector3(0.f, 0.f, 0.f);
    }
}

-(InstanceUniforms *)_instanceUniform:(unsigned int)i
{
    return (InstanceUniforms *)(_instanceUniformBuffer.contents + sizeof(InstanceUniforms) * i);
}

-(void)_initCamera
{
    _camera_yaw = 0.f;
    _camera_pitch = -M_PI;
    _camera_position = (vector_float3) { 0.f, 0.f, -100.f };
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    /// Per frame updates here

    dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

    [self _updateCamera];

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"Physics Command Encoder";

    // Physics

    id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];

    SharedUniforms *sharedUniforms = (SharedUniforms *)_sharedUniformBuffer.contents;
    sharedUniforms->deltaTime = 1.f / 60.f; // TODO: set properly

    [computeEncoder setComputePipelineState:_physicsPipelineState];
    [computeEncoder setBuffer:_instanceUniformBuffer offset:0 atIndex: BufferIndexInstanceUniforms];
    [computeEncoder setBuffer:_sharedUniformBuffer offset:0 atIndex: BufferIndexSharedUniforms];

    NSUInteger threadGroupSize = _physicsPipelineState.maxTotalThreadsPerThreadgroup;
    if (threadGroupSize > INSTANCE_COUNT) threadGroupSize = INSTANCE_COUNT;
    [computeEncoder dispatchThreads: MTLSizeMake(INSTANCE_COUNT, 1, 1)
              threadsPerThreadgroup: MTLSizeMake(threadGroupSize, 1, 1)];

    [computeEncoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    // Apply velociy
    for (unsigned int i = 0; i < INSTANCE_COUNT; i++)
    {
        InstanceUniforms * uniforms = [self _instanceUniform:i];
        uniforms->position += uniforms->velocity * sharedUniforms->deltaTime;
    }

    // Render

    sharedUniforms->viewProjectionMatrix = _viewProjectionMatrix;

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;

    if (!renderPassDescriptor) return;

    commandBuffer = [_commandQueue commandBuffer];

    id <MTLRenderCommandEncoder> renderEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor: renderPassDescriptor];
    renderEncoder.label = @"Render Command Encoder";

    [renderEncoder setFrontFacingWinding: MTLWindingCounterClockwise];
    [renderEncoder setCullMode: MTLCullModeBack];
    [renderEncoder setRenderPipelineState: _pipelineState];
    [renderEncoder setDepthStencilState: _depthState];

    [renderEncoder pushDebugGroup: @"Draw Instance"];

    [renderEncoder setVertexBuffer:_sharedUniformBuffer
                            offset:0
                           atIndex:BufferIndexSharedUniforms];

    [renderEncoder setVertexBuffer:_instanceUniformBuffer
                            offset:0
                           atIndex:BufferIndexInstanceUniforms];

    for (NSUInteger bufferIndex = 0; bufferIndex < _mesh.vertexBuffers.count; bufferIndex++)
    {
        MTKMeshBuffer *vertexBuffer = _mesh.vertexBuffers[bufferIndex];
        if((NSNull*)vertexBuffer != [NSNull null])
        {
            [renderEncoder setVertexBuffer:vertexBuffer.buffer
                                    offset:vertexBuffer.offset
                                   atIndex:bufferIndex];
        }
    }

    [renderEncoder setFragmentTexture: _colorMap
                              atIndex: TextureIndexColor];

    for(MTKSubmesh *submesh in _mesh.submeshes)
    {
        [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                  indexCount:submesh.indexCount
                                   indexType:submesh.indexType
                                 indexBuffer:submesh.indexBuffer.buffer
                           indexBufferOffset:submesh.indexBuffer.offset
                               instanceCount:INSTANCE_COUNT];
    }

    [renderEncoder popDebugGroup];

    [renderEncoder endEncoding];

    __block dispatch_semaphore_t block_sema = _inFlightSemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_semaphore_signal(block_sema);
    }];

    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    _aspect = size.width / (float)size.height;
    [self _updateCamera];
}

-(void)truckCamera:(float)delta
{
    _camera_position -= transform([self _cameraRotation], (vector_float3) { delta, 0.f, 0.f });
}

-(void)dollyCamera:(float)delta
{
    _camera_position -= transform([self _cameraRotation], (vector_float3) { 0.f, 0.f, delta });
}

-(void)yawCamera:(float)delta
{
    _camera_yaw += delta;
}

-(void)pitchCamera:(float)delta
{
    _camera_pitch += delta;
}

-(matrix_float4x4)_cameraRotation
{
    matrix_float4x4 pitch_rotation_matrix = matrix4x4_rotation(_camera_pitch, (vector_float3) { 1.f, 0.f, 0.f });
    matrix_float4x4 yaw_rotation_matrix = matrix4x4_rotation(_camera_yaw, (vector_float3) { 0.f, 1.f, 0.f });
    return matrix_multiply(pitch_rotation_matrix, yaw_rotation_matrix);
}

- (void)_updateCamera
{
    matrix_float4x4 rotation_matrix = [self _cameraRotation];
    matrix_float4x4 translation_matrix = matrix4x4_translation(-_camera_position.x, -_camera_position.y, -_camera_position.z);
    matrix_float4x4 view_matrix = matrix_multiply(rotation_matrix, translation_matrix);

    matrix_float4x4 projection_matrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), _aspect, 0.1f, 1000.0f);

    _viewProjectionMatrix = matrix_multiply(projection_matrix, view_matrix);
}

// MARK: - Matrix utilities

vector_float3 transform(matrix_float4x4 matrix, vector_float3 vector) {
    vector_float3 col1 = *(vector_float3 *)&matrix.columns[0];
    vector_float3 col2 = *(vector_float3 *)&matrix.columns[1];
    vector_float3 col3 = *(vector_float3 *)&matrix.columns[2];

    float x = simd_dot(col1, vector);
    float y = simd_dot(col2, vector);
    float z = simd_dot(col3, vector);

    return (vector_float3) { x, y, z };
}

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

@end

//
//  Renderer.h
//  stardust Shared
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

#import <MetalKit/MetalKit.h>

@interface Renderer : NSObject <MTKViewDelegate>

-(nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;

// MARK: - Camera control

-(void)truckCamera:(float)delta;
-(void)dollyCamera:(float)delta;
-(void)yawCamera:(float)delta;
-(void)pitchCamera:(float)delta;

@end

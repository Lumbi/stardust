//
//  GameViewController.h
//  stardust macOS
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "Renderer.h"

@interface GameViewController : NSViewController

@property (nonatomic, weak) IBOutlet NSTextField *fpsLabel;

@end

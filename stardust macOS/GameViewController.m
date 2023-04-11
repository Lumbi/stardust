//
//  GameViewController.m
//  stardust macOS
//
//  Created by Gabriel Lumbi on 2023-03-31.
//

#import "GameViewController.h"
#import "Renderer.h"

typedef NS_ENUM(NSInteger, KeyCode) {
    KEY_CODE_A = 0,
    KEY_CODE_S = 1,
    KEY_CODE_D = 2,
    KEY_CODE_W = 13,
    KEY_CODE_ESCAPE = 53
};

typedef NS_ENUM(NSUInteger, PressedKeys) {
    PRESSED_KEY_NONE = 0,
    PRESSED_KEY_A = 1 << 0,
    PRESSED_KEY_S = 1 << 1,
    PRESSED_KEY_D = 1 << 2,
    PRESSED_KEY_W = 1 << 3
};

@implementation GameViewController
{
    MTKView *_view;
    Renderer *_renderer;
    PressedKeys _pressedKeys;
    id _eventMonitor;
    NSTimer *_inputTimer;
    NSPoint _previousMouseLocation;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (MTKView *)self.view;

    _pressedKeys = PRESSED_KEY_NONE;

    _view.device = MTLCreateSystemDefaultDevice();
    if(!_view.device)
    {
        NSLog(@"Metal is not supported on this device");
        self.view = [[NSView alloc] initWithFrame:self.view.frame];
        return;
    }
    _renderer = [[Renderer alloc] initWithMetalKitView:_view];
    [_renderer mtkView:_view drawableSizeWillChange:_view.bounds.size];
    _view.delegate = _renderer;
}

- (void)viewDidAppear
{
    [super viewDidAppear];

    [NSCursor hide];

    _previousMouseLocation = [NSEvent mouseLocation];

    __weak GameViewController *weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskKeyUp
                                          handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if (event.type == NSEventTypeKeyDown) {
            [weakSelf _handleKeyDown:event];
        } else if (event.type == NSEventTypeKeyUp) {
            [weakSelf _handleKeyUp:event];
        }
        return event;
    }];

    [_inputTimer invalidate];
    _inputTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                                  repeats:true
                                                    block:^(NSTimer * _Nonnull timer) {
        [weakSelf _processInputs];
    }];
}

-(void)viewDidDisappear
{
    [super viewDidDisappear];

    [NSEvent removeMonitor:_eventMonitor];
    [NSCursor unhide];

    [_inputTimer invalidate];
}

-(void)_processInputs
{
    NSPoint mouseLocation = [NSEvent mouseLocation];
    [_renderer yawCamera: (mouseLocation.x - _previousMouseLocation.x) * (-0.01f)];
    [_renderer pitchCamera: (mouseLocation.y - _previousMouseLocation.y) * (-0.01f)];

    if (
        mouseLocation.x <= 1.f ||
        mouseLocation.x >= self.view.window.screen.frame.size.width - 1.f ||
        mouseLocation.y <= 1.f ||
        mouseLocation.y >= self.view.window.screen.frame.size.height - 1.f
        )
    {
        NSPoint resetPosition = NSMakePoint(NSMidX(self.view.window.frame), NSMidY(self.view.window.frame));
        CGWarpMouseCursorPosition(resetPosition);
        CGAssociateMouseAndMouseCursorPosition(true);
    }
    _previousMouseLocation = [NSEvent mouseLocation];

    if (_pressedKeys & PRESSED_KEY_A) {
        [_renderer truckCamera: 1.f];
    }
    if (_pressedKeys & PRESSED_KEY_D) {
        [_renderer truckCamera: -1.f];
    }
    if (_pressedKeys & PRESSED_KEY_W) {
        [_renderer dollyCamera: 1.f];
    }
    if (_pressedKeys & PRESSED_KEY_S) {
        [_renderer dollyCamera: -1.f];
    }

    self.fpsLabel.cell.title = [NSString stringWithFormat:@"FPS: %.2f", [_renderer fps]];
}

- (void)_handleKeyDown:(NSEvent *)event
{
    switch (event.keyCode) {
        case KEY_CODE_A:
            _pressedKeys |= PRESSED_KEY_A;
            break;

        case KEY_CODE_D:
            _pressedKeys |= PRESSED_KEY_D;
            break;

        case KEY_CODE_W:
            _pressedKeys |= PRESSED_KEY_W;
            break;

        case KEY_CODE_S:
            _pressedKeys |= PRESSED_KEY_S;
            break;

        case KEY_CODE_ESCAPE:
            [[[[self view] window] windowController] close];
            break;

        default:
            break;
    }
}

-(void)_handleKeyUp:(NSEvent *)event
{
    switch (event.keyCode) {
        case KEY_CODE_A:
            _pressedKeys &= ~PRESSED_KEY_A;
            break;

        case KEY_CODE_D:
            _pressedKeys &= ~PRESSED_KEY_D;
            break;

        case KEY_CODE_W:
            _pressedKeys &= ~PRESSED_KEY_W;
            break;

        case KEY_CODE_S:
            _pressedKeys &= ~PRESSED_KEY_S;
            break;

        default:
            break;
    }
}

@end

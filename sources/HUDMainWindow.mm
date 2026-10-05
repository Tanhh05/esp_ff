#import "HUDMainWindow.h"
#import <objc/runtime.h>
#import "../esp/drawing_view/esp.h"
#import "../esp/drawing_view/FloatingMenuView.h"

@implementation HUDMainWindow

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil; // Pass all touches 100% through to game / SpringBoard underneath
}

- (BOOL)_ignoresHitTest {
    return YES; // Must be YES to prevent freezing touches in Free Fire!
}

- (BOOL)_canBecomeKeyWindow {
    return NO;
}

- (BOOL)_canAffectStatusBarAppearance {
    return NO;
}

@end




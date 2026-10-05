#import <UIKit/UIKit.h>

@interface FloatingMenuView : UIView

@property (nonatomic, assign, readonly) BOOL isOpen;
@property (nonatomic, strong, readonly) UIView *menuCard;
@property (nonatomic, strong, readonly) UIButton *bubbleButton;

+ (instancetype)sharedMenu;
- (void)openMenuAnimated:(BOOL)animated;
- (void)closeMenuAnimated:(BOOL)animated;
- (BOOL)handleDirectTouchAtPoint:(CGPoint)pt phase:(UITouchPhase)phase;

@end


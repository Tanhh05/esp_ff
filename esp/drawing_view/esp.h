#import <UIKit/UIKit.h>

@interface ESP_View : UIView
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, assign) BOOL boxEnabled;
@property (nonatomic, assign) BOOL lineEnabled;
@property (nonatomic, assign) BOOL healthEnabled;
@property (nonatomic, assign) BOOL nameEnabled;

@property (nonatomic, assign) BOOL aimbotEnabled;
@property (nonatomic, assign) NSInteger aimBone; // 0: Head, 1: Chest
@property (nonatomic, assign) CGFloat aimFov;     // FOV radius in pixels
@property (nonatomic, assign) CGFloat aimSmooth;  // Smooth factor (0.1 - 1.0)
@property (nonatomic, assign) BOOL isFiring;

+ (instancetype)sharedView;
- (void)startLoop;
- (void)hideViewFromCapture:(BOOL)hide;
@end

typedef ESP_View ESPDrawingView;


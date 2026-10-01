#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface PiPOverlayManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) BOOL isPiPActive;
@property (nonatomic, assign) BOOL boxEnabled;
@property (nonatomic, assign) BOOL lineEnabled;
@property (nonatomic, assign) BOOL healthEnabled;
@property (nonatomic, assign) BOOL nameEnabled;

- (void)setupWithParentView:(UIView *)parentView;
- (void)startPiP;
- (void)stopPiP;

@end

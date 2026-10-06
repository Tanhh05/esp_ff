#import <UIKit/UIKit.h>

@interface ESP_View : UIView
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, assign) BOOL boxEnabled;
@property (nonatomic, assign) BOOL lineEnabled;
@property (nonatomic, assign) BOOL healthEnabled;
@property (nonatomic, assign) BOOL nameEnabled;
@property (nonatomic, assign) BOOL countEnabled;

+ (instancetype)sharedView;
- (void)startLoop;
- (void)hideViewFromCapture:(BOOL)hide;
@end

typedef ESP_View ESPDrawingView;



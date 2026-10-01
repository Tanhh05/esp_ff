#import "esp.h"
#import "../Core/GameLogic.h"
#import "../../sources/UIView+SecureView.h"
#import <QuartzCore/QuartzCore.h>
#import <atomic>

@interface ESP_View () {
    std::atomic<bool> _isUpdating;
}
@property (nonatomic, strong) CADisplayLink *displayLink;
@end

@implementation ESP_View

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil; // Pass all touch events through
}

+ (instancetype)sharedView {
    static ESP_View *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        instance = [[ESP_View alloc] initWithFrame:screenBounds];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.espEnabled = YES;
        self.boxEnabled = YES;
        self.lineEnabled = YES;
        self.healthEnabled = YES;
        self.nameEnabled = YES;
        _isUpdating = false;

        [self startLoop];
    }
    return self;
}

- (void)hideViewFromCapture:(BOOL)hide {
    // Uses UIView+SecureView category to prevent screen recorder from seeing ESP
    [super hideViewFromCapture:hide];
}

- (void)startLoop {
    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (void)onFrame {
    if (!self.espEnabled) return;
    
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat width = MAX(screenSize.width, screenSize.height);
    CGFloat height = MIN(screenSize.width, screenSize.height);
    
    if (!_isUpdating.exchange(true)) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            GameLogic::getInstance().updateData(width, height);
            self->_isUpdating = false;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setNeedsDisplay];
            });
        });
    }
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!self.espEnabled) return;

    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) return;

    const auto& players = GameLogic::getInstance().getPlayers();
    CGPoint topCenter = CGPointMake(rect.size.width / 2.0f, 0.0f);

    for (const auto& p : players) {
        if (!p.isVisibleOnScreen) continue;

        // Screen Y: top of screen is 0, bottom is screenHeight.
        // Head is higher up in 3D world than toe, so headScreen.y < toeScreen.y in UIKit coordinates.
        float topY = MIN(p.headScreenPos.y, p.toeScreenPos.y);
        float bottomY = MAX(p.headScreenPos.y, p.toeScreenPos.y);

        float height = bottomY - topY;
        if (height < 10.0f) height = 10.0f;
        if (height > rect.size.height * 1.5f) continue;

        // Add padding around head and feet for perfect box wrapping
        float boxPadding = height * 0.15f;
        float boxY = topY - boxPadding;
        float boxHeight = height + (boxPadding * 1.8f);
        float boxWidth = boxHeight * 0.55f;

        float boxX = p.headScreenPos.x - (boxWidth / 2.0f);

        // Skip any points outside visible screen range
        if (p.headScreenPos.x < -100.0f || p.headScreenPos.x > rect.size.width + 100.0f ||
            topY < -100.0f || topY > rect.size.height + 100.0f) {
            continue;
        }

        // 1. Line ESP (Red Line from Top-Center to Head)
        if (self.lineEnabled) {
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.85].CGColor);
            CGContextSetLineWidth(context, 1.5f);
            CGContextMoveToPoint(context, topCenter.x, topCenter.y);
            CGContextAddLineToPoint(context, p.headScreenPos.x, topY);
            CGContextStrokePath(context);
        }

        // 2. Box ESP (Green Box around body)
        if (self.boxEnabled) {
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:0.95].CGColor);
            CGContextSetLineWidth(context, 2.0f);
            CGContextAddRect(context, CGRectMake(boxX, boxY, boxWidth, boxHeight));
            CGContextStrokePath(context);
        }

        // 3. Health Bar
        if (self.healthEnabled) {
            float healthRatio = (float)p.currentHP / (float)p.maxHP;
            if (healthRatio > 1.0f) healthRatio = 1.0f;
            if (healthRatio < 0.0f) healthRatio = 0.0f;

            float barWidth = 3.5f;
            float barX = boxX - 7.0f;
            float barHeight = boxHeight * healthRatio;
            float barY = boxY + (boxHeight - barHeight);

            // Background Bar
            CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.1 alpha:0.6].CGColor);
            CGContextFillRect(context, CGRectMake(barX, boxY, barWidth, boxHeight));

            // Green/Red Health Bar
            UIColor *healthColor = [UIColor colorWithRed:(1.0f - healthRatio) green:healthRatio blue:0.0f alpha:0.95f];
            CGContextSetFillColorWithColor(context, healthColor.CGColor);
            CGContextFillRect(context, CGRectMake(barX, barY, barWidth, barHeight));
        }

        // 4. Nickname & Distance
        if (self.nameEnabled) {
            NSString *infoStr = [NSString stringWithFormat:@"%s [%.0fm]", p.name.c_str(), p.distance];
            NSDictionary *atts = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:11.0f],
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSBackgroundColorAttributeName: [UIColor colorWithWhite:0.0f alpha:0.5f]
            };
            CGSize strSize = [infoStr sizeWithAttributes:atts];
            CGPoint textPos = CGPointMake(p.headScreenPos.x - (strSize.width / 2.0f), boxY - strSize.height - 2.0f);
            [infoStr drawAtPoint:textPos withAttributes:atts];
        }
    }
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

@end


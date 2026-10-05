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
        
        self.aimbotEnabled = NO;
        self.aimBone = 0; // 0: Head, 1: Chest
        self.aimFov = 120.0f;
        self.aimSmooth = 0.25f;
        self.isFiring = NO;
        
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

    // 0. Draw Smart Aimbot FOV Circle & Dynamic Crosshair
    if (self.aimbotEnabled && self.aimFov > 10.0f) {
        CGPoint screenCenter = CGPointMake(rect.size.width / 2.0f, rect.size.height / 2.0f);
        CGRect fovRect = CGRectMake(screenCenter.x - self.aimFov,
                                    screenCenter.y - self.aimFov,
                                    self.aimFov * 2.0f,
                                    self.aimFov * 2.0f);
        
        PlayerData bestTarget;
        Vector2 sCenter = Vector2{(float)screenCenter.x, (float)screenCenter.y};
        bool isLocked = GameLogic::getInstance().getBestTarget(sCenter, self.aimFov, (int)self.aimBone, bestTarget);

        // Dynamic FOV Circle Color
        UIColor *fovColor = isLocked 
            ? [UIColor colorWithRed:1.0f green:0.25f blue:0.45f alpha:0.65f]
            : [UIColor colorWithRed:0.2f green:0.8f blue:1.0f alpha:0.35f];
        
        CGContextSetStrokeColorWithColor(context, fovColor.CGColor);
        CGContextSetLineWidth(context, isLocked ? 1.5f : 1.0f);
        CGContextStrokeEllipseInRect(context, fovRect);

        // Center Crosshair (Precision Cross with Dot)
        UIColor *crossColor = isLocked 
            ? [UIColor colorWithRed:1.0f green:0.15f blue:0.35f alpha:0.95f]
            : [UIColor colorWithRed:0.3f green:0.9f blue:1.0f alpha:0.8f];
        
        CGContextSetStrokeColorWithColor(context, crossColor.CGColor);
        CGContextSetLineWidth(context, 1.2f);
        
        CGFloat crossSize = 7.0f;
        CGFloat crossGap = 3.0f;
        // Top line
        CGContextMoveToPoint(context, screenCenter.x, screenCenter.y - crossGap);
        CGContextAddLineToPoint(context, screenCenter.x, screenCenter.y - crossGap - crossSize);
        // Bottom line
        CGContextMoveToPoint(context, screenCenter.x, screenCenter.y + crossGap);
        CGContextAddLineToPoint(context, screenCenter.x, screenCenter.y + crossGap + crossSize);
        // Left line
        CGContextMoveToPoint(context, screenCenter.x - crossGap, screenCenter.y);
        CGContextAddLineToPoint(context, screenCenter.x - crossGap - crossSize, screenCenter.y);
        // Right line
        CGContextMoveToPoint(context, screenCenter.x + crossGap, screenCenter.y);
        CGContextAddLineToPoint(context, screenCenter.x + crossGap + crossSize, screenCenter.y);
        CGContextStrokePath(context);

        // Center Dot
        CGContextSetFillColorWithColor(context, crossColor.CGColor);
        CGContextFillEllipseInRect(context, CGRectMake(screenCenter.x - 2.0f, screenCenter.y - 2.0f, 4.0f, 4.0f));

        if (isLocked) {
            CGPoint targetPt = (self.aimBone == 0)
                ? CGPointMake(bestTarget.headScreenPos.x, bestTarget.headScreenPos.y)
                : CGPointMake((bestTarget.headScreenPos.x + bestTarget.toeScreenPos.x) * 0.5f,
                              bestTarget.headScreenPos.y + (bestTarget.toeScreenPos.y - bestTarget.headScreenPos.y) * 0.35f);
            
            // 1. Draw Aim Snap Line from crosshair to target head
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:1.0f green:0.2f blue:0.3f alpha:0.9f].CGColor);
            CGContextSetLineWidth(context, 1.6f);
            CGContextBeginPath(context);
            CGContextMoveToPoint(context, screenCenter.x, screenCenter.y);
            CGContextAddLineToPoint(context, targetPt.x, targetPt.y);
            CGContextStrokePath(context);

            // 2. Head Lock Target Ring
            CGFloat lockRingRadius = 11.0f;
            CGRect lockRingRect = CGRectMake(targetPt.x - lockRingRadius, targetPt.y - lockRingRadius, lockRingRadius * 2.0f, lockRingRadius * 2.0f);
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:1.0f green:0.15f blue:0.3f alpha:0.95f].CGColor);
            CGContextSetLineWidth(context, 1.8f);
            CGContextStrokeEllipseInRect(context, lockRingRect);

            // 3. Locked HUD Badge below crosshair
            NSString *lockBadge = [NSString stringWithFormat:@"🎯 LOCKED: %s (%.0fm)", bestTarget.name.c_str(), bestTarget.distance];
            NSDictionary *badgeAttrs = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10.5f],
                NSForegroundColorAttributeName: [UIColor colorWithRed:1.0f green:0.3f blue:0.45f alpha:1.0f]
            };
            CGSize badgeSize = [lockBadge sizeWithAttributes:badgeAttrs];
            CGPoint badgePt = CGPointMake(screenCenter.x - (badgeSize.width / 2.0f), screenCenter.y + 16.0f);
            
            CGRect bgBadgeRect = CGRectMake(badgePt.x - 4.0f, badgePt.y - 1.0f, badgeSize.width + 8.0f, badgeSize.height + 2.0f);
            UIBezierPath *bPath = [UIBezierPath bezierPathWithRoundedRect:bgBadgeRect cornerRadius:4.0f];
            CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.0f alpha:0.75f].CGColor);
            CGContextAddPath(context, bPath.CGPath);
            CGContextFillPath(context);

            [lockBadge drawAtPoint:badgePt withAttributes:badgeAttrs];
        }
    }

    const auto& players = GameLogic::getInstance().getPlayers();
    CGPoint topCenter = CGPointMake(rect.size.width / 2.0f, 0.0f);

    static int drawThrottle = 0;
    if (++drawThrottle % 60 == 1) {
        NSLog(@"[ESP_LOG] [DRAW_RECT] rect:(%.1f, %.1f) | bounds:(%.1f, %.1f) | frame:(%.1f, %.1f) | players:%zu",
              rect.size.width, rect.size.height, self.bounds.size.width, self.bounds.size.height, self.frame.size.width, self.frame.size.height, players.size());
    }

    for (const auto& p : players) {
        if (!p.isVisibleOnScreen) continue;

        // Screen Y: top of screen is 0, bottom is screenHeight.
        float topY = MIN(p.headScreenPos.y, p.toeScreenPos.y);
        float bottomY = MAX(p.headScreenPos.y, p.toeScreenPos.y);

        float height = bottomY - topY;
        if (height < 18.0f) height = 18.0f;
        if (height > rect.size.height * 1.5f) continue;

        // Natural human proportions (width ~ 0.48 of height)
        float boxPadding = height * 0.08f;
        float boxY = topY - boxPadding;
        float boxHeight = height + (boxPadding * 1.5f);
        float boxWidth = boxHeight * 0.48f;
        if (boxWidth < 9.0f) boxWidth = 9.0f;

        float boxX = p.headScreenPos.x - (boxWidth / 2.0f);

        // Skip any points outside visible screen range
        if (p.headScreenPos.x < -120.0f || p.headScreenPos.x > rect.size.width + 120.0f ||
            topY < -120.0f || topY > rect.size.height + 120.0f) {
            continue;
        }

        // 1. Line ESP (Red Line from Top-Center to Head)
        if (self.lineEnabled) {
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:1.0f green:0.25f blue:0.25f alpha:0.85f].CGColor);
            CGContextSetLineWidth(context, 1.2f);
            CGContextMoveToPoint(context, topCenter.x, topCenter.y);
            CGContextAddLineToPoint(context, p.headScreenPos.x, boxY);
            CGContextStrokePath(context);
        }

        // 2. Box ESP (Green Box around body)
        if (self.boxEnabled) {
            CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0f green:1.0f blue:0.4f alpha:0.95f].CGColor);
            CGContextSetLineWidth(context, 1.5f);
            CGContextAddRect(context, CGRectMake(boxX, boxY, boxWidth, boxHeight));
            CGContextStrokePath(context);
        }

        // 3. Health Bar (Sleek vertical bar on left of box)
        if (self.healthEnabled) {
            float healthRatio = (float)p.currentHP / (float)p.maxHP;
            if (healthRatio > 1.0f) healthRatio = 1.0f;
            if (healthRatio < 0.0f) healthRatio = 0.0f;

            float barWidth = 2.0f;
            float barX = boxX - 4.5f;
            float barHeight = boxHeight * healthRatio;
            float barY = boxY + (boxHeight - barHeight);

            // Dark background track
            CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.0f alpha:0.6f].CGColor);
            CGContextFillRect(context, CGRectMake(barX, boxY, barWidth, boxHeight));

            // Color gradient: Green -> Yellow -> Red
            UIColor *healthColor;
            if (healthRatio > 0.5f) {
                healthColor = [UIColor colorWithRed:2.0f * (1.0f - healthRatio) green:1.0f blue:0.0f alpha:0.95f];
            } else {
                healthColor = [UIColor colorWithRed:1.0f green:2.0f * healthRatio blue:0.0f alpha:0.95f];
            }
            CGContextSetFillColorWithColor(context, healthColor.CGColor);
            CGContextFillRect(context, CGRectMake(barX, barY, barWidth, barHeight));
        }

        // 4. Nickname & Distance (Neat pill background)
        if (self.nameEnabled) {
            NSString *infoStr = [NSString stringWithFormat:@"%s [%.0fm]", p.name.c_str(), p.distance];
            NSDictionary *atts = @{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:10.0f],
                NSForegroundColorAttributeName: [UIColor whiteColor],
            };
            CGSize strSize = [infoStr sizeWithAttributes:atts];
            CGPoint textPos = CGPointMake(p.headScreenPos.x - (strSize.width / 2.0f), boxY - strSize.height - 3.0f);

            CGRect bgRect = CGRectMake(textPos.x - 3.0f, textPos.y - 1.0f, strSize.width + 6.0f, strSize.height + 2.0f);
            UIBezierPath *bgPath = [UIBezierPath bezierPathWithRoundedRect:bgRect cornerRadius:3.0f];
            CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.0f alpha:0.65f].CGColor);
            CGContextAddPath(context, bgPath.CGPath);
            CGContextFillPath(context);

            [infoStr drawAtPoint:textPos withAttributes:atts];
        }
    }
}

- (void)dealloc {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

@end


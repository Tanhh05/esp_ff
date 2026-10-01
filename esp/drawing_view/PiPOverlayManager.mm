#import "PiPOverlayManager.h"
#import "../Core/GameLogic.h"
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <QuartzCore/QuartzCore.h>

@interface PiPOverlayManager () <AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate>

@property (nonatomic, strong) AVSampleBufferDisplayLayer *sampleBufferLayer;
@property (nonatomic, strong) AVPictureInPictureController *pipController;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) UIView *pipContainerView;
@property (nonatomic, weak) UIView *hostView;

@end

@implementation PiPOverlayManager

+ (instancetype)sharedManager {
    static PiPOverlayManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PiPOverlayManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _boxEnabled = YES;
        _lineEnabled = YES;
        _healthEnabled = YES;
        _nameEnabled = YES;
        _isPiPActive = NO;
        [self setupAudioSession];
    }
    return self;
}

- (void)setupAudioSession {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
}

- (void)setupWithParentView:(UIView *)parentView {
    self.hostView = parentView;

    [self setupAudioSession];

    if (self.pipContainerView) {
        [self.pipContainerView removeFromSuperview];
    }

    self.pipContainerView = [[UIView alloc] initWithFrame:CGRectMake(20, parentView.bounds.size.height - 110, 160, 90)];
    self.pipContainerView.backgroundColor = [UIColor blackColor];
    self.pipContainerView.layer.cornerRadius = 8.0f;
    self.pipContainerView.layer.masksToBounds = YES;
    self.pipContainerView.layer.borderWidth = 1.0f;
    self.pipContainerView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    [parentView addSubview:self.pipContainerView];

    self.sampleBufferLayer = [[AVSampleBufferDisplayLayer alloc] init];
    self.sampleBufferLayer.frame = self.pipContainerView.bounds;
    self.sampleBufferLayer.backgroundColor = [UIColor blackColor].CGColor;
    self.sampleBufferLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    CMTimebaseRef timebase = NULL;
    CMTimebaseCreateWithMasterClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase);
    if (timebase) {
        self.sampleBufferLayer.controlTimebase = timebase;
        CMTimebaseSetTime(timebase, CMTimeMake(0, 1000));
        CMTimebaseSetRate(timebase, 1.0);
    }

    [self.pipContainerView.layer addSublayer:self.sampleBufferLayer];

    if (@available(iOS 15.0, *)) {
        if ([AVPictureInPictureController isPictureInPictureSupported]) {
            AVPictureInPictureControllerContentSource *source = [[AVPictureInPictureControllerContentSource alloc] initWithSampleBufferDisplayLayer:self.sampleBufferLayer playbackDelegate:self];
            self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:source];
            self.pipController.delegate = self;
            self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
        }
    }

    // Generate initial idle frames so Pegasus has active media
    for (int i = 0; i < 5; i++) {
        [self renderInitialIdleFrame];
    }
}

- (void)renderInitialIdleFrame {
    CGSize size = CGSizeMake(736, 414);
    CVPixelBufferRef pixelBuffer = [self createPixelBufferWithSize:size];
    if (!pixelBuffer) return;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data, (size_t)size.width, (size_t)size.height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    if (context) {
        CGContextSetFillColorWithColor(context, [UIColor colorWithRed:0.05f green:0.05f blue:0.1f alpha:1.0f].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
        CGContextRelease(context);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    [self enqueuePixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
}

- (void)startPiP {
    [self setupAudioSession];

    self.isPiPActive = YES;

    if (!self.displayLink) {
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }

    // Render immediately
    [self onFrame];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.pipController) {
            if ([self.pipController isPictureInPicturePossible]) {
                [self.pipController startPictureInPicture];
                NSLog(@"[ESP_LOG] [PiP] Starting Picture in Picture...");
            } else {
                NSLog(@"[ESP_LOG] [PiP] isPictureInPicturePossible is currently NO (Auto-PiP will trigger when switching apps)");
            }
        }
    });
}

- (void)stopPiP {
    self.isPiPActive = NO;
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    if (self.pipController && [self.pipController isPictureInPictureActive]) {
        [self.pipController stopPictureInPicture];
    }
}

- (void)onFrame {
    if (!self.isPiPActive) return;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat width = MAX(screenSize.width, screenSize.height);
    CGFloat height = MIN(screenSize.width, screenSize.height);

    GameLogic::getInstance().updateData(width, height);

    CVPixelBufferRef pixelBuffer = [self createPixelBufferWithSize:CGSizeMake(width, height)];
    if (!pixelBuffer) return;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *data = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(data,
                                                 (size_t)width,
                                                 (size_t)height,
                                                 8,
                                                 bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    if (context) {
        CGContextClearRect(context, CGRectMake(0, 0, width, height));
        
        // Semi-transparent overlay canvas
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.0f alpha:0.15f].CGColor);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));

        const auto& players = GameLogic::getInstance().getPlayers();
        CGPoint topCenter = CGPointMake(width / 2.0f, 0.0f);

        for (const auto& p : players) {
            if (!p.isVisibleOnScreen) continue;

            float headY = p.headScreenPos.y;
            float toeY = p.toeScreenPos.y;
            float boxHeight = std::abs(toeY - headY);
            if (boxHeight < 10.0f) boxHeight = 10.0f;
            float boxWidth = boxHeight * 0.55f;

            float x = p.headScreenPos.x - (boxWidth / 2.0f);
            float y = headY;

            // 1. Line ESP
            if (self.lineEnabled) {
                CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:0.85].CGColor);
                CGContextSetLineWidth(context, 1.5f);
                CGContextMoveToPoint(context, topCenter.x, topCenter.y);
                CGContextAddLineToPoint(context, p.headScreenPos.x, headY);
                CGContextStrokePath(context);
            }

            // 2. Box ESP
            if (self.boxEnabled) {
                CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0.0 green:1.0 blue:0.4 alpha:0.95].CGColor);
                CGContextSetLineWidth(context, 2.0f);
                CGContextAddRect(context, CGRectMake(x, y, boxWidth, boxHeight));
                CGContextStrokePath(context);
            }

            // 3. Health Bar
            if (self.healthEnabled) {
                float healthRatio = (float)p.currentHP / (float)p.maxHP;
                if (healthRatio > 1.0f) healthRatio = 1.0f;
                if (healthRatio < 0.0f) healthRatio = 0.0f;

                float barWidth = 3.5f;
                float barX = x - 7.0f;
                float barH = boxHeight * healthRatio;
                float barY = y + (boxHeight - barH);

                CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0.1 alpha:0.6].CGColor);
                CGContextFillRect(context, CGRectMake(barX, y, barWidth, boxHeight));

                UIColor *healthColor = [UIColor colorWithRed:(1.0f - healthRatio) green:healthRatio blue:0.0f alpha:0.95f];
                CGContextSetFillColorWithColor(context, healthColor.CGColor);
                CGContextFillRect(context, CGRectMake(barX, barY, barWidth, barH));
            }

            // 4. Name & Distance
            if (self.nameEnabled) {
                NSString *infoText = [NSString stringWithFormat:@"%s [%.0fm]", p.name.c_str(), p.distance];
                NSDictionary *attributes = @{
                    NSFontAttributeName: [UIFont boldSystemFontOfSize:11.0f],
                    NSForegroundColorAttributeName: [UIColor whiteColor]
                };
                UIGraphicsPushContext(context);
                [infoText drawAtPoint:CGPointMake(x, y - 14.0f) withAttributes:attributes];
                UIGraphicsPopContext();
            }
        }

        CGContextRelease(context);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    [self enqueuePixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
}

- (CVPixelBufferRef)createPixelBufferWithSize:(CGSize)size {
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *options = @{
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)size.width,
                                          (size_t)size.height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)options,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess) return NULL;
    return pixelBuffer;
}

- (void)enqueuePixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CMSampleTimingInfo timingInfo;
    timingInfo.duration = CMTimeMake(1, 60);
    timingInfo.presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
    timingInfo.decodeTimeStamp = kCMTimeInvalid;

    CMVideoFormatDescriptionRef formatDesc = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (status != noErr) return;

    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                pixelBuffer,
                                                true,
                                                NULL,
                                                NULL,
                                                formatDesc,
                                                &timingInfo,
                                                &sampleBuffer);
    CFRelease(formatDesc);

    if (status == noErr && sampleBuffer) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        if (attachments && CFArrayGetCount(attachments) > 0) {
            CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        }

        if ([self.sampleBufferLayer isReadyForMoreMediaData]) {
            [self.sampleBufferLayer enqueueSampleBuffer:sampleBuffer];
        }
        CFRelease(sampleBuffer);
    }
}

#pragma mark - AVPictureInPictureSampleBufferPlaybackDelegate

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)pictureInPictureController {
    return NO;
}

- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)pictureInPictureController {
    return CMTimeRangeMake(kCMTimeZero, CMTimeMake(3600 * 24, 1));
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController setPlaying:(BOOL)playing {
    if (self.sampleBufferLayer && self.sampleBufferLayer.controlTimebase) {
        CMTimebaseSetRate(self.sampleBufferLayer.controlTimebase, playing ? 1.0 : 0.0);
    }
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController skipByInterval:(CMTime)skipInterval completionHandler:(void (^)(void))completionHandler {
    if (completionHandler) completionHandler();
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    NSLog(@"[ESP_LOG] [PiP] Picture in Picture started successfully!");
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    NSLog(@"[ESP_LOG] [PiP] Picture in Picture stopped.");
    self.isPiPActive = NO;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)pictureInPictureController failedToStartPictureInPictureWithError:(NSError *)error {
    NSLog(@"[ESP_LOG] [PiP] Failed to start Picture in Picture: %@", error.localizedDescription);
}

@end

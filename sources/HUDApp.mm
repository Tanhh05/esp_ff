//
//  HUDApp.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <notify.h>
#import "rootless.h"
#import <mach-o/dyld.h>
#import <sys/utsname.h>
#import <objc/runtime.h>
#import <signal.h>

#import "HUDHelper.h"
#import "TSEventFetcher.h"
#import "BackboardServices.h"
#import "AXEventRepresentation.h"
#import "UIApplication+Private.h"
#import "../esp/drawing_view/FloatingMenuView.h"
#import "../esp/drawing_view/esp.h"
#import "../esp/Core/GameLogic.h"
#import <mach/mach_time.h>

#ifdef __LP64__

typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

typedef uint32_t IOOptionBits;
typedef uint32_t IOHIDDigitizerTransducerType;
typedef uint32_t IOHIDEventField;
#define IOHIDEventFieldBase(type) (type << 16)
enum {
    kIOHIDEventTypeDigitizer = 11,
};
enum {
    kIOHIDDigitizerEventPosition = 1 << 2,
};
enum {
    kIOHIDEventFieldDigitizerX = IOHIDEventFieldBase(kIOHIDEventTypeDigitizer),
    kIOHIDEventFieldDigitizerY,
    kIOHIDEventFieldDigitizerTouch = IOHIDEventFieldBase(kIOHIDEventTypeDigitizer) + 9,
    kIOHIDEventFieldDigitizerIsDisplayIntegrated = IOHIDEventFieldBase(kIOHIDEventTypeDigitizer) + 25,
};

extern "C" IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, IOHIDEventField field);
extern "C" int IOHIDEventGetIntegerValue(IOHIDEventRef event, IOHIDEventField field);
extern "C" uint32_t IOHIDEventGetType(IOHIDEventRef event);
extern "C" CFArrayRef IOHIDEventGetChildren(IOHIDEventRef event);

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef void (*IOHIDEventSystemClientEventCallback)(void *target, void *refcon, void *service, IOHIDEventRef event);

extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator, uint32_t clientType, CFDictionaryRef options);
    void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client, IOHIDEventSystemClientEventCallback callback, void *target, void *refcon);
    void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef runloop, CFStringRef mode);
    void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
    void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
    IOHIDEventRef IOHIDEventCreateDigitizerFingerEventWithQuality(
        CFAllocatorRef allocator, AbsoluteTime timeStamp, uint32_t index,
        uint32_t identity, uint32_t eventMask, IOHIDFloat x, IOHIDFloat y,
        IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat twist,
        IOHIDFloat minorRadius, IOHIDFloat majorRadius, IOHIDFloat quality,
        IOHIDFloat density, IOHIDFloat irregularity, Boolean range, Boolean touch,
        IOOptionBits options);
    void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, int value);
}

void _HUDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event);

static void _IOHIDEventClientCallback(void *target, void *refcon, void *service, IOHIDEventRef event)
{
    if (!event) return;
    _HUDEventCallback(target, refcon, (IOHIDServiceRef)service, event);
}

void _HUDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event)
{
    static UIApplication *app = [UIApplication sharedApplication];
    
    // iOS 15.1+ has a new API for handling HID events.
    if (@available(iOS 15.1, *)) {}
    else {
        [app _enqueueHIDEvent:event];
    }

    if (!event) return;

    uint32_t eventType = IOHIDEventGetType(event);
    if (eventType != kIOHIDEventTypeDigitizer) return;

    // 1. Get raw point and state from AXEventRepresentation or IOHIDEvent
    CGPoint rawLoc = CGPointZero;
    BOOL isTouchDown = NO;
    BOOL isMove = NO;
    BOOL isLift = NO;

    static Class AXEventRepresentationCls = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
        AXEventRepresentationCls = objc_getClass("AXEventRepresentation");
    });

    static BOOL s_wasFingerDown = NO;
    AXEventRepresentation *rep = nil;

    @try {
        if (AXEventRepresentationCls) {
            rep = [AXEventRepresentationCls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
            if (rep) {
                rawLoc = [rep location];
                isTouchDown = [rep isTouchDown];
                isMove = [rep isMove];
                isLift = [rep isLift] || [rep isInRangeLift] || [rep isCancel];

                if (!isTouchDown && !isMove && !isLift) {
                    if (!s_wasFingerDown) {
                        isTouchDown = YES;
                        s_wasFingerDown = YES;
                    } else {
                        isMove = YES;
                    }
                } else {
                    if (isTouchDown) s_wasFingerDown = YES;
                    if (isLift) s_wasFingerDown = NO;
                }
            }
        }
    } @catch (NSException *e) {
        rep = nil;
    }

    int touchVal = IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerTouch);

    if (CGPointEqualToPoint(rawLoc, CGPointZero)) {
        CGFloat hx = (CGFloat)IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerX);
        CGFloat hy = (CGFloat)IOHIDEventGetFloatValue(event, kIOHIDEventFieldDigitizerY);
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat sw = MIN(screenBounds.size.width, screenBounds.size.height);
        CGFloat sh = MAX(screenBounds.size.width, screenBounds.size.height);
        
        if (hx <= 1.05f && hy <= 1.05f && (hx > 0.0f || hy > 0.0f)) {
            hx *= sw;
            hy *= sh;
        }
        rawLoc = CGPointMake(hx, hy);
        if (touchVal == 1) {
            if (!s_wasFingerDown) {
                isTouchDown = YES;
                s_wasFingerDown = YES;
            } else {
                isMove = YES;
            }
        } else {
            isLift = YES;
            s_wasFingerDown = NO;
        }
    }

    // 2. Count active fingers from IOHIDEvent children AND AXEvent paths
    CFArrayRef children = IOHIDEventGetChildren(event);
    CFIndex childCount = children ? CFArrayGetCount(children) : 0;
    uint32_t activeFingers = 0;
    if (childCount > 0) {
        for (CFIndex i = 0; i < childCount; i++) {
            IOHIDEventRef child = (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
            if (child) {
                int cTouch = IOHIDEventGetIntegerValue(child, kIOHIDEventFieldDigitizerTouch);
                if (cTouch == 1) {
                    activeFingers++;
                }
            }
        }
    }
    uint32_t currentFingers = activeFingers;
    if (currentFingers == 0 && childCount > 0 && !isLift && (isTouchDown || isMove || touchVal == 1)) {
        currentFingers = (uint32_t)childCount;
    }
    if (rep) {
        @try {
            NSArray *paths = [[rep handInfo] paths];
            if (paths && paths.count > currentFingers) {
                currentFingers = (uint32_t)paths.count;
            }
        } @catch (NSException *e) {}
    }
    if (currentFingers == 0 && (isTouchDown || isMove || touchVal == 1)) {
        currentFingers = 1;
    }

    if (isTouchDown || isLift) {
        NSLog(@"[ESP_LOG] [TOUCH] down:%d lift:%d fingers:%u children:%ld rep:%p loc:(%.1f, %.1f)",
              (int)isTouchDown, (int)isLift, currentFingers,
              childCount, rep, rawLoc.x, rawLoc.y);
    }

    // 3. Detect Multi-Finger (2 or 3 fingers) Double Tap gesture
    static double s_lastTap1Time = 0.0;
    static double s_lastToggleTime = 0.0;
    static BOOL s_inGestureTouch = NO;
    static double s_gestureTouchStartTime = 0.0;
    static uint32_t s_maxFingersInTap = 0;

    double nowTime = CACurrentMediaTime();

    if (currentFingers > 0 && !isLift) {
        if (!s_inGestureTouch) {
            s_inGestureTouch = YES;
            s_gestureTouchStartTime = nowTime;
            s_maxFingersInTap = currentFingers;
        } else {
            if (currentFingers > s_maxFingersInTap) {
                s_maxFingersInTap = currentFingers;
            }
        }

        if (s_maxFingersInTap >= 3) {
            // Check if this is Tap 2 within 0.50s of Tap 1
            if (s_lastTap1Time > 0.0 && (nowTime - s_lastTap1Time < 0.50) && (nowTime - s_lastToggleTime > 0.4)) {
                s_lastTap1Time = 0.0;
                s_lastToggleTime = nowTime;
                s_maxFingersInTap = 0;
                NSLog(@"[ESP_LOG] [GESTURE] >>> DETECTED 3-FINGER DOUBLE TAP! TOGGLING MENU! <<<");
                dispatch_async(dispatch_get_main_queue(), ^{
                    FloatingMenuView *floatingMenu = [FloatingMenuView sharedMenu];
                    if (floatingMenu) {
                        if (floatingMenu.isOpen) {
                            [floatingMenu closeMenuAnimated:YES];
                        } else {
                            [floatingMenu openMenuAnimated:YES];
                        }
                    }
                });
                return;
            }
        }
    } else {
        // Finger(s) lifted
        if (s_inGestureTouch) {
            double touchDuration = nowTime - s_gestureTouchStartTime;
            if (s_maxFingersInTap >= 3 && touchDuration < 0.45 && (nowTime - s_lastToggleTime > 0.4)) {
                s_lastTap1Time = nowTime;
                NSLog(@"[ESP_LOG] [GESTURE] Valid 3-Finger Tap 1 registered (fingers:%u duration:%.2fs)", s_maxFingersInTap, touchDuration);
            }
            s_inGestureTouch = NO;
            s_maxFingersInTap = 0;
        }
    }

    if (s_lastTap1Time > 0.0 && (nowTime - s_lastTap1Time >= 0.50)) {
        s_lastTap1Time = 0.0; // Expired
    }

    // 4. If point is zero, nothing more to dispatch
    if (CGPointEqualToPoint(rawLoc, CGPointZero)) return;

    // Ensure rawLoc is in points (if normalized 0..1, multiply by screen size)
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat sw = MIN(screenBounds.size.width, screenBounds.size.height);
    CGFloat sh = MAX(screenBounds.size.width, screenBounds.size.height);

    if (rawLoc.x <= 1.05f && rawLoc.y <= 1.05f && (rawLoc.x > 0.0f || rawLoc.y > 0.0f)) {
        rawLoc.x *= sw;
        rawLoc.y *= sh;
    }

    UITouchPhase phase = UITouchPhaseMoved;
    if (isTouchDown) phase = UITouchPhaseBegan;
    else if (isLift) phase = UITouchPhaseEnded;
    else if (isMove) phase = UITouchPhaseMoved;

    FloatingMenuView *floatingMenu = [FloatingMenuView sharedMenu];
    if (floatingMenu && floatingMenu.isOpen) {
        dispatch_async(dispatch_get_main_queue(), ^{
            FloatingMenuView *menu = [FloatingMenuView sharedMenu];
            if (!menu || !menu.isOpen) return;

            // Hardware portrait coordinates: rawLoc.x (0..sw), rawLoc.y (0..sh)
            // 1. Landscape Right (Home button / USB port on RIGHT side):
            CGPoint pLandscapeRight = CGPointMake(rawLoc.y, sw - rawLoc.x);
            // 2. Landscape Left (Home button / USB port on LEFT side):
            CGPoint pLandscapeLeft = CGPointMake(sh - rawLoc.y, rawLoc.x);
            // 3. Portrait:
            CGPoint pPortrait = rawLoc;
            // 4. Portrait Upside Down:
            CGPoint pPortraitUpsideDown = CGPointMake(sw - rawLoc.x, sh - rawLoc.y);

            static int s_activeTouchOrientation = 0; // 1: LR, 2: LL, 3: Port, 4: PortUD

            if (phase == UITouchPhaseBegan) {
                s_activeTouchOrientation = 0;
                if ([menu handleDirectTouchAtPoint:pLandscapeRight phase:phase]) {
                    s_activeTouchOrientation = 1;
                } else if ([menu handleDirectTouchAtPoint:pLandscapeLeft phase:phase]) {
                    s_activeTouchOrientation = 2;
                } else if ([menu handleDirectTouchAtPoint:pPortrait phase:phase]) {
                    s_activeTouchOrientation = 3;
                } else if ([menu handleDirectTouchAtPoint:pPortraitUpsideDown phase:phase]) {
                    s_activeTouchOrientation = 4;
                }
            } else if (phase == UITouchPhaseMoved) {
                CGPoint targetPt = pLandscapeRight;
                if (s_activeTouchOrientation == 1) targetPt = pLandscapeRight;
                else if (s_activeTouchOrientation == 2) targetPt = pLandscapeLeft;
                else if (s_activeTouchOrientation == 3) targetPt = pPortrait;
                else if (s_activeTouchOrientation == 4) targetPt = pPortraitUpsideDown;
                
                [menu handleDirectTouchAtPoint:targetPt phase:phase];
            } else if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
                CGPoint targetPt = pLandscapeRight;
                if (s_activeTouchOrientation == 1) targetPt = pLandscapeRight;
                else if (s_activeTouchOrientation == 2) targetPt = pLandscapeLeft;
                else if (s_activeTouchOrientation == 3) targetPt = pPortrait;
                else if (s_activeTouchOrientation == 4) targetPt = pPortraitUpsideDown;
                
                [menu handleDirectTouchAtPoint:targetPt phase:phase];
                s_activeTouchOrientation = 0;
            }
        });
        return;
    }

    // 5. Aimbot Touch Drag Assist (Active during gameplay when Menu is closed)
    ESP_View *espView = [ESP_View sharedView];
    if (espView && espView.aimbotEnabled) {
        CGFloat screenW = sh; // Landscape Width (e.g. 736)
        CGFloat screenH = sw; // Landscape Height (e.g. 414)

        // Landscape Right position of player's touch
        CGPoint pLandscape = CGPointMake(rawLoc.y, sw - rawLoc.x);

        // Check if player is touching the right half / aim & shoot area (X > 38% of screen)
        BOOL isAimingZone = (pLandscape.x > screenW * 0.38f);
        BOOL isTouchActive = (isTouchDown || isMove || touchVal == 1);

        if (isAimingZone && isTouchActive) {
            PlayerData bestTarget;
            Vector2 sCenter = Vector2{(float)(screenW / 2.0f), (float)(screenH / 2.0f)};
            float aimFov = espView.aimFov;
            int aimBone = (int)espView.aimBone;

            if (GameLogic::getInstance().getBestTarget(sCenter, aimFov, aimBone, bestTarget)) {
                CGPoint targetPt = (aimBone == 0)
                    ? CGPointMake(bestTarget.headScreenPos.x, bestTarget.headScreenPos.y)
                    : CGPointMake((bestTarget.headScreenPos.x + bestTarget.toeScreenPos.x) * 0.5f,
                                  bestTarget.headScreenPos.y + (bestTarget.toeScreenPos.y - bestTarget.headScreenPos.y) * 0.35f);

                float deltaX = (float)(targetPt.x - (screenW / 2.0f));
                float deltaY = (float)(targetPt.y - (screenH / 2.0f));
                float dist = sqrtf(deltaX * deltaX + deltaY * deltaY);

                if (dist > 2.5f && dist <= aimFov) {
                    float smooth = espView.aimSmooth;
                    if (smooth <= 0.01f) smooth = 0.22f;

                    float stepX = deltaX * smooth;
                    float stepY = deltaY * smooth;

                    // Limit step to keep movement natural and avoid overshooting
                    float maxStep = 16.0f;
                    if (stepX > maxStep) stepX = maxStep;
                    if (stepX < -maxStep) stepX = -maxStep;
                    if (stepY > maxStep) stepY = maxStep;
                    if (stepY < -maxStep) stepY = -maxStep;

                    // Convert drag destination to portrait hardware coords
                    CGFloat dragLsX = pLandscape.x + stepX;
                    CGFloat dragLsY = pLandscape.y + stepY;
                    CGFloat dragPortX = sw - dragLsY;
                    CGFloat dragPortY = dragLsX;

                    uint64_t abTime = mach_absolute_time();
                    AbsoluteTime timeStamp;
                    timeStamp.hi = (UInt32)(abTime >> 32);
                    timeStamp.lo = (UInt32)(abTime);

                    static IOHIDEventSystemClientRef s_aimSenderClient = NULL;
                    static dispatch_once_t s_aimOnce;
                    dispatch_once(&s_aimOnce, ^{
                        s_aimSenderClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
                    });

                    IOHIDEventRef dragEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
                        kCFAllocatorDefault,
                        timeStamp,
                        1, // finger index 1
                        2, // identity
                        kIOHIDDigitizerEventPosition,
                        (IOHIDFloat)dragPortX,
                        (IOHIDFloat)dragPortY,
                        0.0, 0, 0, 5.0, 5.0, 1.0, 1.0, 1.0, true, true, 0);

                    if (dragEvent) {
                        IOHIDEventSetIntegerValue(dragEvent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
                        if (s_aimSenderClient) {
                            IOHIDEventSystemClientDispatchEvent(s_aimSenderClient, dragEvent);
                        }
                        CFRelease(dragEvent);
                    }
                }
            }
        }
    }
}


int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        if (argc <= 1) {
            return UIApplicationMain(argc, argv, @"MainApplication", @"MainApplicationDelegate");
        }

        if (strcmp(argv[1], "-hud") == 0)
        {
            pid_t pid = getpid();
            NSLog(@"[ESP_LOG] [HUD_PROCESS] >>> Launching HUD background process (PID: %d)...", (int)pid);

            NSString *pidString = [NSString stringWithFormat:@"%d", pid];
            [pidString writeToFile:ROOT_PATH_NS(PID_PATH)
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil];

            [UIScreen initialize];
            CFRunLoopGetCurrent();

            GSInitialize();
            BKSDisplayServicesStart();
            UIApplicationInitialize();

            UIApplicationInstantiateSingleton(objc_getClass("HUDMainApplication"));
            static id<UIApplicationDelegate> appDelegate = [[objc_getClass("HUDMainApplicationDelegate") alloc] init];
            [UIApplication.sharedApplication setDelegate:appDelegate];
            [UIApplication.sharedApplication _accessibilityInit];

            [NSRunLoop currentRunLoop];
            BKSHIDEventRegisterEventCallback(_HUDEventCallback);

            IOHIDEventSystemClientRef hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
            if (!hidClient) {
                hidClient = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 1, NULL);
            }
            if (!hidClient) {
                hidClient = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, 2, NULL);
            }
            if (hidClient) {
                NSLog(@"[ESP_LOG] [HID_INIT] Successfully created IOHIDEventSystemClient: %p", hidClient);
                IOHIDEventSystemClientRegisterEventCallback(hidClient, _IOHIDEventClientCallback, NULL, NULL);
                IOHIDEventSystemClientScheduleWithRunLoop(hidClient, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
            } else {
                NSLog(@"[ESP_LOG] [HID_INIT] Failed to create IOHIDEventSystemClient!");
            }

            if (@available(iOS 15.0, *)) {
                GSEventInitialize(0);
                GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
            }

            static int _destroyHUDToken;
            notify_register_dispatch(NOTIFY_DESTROY_HUD, &_destroyHUDToken, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(int token) {
                NSLog(@"[ESP_LOG] [HUD_PROCESS] Received NOTIFY_DESTROY_HUD -> exiting PID: %d", (int)pid);
                unlink([ROOT_PATH_NS(PID_PATH) UTF8String]);
                exit(0);
            });

            signal(SIGTERM, [](int) {
                unlink([ROOT_PATH_NS(PID_PATH) UTF8String]);
                exit(0);
            });
            signal(SIGINT, [](int) {
                unlink([ROOT_PATH_NS(PID_PATH) UTF8String]);
                exit(0);
            });

            NSLog(@"[ESP_LOG] [HUD_PROCESS] Calling __completeAndRunAsPlugin...");
            [UIApplication.sharedApplication __completeAndRunAsPlugin];
            NSLog(@"[ESP_LOG] [HUD_PROCESS] __completeAndRunAsPlugin executed!");

            static int _springboardBootToken;
            notify_register_dispatch("SBSpringBoardDidLaunchNotification", &_springboardBootToken, dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);

                notify_post(NOTIFY_DESTROY_HUD);

                // Re-enable HUD after SpringBoard is launched.
                SetHUDEnabled(YES);

                // Exit the current instance of HUD.
                kill(pid, SIGKILL);
            });

            CFRunLoopRun();
            return EXIT_SUCCESS;
        }
    }
}


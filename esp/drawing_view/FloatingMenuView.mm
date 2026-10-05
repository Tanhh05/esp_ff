#import "FloatingMenuView.h"
#import "esp.h"

@interface BubbleButton : UIButton {
    CGPoint _startTouchPointInParent;
    CGPoint _startCenter;
    BOOL _isDragging;
}
@property (nonatomic, copy) void (^onTapBlock)(void);
@property (nonatomic, copy) void (^onDragBlock)(CGPoint newCenter);
@end

@implementation BubbleButton

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    UITouch *t = [touches anyObject];
    _startTouchPointInParent = [t locationInView:self.superview];
    _startCenter = self.center;
    _isDragging = NO;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    UITouch *t = [touches anyObject];
    CGPoint curTouch = [t locationInView:self.superview];
    CGFloat dx = curTouch.x - _startTouchPointInParent.x;
    CGFloat dy = curTouch.y - _startTouchPointInParent.y;
    
    if (hypot(dx, dy) > 6.0f) {
        _isDragging = YES;
    }
    
    if (_isDragging) {
        CGPoint newCenter = CGPointMake(_startCenter.x + dx, _startCenter.y + dy);
        if (self.onDragBlock) {
            self.onDragBlock(newCenter);
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (!_isDragging) {
        if (self.onTapBlock) {
            self.onTapBlock();
        }
    }
    _isDragging = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    _isDragging = NO;
}

@end

@interface FloatingMenuView () {
    CGPoint _bubbleCenter;
    UISwitch *_boxSwitch;
    UISwitch *_lineSwitch;
    UISwitch *_healthSwitch;
    UISwitch *_nameSwitch;
    
    UISwitch *_aimbotSwitch;
    UISegmentedControl *_aimBoneSegment;
    UISlider *_fovSlider;
    UILabel *_fovValueLabel;
    
    BOOL _isDirectDragging;
    CGPoint _directDragStartPoint;
    CGPoint _directDragStartCenter;
}

@property (nonatomic, assign, readwrite) BOOL isOpen;
@property (nonatomic, strong, readwrite) UIView *menuCard;
@property (nonatomic, strong, readwrite) BubbleButton *bubbleButton;

@end

@implementation FloatingMenuView

+ (instancetype)sharedMenu {
    static FloatingMenuView *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat w = MAX(screenBounds.size.width, screenBounds.size.height);
        CGFloat h = MIN(screenBounds.size.width, screenBounds.size.height);
        instance = [[FloatingMenuView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    });
    return instance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _isOpen = NO;

        [self setupUI];
    }
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 1. Check Bubble Button (with generous margin)
    if (_bubbleButton && !_bubbleButton.hidden && _bubbleButton.alpha > 0.05f) {
        CGPoint ptInBubble = [self convertPoint:point toView:_bubbleButton];
        if (CGRectContainsPoint(CGRectInset(_bubbleButton.bounds, -12, -12), ptInBubble)) {
            UIView *hit = [_bubbleButton hitTest:ptInBubble withEvent:event];
            return hit ?: _bubbleButton;
        }
    }

    // 2. Check Menu Card (when open)
    if (_isOpen && _menuCard && !_menuCard.hidden && _menuCard.alpha > 0.1f) {
        CGPoint ptInMenu = [self convertPoint:point toView:_menuCard];
        if (CGRectContainsPoint(_menuCard.bounds, ptInMenu)) {
            UIView *hit = [_menuCard hitTest:ptInMenu withEvent:event];
            return hit ?: _menuCard;
        }
    }

    // 3. Transparent area: MUST return nil so game controls NEVER freeze!
    return nil;
}

- (void)setupUI {
    // 1. Floating Bubble Button
    CGFloat bubbleSize = 52.0f;
    _bubbleCenter = CGPointMake(70.0f, 80.0f);

    _bubbleButton = [BubbleButton buttonWithType:UIButtonTypeCustom];
    _bubbleButton.frame = CGRectMake(_bubbleCenter.x - (bubbleSize / 2.0f),
                                     _bubbleCenter.y - (bubbleSize / 2.0f),
                                     bubbleSize, bubbleSize);
    _bubbleButton.layer.cornerRadius = bubbleSize / 2.0f;
    _bubbleButton.layer.masksToBounds = YES;
    _bubbleButton.layer.borderWidth = 2.0f;
    _bubbleButton.layer.borderColor = [UIColor colorWithRed:1.0f green:0.5f blue:0.7f alpha:0.9f].CGColor;
    _bubbleButton.backgroundColor = [UIColor colorWithRed:0.12f green:0.13f blue:0.18f alpha:0.9f];

    // Try to load icon image
    UIImage *iconImg = [UIImage imageNamed:@"AppIcon60x60"];
    if (!iconImg) iconImg = [UIImage imageNamed:@"icon"];
    if (!iconImg) {
        NSString *resPath = [[NSBundle mainBundle] pathForResource:@"AppIcon60x60@2x" ofType:@"png"];
        if (resPath) iconImg = [UIImage imageWithContentsOfFile:resPath];
    }

    if (iconImg) {
        [_bubbleButton setImage:iconImg forState:UIControlStateNormal];
        _bubbleButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
    } else {
        [_bubbleButton setTitle:@"🐻" forState:UIControlStateNormal];
        _bubbleButton.titleLabel.font = [UIFont systemFontOfSize:26.0f];
    }

    // Shadow on wrapper
    _bubbleButton.layer.shadowColor = [UIColor colorWithRed:1.0f green:0.4f blue:0.7f alpha:0.6f].CGColor;
    _bubbleButton.layer.shadowOffset = CGSizeMake(0, 3);
    _bubbleButton.layer.shadowRadius = 6.0f;
    _bubbleButton.layer.shadowOpacity = 0.8f;

    __weak FloatingMenuView *weakSelf = self;
    _bubbleButton.onTapBlock = ^{
        [weakSelf onBubbleTapped];
    };
    _bubbleButton.onDragBlock = ^(CGPoint newCenter) {
        [weakSelf handleBubbleDrag:newCenter];
    };

    _bubbleButton.hidden = YES; // Hidden in favor of 3-finger double tap gesture
    [self addSubview:_bubbleButton];

    // 2. Menu Card (Glassmorphism design)
    CGFloat menuW = 230.0f;
    CGFloat menuH = 345.0f;
    _menuCard = [[UIView alloc] initWithFrame:CGRectMake(20, 20, menuW, menuH)];
    _menuCard.backgroundColor = [UIColor colorWithRed:0.10f green:0.11f blue:0.16f alpha:0.95f];
    _menuCard.layer.cornerRadius = 18.0f;
    _menuCard.layer.borderWidth = 1.2f;
    _menuCard.layer.borderColor = [UIColor colorWithWhite:0.3f alpha:0.6f].CGColor;
    _menuCard.layer.shadowColor = [UIColor blackColor].CGColor;
    _menuCard.layer.shadowOffset = CGSizeMake(0, 6);
    _menuCard.layer.shadowRadius = 14.0f;
    _menuCard.layer.shadowOpacity = 0.6f;
    _menuCard.alpha = 0.0f;
    _menuCard.hidden = YES;
    _menuCard.transform = CGAffineTransformMakeScale(0.7f, 0.7f);

    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, menuW - 32, 22)];
    titleLabel.text = @"ESP & AIMBOT SETTINGS";
    titleLabel.textColor = [UIColor colorWithRed:1.0f green:0.55f blue:0.75f alpha:1.0f];
    titleLabel.font = [UIFont boldSystemFontOfSize:12.5f];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.userInteractionEnabled = NO;
    [_menuCard addSubview:titleLabel];

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(menuW - 32, 10, 24, 24);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.75f alpha:1.0f] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    [closeBtn addTarget:self action:@selector(onCloseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [_menuCard addSubview:closeBtn];

    UIView *div1 = [[UIView alloc] initWithFrame:CGRectMake(16, 36, menuW - 32, 1)];
    div1.backgroundColor = [UIColor colorWithWhite:0.25f alpha:0.6f];
    div1.userInteractionEnabled = NO;
    [_menuCard addSubview:div1];

    // ESP Switches
    CGFloat curY = 42.0f;
    _boxSwitch = [self createToggleRowInMenu:_menuCard y:curY title:@"Box ESP" selector:@selector(onToggleChanged:) defaultOn:[ESP_View sharedView].boxEnabled];
    curY += 36.0f;
    _lineSwitch = [self createToggleRowInMenu:_menuCard y:curY title:@"Line ESP" selector:@selector(onToggleChanged:) defaultOn:[ESP_View sharedView].lineEnabled];
    curY += 36.0f;
    _healthSwitch = [self createToggleRowInMenu:_menuCard y:curY title:@"Health Bar" selector:@selector(onToggleChanged:) defaultOn:[ESP_View sharedView].healthEnabled];
    curY += 36.0f;
    _nameSwitch = [self createToggleRowInMenu:_menuCard y:curY title:@"Name & Dist" selector:@selector(onToggleChanged:) defaultOn:[ESP_View sharedView].nameEnabled];
    curY += 38.0f;

    // Divider 2
    UIView *div2 = [[UIView alloc] initWithFrame:CGRectMake(16, curY, menuW - 32, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:0.25f alpha:0.6f];
    div2.userInteractionEnabled = NO;
    [_menuCard addSubview:div2];
    curY += 8.0f;

    // Aimbot Switches & Controls
    _aimbotSwitch = [self createToggleRowInMenu:_menuCard y:curY title:@"Aimbot Lock" selector:@selector(onAimbotToggleChanged:) defaultOn:[ESP_View sharedView].aimbotEnabled];
    curY += 40.0f;

    // Aim Bone Selector
    UILabel *boneLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, curY + 2, 70, 24)];
    boneLbl.text = @"Aim Bone";
    boneLbl.textColor = [UIColor whiteColor];
    boneLbl.font = [UIFont systemFontOfSize:13.5f weight:UIFontWeightMedium];
    boneLbl.userInteractionEnabled = NO;
    [_menuCard addSubview:boneLbl];

    _aimBoneSegment = [[UISegmentedControl alloc] initWithItems:@[@"Head", @"Chest"]];
    _aimBoneSegment.frame = CGRectMake(menuW - 126, curY, 110, 26);
    _aimBoneSegment.selectedSegmentIndex = [ESP_View sharedView].aimBone;
    _aimBoneSegment.selectedSegmentTintColor = [UIColor colorWithRed:1.0f green:0.3f blue:0.5f alpha:0.85f];
    [_aimBoneSegment setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:11.5f weight:UIFontWeightBold]} forState:UIControlStateNormal];
    [_aimBoneSegment addTarget:self action:@selector(onBoneChanged:) forControlEvents:UIControlEventValueChanged];
    [_menuCard addSubview:_aimBoneSegment];
    curY += 38.0f;

    // FOV Slider & Label
    _fovValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, curY, menuW - 32, 18)];
    _fovValueLabel.text = [NSString stringWithFormat:@"FOV Radius: %.0fpx", [ESP_View sharedView].aimFov];
    _fovValueLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
    _fovValueLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightMedium];
    _fovValueLabel.userInteractionEnabled = NO;
    [_menuCard addSubview:_fovValueLabel];
    curY += 20.0f;

    _fovSlider = [[UISlider alloc] initWithFrame:CGRectMake(16, curY, menuW - 32, 24)];
    _fovSlider.minimumValue = 40.0f;
    _fovSlider.maximumValue = 300.0f;
    _fovSlider.value = [ESP_View sharedView].aimFov;
    _fovSlider.minimumTrackTintColor = [UIColor colorWithRed:1.0f green:0.35f blue:0.6f alpha:1.0f];
    [_fovSlider addTarget:self action:@selector(onFovChanged:) forControlEvents:UIControlEventValueChanged];
    [_menuCard addSubview:_fovSlider];

    [self addSubview:_menuCard];
}

- (UISwitch *)createToggleRowInMenu:(UIView *)menu y:(CGFloat)y title:(NSString *)title selector:(SEL)selector defaultOn:(BOOL)isOn {
    CGFloat menuW = menu.bounds.size.width;

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y + 2, menuW - 80, 24)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:13.5f weight:UIFontWeightMedium];
    lbl.userInteractionEnabled = NO;
    [menu addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(menuW - 58, y - 2, 46, 26)];
    sw.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
    sw.on = isOn;
    sw.onTintColor = [UIColor colorWithRed:0.0f green:0.8f blue:0.45f alpha:1.0f];
    sw.userInteractionEnabled = YES;
    [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [menu addSubview:sw];

    return sw;
}

- (void)onToggleChanged:(UISwitch *)sender {
    ESP_View *esp = [ESP_View sharedView];
    esp.boxEnabled = _boxSwitch.isOn;
    esp.lineEnabled = _lineSwitch.isOn;
    esp.healthEnabled = _healthSwitch.isOn;
    esp.nameEnabled = _nameSwitch.isOn;
    NSLog(@"[ESP_LOG] [MENU] onToggleChanged -> Box:%d Line:%d HP:%d Name:%d",
          (int)esp.boxEnabled, (int)esp.lineEnabled, (int)esp.healthEnabled, (int)esp.nameEnabled);
}

- (void)onAimbotToggleChanged:(UISwitch *)sender {
    ESP_View *esp = [ESP_View sharedView];
    esp.aimbotEnabled = _aimbotSwitch.isOn;
    NSLog(@"[ESP_LOG] [MENU] onAimbotToggleChanged -> Aimbot:%d", (int)esp.aimbotEnabled);
}

- (void)onBoneChanged:(UISegmentedControl *)sender {
    ESP_View *esp = [ESP_View sharedView];
    esp.aimBone = sender.selectedSegmentIndex;
    NSLog(@"[ESP_LOG] [MENU] onBoneChanged -> Bone:%ld (%s)", (long)esp.aimBone, esp.aimBone == 0 ? "Head" : "Chest");
}

- (void)onFovChanged:(UISlider *)sender {
    ESP_View *esp = [ESP_View sharedView];
    esp.aimFov = sender.value;
    _fovValueLabel.text = [NSString stringWithFormat:@"FOV Radius: %.0fpx", esp.aimFov];
}

- (void)handleBubbleDrag:(CGPoint)newCenter {
    CGFloat radius = _bubbleButton.bounds.size.width / 2.0f;
    CGFloat minX = radius + 10.0f;
    CGFloat maxX = self.bounds.size.width - radius - 10.0f;
    CGFloat minY = radius + 10.0f;
    CGFloat maxY = self.bounds.size.height - radius - 10.0f;

    newCenter.x = MAX(minX, MIN(maxX, newCenter.x));
    newCenter.y = MAX(minY, MIN(maxY, newCenter.y));

    _bubbleButton.center = newCenter;
    _bubbleCenter = newCenter;
}

- (void)onBubbleTapped {
    NSLog(@"[ESP_LOG] [MENU] onBubbleTapped tapped! Current isOpen: %d", (int)_isOpen);
    if (_isOpen) {
        [self closeMenuAnimated:YES];
    } else {
        [self openMenuAnimated:YES];
    }
}

- (void)openMenuAnimated:(BOOL)animated {
    if (_isOpen) return;
    _isOpen = YES;
    NSLog(@"[ESP_LOG] [MENU] Opening menu card at screen center...");

    CGFloat menuW = _menuCard.bounds.size.width;
    CGFloat menuH = _menuCard.bounds.size.height;

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenW = MAX(screenBounds.size.width, screenBounds.size.height);
    CGFloat screenH = MIN(screenBounds.size.width, screenBounds.size.height);

    CGFloat containerW = (self.bounds.size.width > 50.0f) ? self.bounds.size.width : screenW;
    CGFloat containerH = (self.bounds.size.height > 50.0f) ? self.bounds.size.height : screenH;

    // Center menu card on screen
    CGFloat targetX = (containerW - menuW) / 2.0f;
    CGFloat targetY = (containerH - menuH) / 2.0f;

    if (targetX < 15.0f) targetX = 15.0f;
    if (targetY < 15.0f) targetY = 15.0f;

    CGRect frame = _menuCard.frame;
    frame.origin = CGPointMake(targetX, targetY);
    _menuCard.frame = frame;

    _menuCard.hidden = NO;

    _boxSwitch.on = [ESP_View sharedView].boxEnabled;
    _lineSwitch.on = [ESP_View sharedView].lineEnabled;
    _healthSwitch.on = [ESP_View sharedView].healthEnabled;
    _nameSwitch.on = [ESP_View sharedView].nameEnabled;
    _aimbotSwitch.on = [ESP_View sharedView].aimbotEnabled;
    _aimBoneSegment.selectedSegmentIndex = [ESP_View sharedView].aimBone;
    _fovSlider.value = [ESP_View sharedView].aimFov;
    _fovValueLabel.text = [NSString stringWithFormat:@"FOV Radius: %.0fpx", [ESP_View sharedView].aimFov];

    if (animated) {
        _menuCard.alpha = 0.0f;
        _menuCard.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.6 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self->_menuCard.alpha = 1.0f;
            self->_menuCard.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        _menuCard.alpha = 1.0f;
        _menuCard.transform = CGAffineTransformIdentity;
    }
}

- (void)closeMenuAnimated:(BOOL)animated {
    if (!_isOpen) return;
    _isOpen = NO;
    NSLog(@"[ESP_LOG] [MENU] Closing menu card...");

    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            self->_menuCard.alpha = 0.0f;
            self->_menuCard.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
        } completion:^(BOOL finished) {
            self->_menuCard.hidden = YES;
        }];
    } else {
        _menuCard.alpha = 0.0f;
        _menuCard.hidden = YES;
    }
}

- (void)onCloseButtonTapped {
    [self closeMenuAnimated:YES];
}

- (BOOL)handleDirectTouchAtPoint:(CGPoint)pt phase:(UITouchPhase)phase {
    static double s_lastToggleTime = 0.0;
    double now = CACurrentMediaTime();

    // 1. Check Bubble Button hit (only if bubble is visible)
    if (_bubbleButton && !_bubbleButton.hidden && _bubbleButton.alpha > 0.05f) {
        CGRect bubbleHitRect = CGRectInset(_bubbleButton.frame, -20, -20);
        if (CGRectContainsPoint(bubbleHitRect, pt)) {
            if (phase == UITouchPhaseBegan) {
                _isDirectDragging = YES;
                _directDragStartPoint = pt;
                _directDragStartCenter = _bubbleButton.center;
                if (now - s_lastToggleTime > 0.25) {
                    s_lastToggleTime = now;
                    [self onBubbleTapped];
                }
                return YES;
            } else if (phase == UITouchPhaseMoved) {
                if (_isDirectDragging) {
                    CGPoint newCenter = CGPointMake(_directDragStartCenter.x + (pt.x - _directDragStartPoint.x),
                                                    _directDragStartCenter.y + (pt.y - _directDragStartPoint.y));
                    [self handleBubbleDrag:newCenter];
                    return YES;
                }
            } else if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
                _isDirectDragging = NO;
                return YES;
            }
        }
    }

    // 2. Check Menu Card hit if open
    if (_isOpen && !_menuCard.hidden) {
        CGRect cardHitBounds = CGRectInset(_menuCard.frame, -8, -8);
        if (CGRectContainsPoint(cardHitBounds, pt)) {
            CGPoint ptInMenu = [self convertPoint:pt toView:_menuCard];
            CGFloat menuW = _menuCard.bounds.size.width;
            CGFloat menuH = _menuCard.bounds.size.height;

            // Row 7: FOV Slider (supports continuous drag on Began AND Moved!)
            if (ptInMenu.y >= 268.0f && ptInMenu.y <= menuH + 15.0f) {
                CGFloat sliderW = menuW - 32.0f;
                CGFloat relativeX = ptInMenu.x - 16.0f;
                if (relativeX < 0.0f) relativeX = 0.0f;
                if (relativeX > sliderW) relativeX = sliderW;
                float ratio = (float)(relativeX / sliderW);
                float newFov = _fovSlider.minimumValue + ratio * (_fovSlider.maximumValue - _fovSlider.minimumValue);
                _fovSlider.value = newFov;
                [self onFovChanged:_fovSlider];
                return YES;
            }

            // Other buttons trigger on Began
            if (phase == UITouchPhaseBegan) {
                // Close button (top right)
                if (ptInMenu.y <= 38.0f && ptInMenu.x >= menuW - 44.0f) {
                    [self closeMenuAnimated:YES];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Closed menu card");
                    return YES;
                }

                // Row 1: Box ESP (38..74)
                if (ptInMenu.y >= 38.0f && ptInMenu.y < 74.0f) {
                    [_boxSwitch setOn:!_boxSwitch.isOn animated:YES];
                    [self onToggleChanged:_boxSwitch];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Toggled Box ESP -> %d", (int)_boxSwitch.isOn);
                    return YES;
                }
                // Row 2: Line ESP (74..110)
                if (ptInMenu.y >= 74.0f && ptInMenu.y < 110.0f) {
                    [_lineSwitch setOn:!_lineSwitch.isOn animated:YES];
                    [self onToggleChanged:_lineSwitch];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Toggled Line ESP -> %d", (int)_lineSwitch.isOn);
                    return YES;
                }
                // Row 3: Health Bar (110..146)
                if (ptInMenu.y >= 110.0f && ptInMenu.y < 146.0f) {
                    [_healthSwitch setOn:!_healthSwitch.isOn animated:YES];
                    [self onToggleChanged:_healthSwitch];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Toggled Health Bar -> %d", (int)_healthSwitch.isOn);
                    return YES;
                }
                // Row 4: Name & Dist (146..186)
                if (ptInMenu.y >= 146.0f && ptInMenu.y < 186.0f) {
                    [_nameSwitch setOn:!_nameSwitch.isOn animated:YES];
                    [self onToggleChanged:_nameSwitch];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Toggled Name & Dist -> %d", (int)_nameSwitch.isOn);
                    return YES;
                }
                // Row 5: Aimbot Lock (186..228)
                if (ptInMenu.y >= 186.0f && ptInMenu.y < 228.0f) {
                    [_aimbotSwitch setOn:!_aimbotSwitch.isOn animated:YES];
                    [self onAimbotToggleChanged:_aimbotSwitch];
                    NSLog(@"[ESP_LOG] [MENU_TOUCH] Toggled Aimbot Lock -> %d", (int)_aimbotSwitch.isOn);
                    return YES;
                }
                // Row 6: Aim Bone (228..268)
                if (ptInMenu.y >= 228.0f && ptInMenu.y < 268.0f) {
                    if (ptInMenu.x >= menuW - 130.0f) {
                        if (ptInMenu.x < menuW - 72.0f) {
                            _aimBoneSegment.selectedSegmentIndex = 0; // Head
                        } else {
                            _aimBoneSegment.selectedSegmentIndex = 1; // Chest
                        }
                    } else {
                        _aimBoneSegment.selectedSegmentIndex = (_aimBoneSegment.selectedSegmentIndex == 0) ? 1 : 0;
                    }
                    [self onBoneChanged:_aimBoneSegment];
                    return YES;
                }
            }

            return YES;
        }
    }

    return NO;
}

@end




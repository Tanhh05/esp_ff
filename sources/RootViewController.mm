#import "RootViewController.h"
#import "HUDHelper.h"
#import "../esp/drawing_view/esp.h"
#import "../esp/Core/GameLogic.h"
#include <string>

@implementation RootViewController {
    UIButton *_hudButton;
    UILabel *_statusLabel;
    BOOL _isHudOpen;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];
    _isHudOpen = IsHUDEnabled();

    [self setupUI];
    [self updateHUDButtonState];
}

- (void)setupUI {
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat screenHeight = self.view.bounds.size.height;

    // Open HUD Main Button (Centered)
    _hudButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _hudButton.frame = CGRectMake(30, (screenHeight / 2.0f) - 40, screenWidth - 60, 56);
    _hudButton.backgroundColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:1.0f];
    [_hudButton setTitle:@"OPEN HUD (SpringBoard)" forState:UIControlStateNormal];
    [_hudButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _hudButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0f];
    _hudButton.layer.cornerRadius = 16.0f;
    _hudButton.layer.shadowColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:0.4f].CGColor;
    _hudButton.layer.shadowOffset = CGSizeMake(0, 4);
    _hudButton.layer.shadowRadius = 8.0f;
    _hudButton.layer.shadowOpacity = 1.0f;
    [_hudButton addTarget:self action:@selector(onOpenHudTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_hudButton];

    // Status Label Footer (Directly below button)
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, (screenHeight / 2.0f) + 36, screenWidth - 40, 30)];
    _statusLabel.text = @"Status: HUD Closed";
    _statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _statusLabel.font = [UIFont systemFontOfSize:14.0f weight:UIFontWeightMedium];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_statusLabel];
}

- (void)updateHUDButtonState {
    _isHudOpen = IsHUDEnabled();
    if (_isHudOpen) {
        [_hudButton setTitle:@"EXIT HUD" forState:UIControlStateNormal];
        _hudButton.backgroundColor = [UIColor colorWithRed:0.95f green:0.2f blue:0.3f alpha:1.0f];
        _hudButton.layer.shadowColor = [UIColor colorWithRed:0.95f green:0.2f blue:0.3f alpha:0.4f].CGColor;
        _statusLabel.text = @"Status: ESP Overlay is Active in SpringBoard!";
        _statusLabel.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.4f alpha:1.0f];
    } else {
        [_hudButton setTitle:@"OPEN HUD (SpringBoard)" forState:UIControlStateNormal];
        _hudButton.backgroundColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:1.0f];
        _hudButton.layer.shadowColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:0.4f].CGColor;
        _statusLabel.text = @"Status: HUD Closed";
        _statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    }
}

- (void)reloadMainButtonState {
    [self updateHUDButtonState];
}

- (void)onOpenHudTapped {
    BOOL isEnabled = IsHUDEnabled();
    SetHUDEnabled(!isEnabled);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateHUDButtonState];
    });
}

@end


#import "RootViewController.h"
#import "HUDHelper.h"
#import "../esp/drawing_view/esp.h"
#import "../esp/Core/GameLogic.h"
#include <string>

@implementation RootViewController {
    UIButton *_hudButton;
    UISwitch *_boxSwitch;
    UISwitch *_lineSwitch;
    UISwitch *_healthSwitch;
    UISwitch *_nameSwitch;
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

    // Header Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, screenWidth - 40, 36)];
    titleLabel.text = @"ESP FREE FIRE 1.132.1";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:24.0f];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];

    UILabel *subTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 96, screenWidth - 40, 20)];
    subTitle.text = @"SpringBoard Accessibility Overlay • TrollStore iOS 16.x";
    subTitle.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    subTitle.font = [UIFont systemFontOfSize:13.0f];
    subTitle.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:subTitle];

    // Status Card Container
    UIView *cardView = [[UIView alloc] initWithFrame:CGRectMake(20, 135, screenWidth - 40, 260)];
    cardView.backgroundColor = [UIColor colorWithRed:0.14 green:0.15 blue:0.20 alpha:1.0];
    cardView.layer.cornerRadius = 16.0f;
    cardView.layer.borderWidth = 1.0f;
    cardView.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1.0].CGColor;
    [self.view addSubview:cardView];

    // Switches
    CGFloat startY = 20;
    _boxSwitch = [self addToggleInCard:cardView y:&startY title:@"Box ESP" defaultState:YES selector:@selector(onToggleChanged:)];
    _lineSwitch = [self addToggleInCard:cardView y:&startY title:@"Line ESP" defaultState:YES selector:@selector(onToggleChanged:)];
    _healthSwitch = [self addToggleInCard:cardView y:&startY title:@"Health Bar" defaultState:YES selector:@selector(onToggleChanged:)];
    _nameSwitch = [self addToggleInCard:cardView y:&startY title:@"Name & Distance" defaultState:YES selector:@selector(onToggleChanged:)];

    // Open HUD Main Button
    _hudButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _hudButton.frame = CGRectMake(30, 420, screenWidth - 60, 54);
    _hudButton.backgroundColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:1.0f];
    [_hudButton setTitle:@"OPEN HUD (SpringBoard)" forState:UIControlStateNormal];
    [_hudButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _hudButton.titleLabel.font = [UIFont boldSystemFontOfSize:18.0f];
    _hudButton.layer.cornerRadius = 14.0f;
    _hudButton.layer.shadowColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:0.4f].CGColor;
    _hudButton.layer.shadowOffset = CGSizeMake(0, 4);
    _hudButton.layer.shadowRadius = 8.0f;
    _hudButton.layer.shadowOpacity = 1.0f;
    [_hudButton addTarget:self action:@selector(onOpenHudTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_hudButton];

    // Status Label Footer
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 490, screenWidth - 40, 24)];
    _statusLabel.text = @"Status: HUD Ready";
    _statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    _statusLabel.font = [UIFont systemFontOfSize:14.0f weight:UIFontWeightMedium];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_statusLabel];
}

- (UISwitch *)addToggleInCard:(UIView *)card y:(CGFloat *)y title:(NSString *)title defaultState:(BOOL)state selector:(SEL)selector {
    CGFloat cardWidth = card.bounds.size.width;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, *y, cardWidth - 90, 31)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:16.0f weight:UIFontWeightMedium];
    [card addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(cardWidth - 70, *y, 51, 31)];
    sw.on = state;
    sw.onTintColor = [UIColor colorWithRed:0.0f green:0.75f blue:0.4f alpha:1.0f];
    [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];

    *y += 55;
    return sw;
}

- (void)onToggleChanged:(UISwitch *)sender {
    ESPDrawingView *esp = [ESPDrawingView sharedView];
    esp.boxEnabled = _boxSwitch.isOn;
    esp.lineEnabled = _lineSwitch.isOn;
    esp.healthEnabled = _healthSwitch.isOn;
    esp.nameEnabled = _nameSwitch.isOn;
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


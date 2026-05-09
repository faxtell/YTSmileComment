#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoFetchValueLabelKey = &kYTNicoFetchValueLabelKey;
static const void *kYTNicoFetchProgressKey = &kYTNicoFetchProgressKey;

%hook YTNicoSettingsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, @selector(ytnico_addFetchCountSlider)) boolValue]) return;
    objc_setAssociatedObject(self, @selector(ytnico_addFetchCountSlider), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIStackView *stack = nil;
    @try { stack = [self valueForKey:@"stack"]; } @catch (__unused NSException *e) {}
    if (![stack isKindOfClass:UIStackView.class]) return;
    SettingsManager *settings = SettingsManager.shared;

    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 8.0;
    box.layoutMargins = UIEdgeInsetsMake(14,14,14,14);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    UILabel *title = [UILabel new];
    title.text = @"取得コメント数";
    title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UILabel *value = [UILabel new];
    value.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    value.textAlignment = NSTextAlignmentRight;
    UIStackView *top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    [top addArrangedSubview:title];
    [top addArrangedSubview:value];
    [box addArrangedSubview:top];
    UILabel *sub = [UILabel new];
    sub.text = @"多いほど途切れにくくなります。デフォルト500件、最大3000件です。";
    sub.numberOfLines = 0;
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = UIColor.secondaryLabelColor;
    [box addArrangedSubview:sub];
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [box addArrangedSubview:progress];
    UISlider *slider = [UISlider new];
    slider.minimumValue = 100;
    slider.maximumValue = 3000;
    slider.value = settings.maxFetchComments;
    [box addArrangedSubview:slider];
    objc_setAssociatedObject(slider, kYTNicoFetchValueLabelKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kYTNicoFetchProgressKey, progress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    value.text = [NSString stringWithFormat:@"%.0f 件", slider.value];
    progress.progress = (slider.value - 100.0f) / 2900.0f;
    [slider addTarget:self action:@selector(ytnico_fetchCountSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [stack insertArrangedSubview:card atIndex:MIN((NSUInteger)4, stack.arrangedSubviews.count)];

    UIView *debugCard = [UIView new];
    debugCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
    debugCard.layer.cornerRadius = 16.0;
    debugCard.layer.masksToBounds = YES;
    UIStackView *debugBox = [UIStackView new];
    debugBox.axis = UILayoutConstraintAxisVertical;
    debugBox.spacing = 10.0;
    debugBox.layoutMargins = UIEdgeInsetsMake(14,14,14,14);
    debugBox.layoutMarginsRelativeArrangement = YES;
    debugBox.translatesAutoresizingMaskIntoConstraints = NO;
    [debugCard addSubview:debugBox];
    [NSLayoutConstraint activateConstraints:@[
        [debugBox.leadingAnchor constraintEqualToAnchor:debugCard.leadingAnchor],
        [debugBox.trailingAnchor constraintEqualToAnchor:debugCard.trailingAnchor],
        [debugBox.topAnchor constraintEqualToAnchor:debugCard.topAnchor],
        [debugBox.bottomAnchor constraintEqualToAnchor:debugCard.bottomAnchor]
    ]];

    UIStackView *debugTop = [UIStackView new];
    debugTop.axis = UILayoutConstraintAxisHorizontal;
    debugTop.alignment = UIStackViewAlignmentCenter;
    UILabel *debugTitle = [UILabel new];
    debugTitle.text = @"デバッグログ";
    debugTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    UISwitch *debugSwitch = [UISwitch new];
    debugSwitch.on = settings.debugLogging;
    [debugSwitch addTarget:self action:@selector(ytnico_debugSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [debugTop addArrangedSubview:debugTitle];
    [debugTop addArrangedSubview:debugSwitch];
    [debugBox addArrangedSubview:debugTop];

    UILabel *debugSub = [UILabel new];
    debugSub.text = @"取得分岐・token有無・parse件数・overlay候補を記録します。修正依頼時はログをコピーして貼ってください。";
    debugSub.numberOfLines = 0;
    debugSub.font = [UIFont systemFontOfSize:12];
    debugSub.textColor = UIColor.secondaryLabelColor;
    [debugBox addArrangedSubview:debugSub];

    UIButton *copyLog = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyLog setTitle:@"ログをコピー" forState:UIControlStateNormal];
    copyLog.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    copyLog.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    copyLog.layer.cornerRadius = 12.0;
    copyLog.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    [copyLog addTarget:self action:@selector(ytnico_copyDebugLogs) forControlEvents:UIControlEventTouchUpInside];
    [debugBox addArrangedSubview:copyLog];

    UIButton *clearLog = [UIButton buttonWithType:UIButtonTypeSystem];
    [clearLog setTitle:@"ログを消去" forState:UIControlStateNormal];
    clearLog.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    clearLog.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    clearLog.layer.cornerRadius = 12.0;
    clearLog.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    [clearLog addTarget:self action:@selector(ytnico_clearDebugLogs) forControlEvents:UIControlEventTouchUpInside];
    [debugBox addArrangedSubview:clearLog];
    [stack addArrangedSubview:debugCard];

    UILabel *creditText = [UILabel new];
    creditText.text = @"クレジット";
    creditText.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    creditText.textColor = UIColor.secondaryLabelColor;
    creditText.textAlignment = NSTextAlignmentCenter;
    creditText.numberOfLines = 1;
    [stack addArrangedSubview:creditText];

    UIButton *developerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [developerButton setTitle:@"開発者: 🦈" forState:UIControlStateNormal];
    developerButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    developerButton.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    developerButton.layer.cornerRadius = 14.0;
    developerButton.contentEdgeInsets = UIEdgeInsetsMake(12, 14, 12, 14);
    [developerButton addTarget:self action:@selector(ytnico_openCreditLink) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:developerButton];
}

%new
- (void)ytnico_fetchCountSliderChanged:(UISlider *)slider {
    UILabel *value = objc_getAssociatedObject(slider, kYTNicoFetchValueLabelKey);
    UIProgressView *progress = objc_getAssociatedObject(slider, kYTNicoFetchProgressKey);
    [SettingsManager.shared setMaxFetchComments:(NSInteger)roundf(slider.value)];
    value.text = [NSString stringWithFormat:@"%.0f 件", slider.value];
    progress.progress = (slider.value - 100.0f) / 2900.0f;
}

%new
- (void)ytnico_debugSwitchChanged:(UISwitch *)sender {
    [SettingsManager.shared setDebugLogging:sender.on];
    [[DebugInspector shared] important:@"debugLogging=%d", sender.on];
}

%new
- (void)ytnico_copyDebugLogs {
    NSString *text = DebugInspector.shared.recentLogText;
    if (text.length == 0) text = @"YTNico debug log is empty.";
    UIPasteboard.generalPasteboard.string = text;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"コピーしました" message:@"デバッグログをクリップボードにコピーしました。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)ytnico_clearDebugLogs {
    [DebugInspector.shared clearLogs];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"消去しました" message:@"デバッグログを消去しました。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)ytnico_openCreditLink {
    NSURL *url = [NSURL URLWithString:@"https://x.com/sa_me_kun"];
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
        [app openURL:url];
    }
}
%end

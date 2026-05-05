#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoStyleScrollLabelKey = &kYTNicoStyleScrollLabelKey;
static const void *kYTNicoStyleOutlineLabelKey = &kYTNicoStyleOutlineLabelKey;

static UILabel *YTNicoStyleLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}

static UIButton *YTNicoStyleButton(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 12.0;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    return button;
}

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, @selector(ytnico_addNiconicoStyleCard)) boolValue]) return;
    objc_setAssociatedObject(self, @selector(ytnico_addNiconicoStyleCard), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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
    box.spacing = 10.0;
    box.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];

    UIStackView *top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    [top addArrangedSubview:YTNicoStyleLabel(@"ニコニコ風表示", 16, UIFontWeightSemibold, nil)];
    UISwitch *modeSwitch = [UISwitch new];
    modeSwitch.on = settings.niconicoMode;
    [modeSwitch addTarget:self action:@selector(ytnico_styleModeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [top addArrangedSubview:modeSwitch];
    [box addArrangedSubview:top];

    [box addArrangedSubview:YTNicoStyleLabel(@"白太字＋黒縁取り、固定時間スクロール、上から順に詰めるレーン選択へ寄せます。", 12, UIFontWeightRegular, UIColor.secondaryLabelColor)];

    UIButton *preset = YTNicoStyleButton(@"ニコニコ風プリセットを適用");
    [preset addTarget:self action:@selector(ytnico_applyStylePreset) forControlEvents:UIControlEventTouchUpInside];
    [box addArrangedSubview:preset];

    UIStackView *fontRow = [UIStackView new];
    fontRow.axis = UILayoutConstraintAxisHorizontal;
    fontRow.alignment = UIStackViewAlignmentCenter;
    [fontRow addArrangedSubview:YTNicoStyleLabel(@"動画サイズ連動フォント", 14, UIFontWeightMedium, nil)];
    UISwitch *fontSwitch = [UISwitch new];
    fontSwitch.on = settings.adaptiveFontSize;
    [fontSwitch addTarget:self action:@selector(ytnico_adaptiveStyleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [fontRow addArrangedSubview:fontSwitch];
    [box addArrangedSubview:fontRow];

    UILabel *scrollValue = YTNicoStyleLabel([NSString stringWithFormat:@"%.1f 秒", settings.scrollDuration], 13, UIFontWeightMedium, nil);
    scrollValue.textAlignment = NSTextAlignmentRight;
    UIStackView *scrollRow = [UIStackView new];
    scrollRow.axis = UILayoutConstraintAxisHorizontal;
    [scrollRow addArrangedSubview:YTNicoStyleLabel(@"スクロール時間", 14, UIFontWeightMedium, nil)];
    [scrollRow addArrangedSubview:scrollValue];
    [box addArrangedSubview:scrollRow];
    UISlider *scrollSlider = [UISlider new];
    scrollSlider.minimumValue = 2.5;
    scrollSlider.maximumValue = 10.0;
    scrollSlider.value = settings.scrollDuration;
    objc_setAssociatedObject(scrollSlider, kYTNicoStyleScrollLabelKey, scrollValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [scrollSlider addTarget:self action:@selector(ytnico_styleScrollChanged:) forControlEvents:UIControlEventValueChanged];
    [box addArrangedSubview:scrollSlider];

    UILabel *outlineValue = YTNicoStyleLabel([NSString stringWithFormat:@"%.1f", settings.outlineStrength], 13, UIFontWeightMedium, nil);
    outlineValue.textAlignment = NSTextAlignmentRight;
    UIStackView *outlineRow = [UIStackView new];
    outlineRow.axis = UILayoutConstraintAxisHorizontal;
    [outlineRow addArrangedSubview:YTNicoStyleLabel(@"黒縁の強さ", 14, UIFontWeightMedium, nil)];
    [outlineRow addArrangedSubview:outlineValue];
    [box addArrangedSubview:outlineRow];
    UISlider *outlineSlider = [UISlider new];
    outlineSlider.minimumValue = 0.0;
    outlineSlider.maximumValue = 8.0;
    outlineSlider.value = settings.outlineStrength;
    objc_setAssociatedObject(outlineSlider, kYTNicoStyleOutlineLabelKey, outlineValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [outlineSlider addTarget:self action:@selector(ytnico_styleOutlineChanged:) forControlEvents:UIControlEventValueChanged];
    [box addArrangedSubview:outlineSlider];

    [stack insertArrangedSubview:card atIndex:MIN((NSUInteger)5, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_styleModeSwitchChanged:(UISwitch *)sender {
    [SettingsManager.shared setNiconicoMode:sender.on];
    [[DebugInspector shared] important:@"niconicoMode=%d", sender.on];
}

%new
- (void)ytnico_adaptiveStyleSwitchChanged:(UISwitch *)sender {
    [SettingsManager.shared setAdaptiveFontSize:sender.on];
    [[DebugInspector shared] important:@"adaptiveFontSize=%d", sender.on];
}

%new
- (void)ytnico_styleScrollChanged:(UISlider *)slider {
    UILabel *label = objc_getAssociatedObject(slider, kYTNicoStyleScrollLabelKey);
    [SettingsManager.shared setScrollDuration:slider.value];
    label.text = [NSString stringWithFormat:@"%.1f 秒", slider.value];
}

%new
- (void)ytnico_styleOutlineChanged:(UISlider *)slider {
    UILabel *label = objc_getAssociatedObject(slider, kYTNicoStyleOutlineLabelKey);
    [SettingsManager.shared setOutlineStrength:slider.value];
    [SettingsManager.shared setEnableOutline:slider.value > 0.05];
    label.text = [NSString stringWithFormat:@"%.1f", slider.value];
}

%new
- (void)ytnico_applyStylePreset {
    [SettingsManager.shared applyNiconicoPreset];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"適用しました" message:@"ニコニコ風プリセットを適用しました。設定画面を開き直すと表示値も更新されます。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

%end

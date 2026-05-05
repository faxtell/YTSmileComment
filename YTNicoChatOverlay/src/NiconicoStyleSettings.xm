#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const NSInteger kYTNicoComingSoonTag = 940731;
static const void *kYTNicoLiveOnlyProcessedKey = &kYTNicoLiveOnlyProcessedKey;

static UILabel *YTNicoLiveOnlyLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}

static NSString *YTNicoLiveOnlyTextFromView(UIView *view, NSInteger depth) {
    if (!view || depth > 8) return @"";
    NSMutableString *out = [NSMutableString string];
    if ([view isKindOfClass:UILabel.class]) {
        NSString *t = ((UILabel *)view).text ?: @"";
        if (t.length) [out appendFormat:@" %@", t];
    }
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)view;
        NSString *t = [b titleForState:UIControlStateNormal] ?: @"";
        if (t.length) [out appendFormat:@" %@", t];
    }
    NSString *a = view.accessibilityLabel ?: @"";
    if (a.length) [out appendFormat:@" %@", a];
    for (UIView *sub in view.subviews) {
        NSString *child = YTNicoLiveOnlyTextFromView(sub, depth + 1);
        if (child.length) [out appendString:child];
    }
    return out;
}

static BOOL YTNicoLiveOnlyShouldDisableCard(UIView *view) {
    NSString *text = YTNicoLiveOnlyTextFromView(view, 0);
    if (text.length == 0) return NO;
    NSArray<NSString *> *needles = @[
        @"取得コメント数",
        @"通常コメント",
        @"チャットリプレイ",
        @"リプレイ",
        @"クリップボード",
        @"動画URL",
        @"URL/ID",
        @"ニコニコ風プリセット",
        @"スクロール時間",
        @"黒縁の強さ",
        @"動画サイズ連動フォント",
        @"ニコニコ風表示"
    ];
    for (NSString *needle in needles) {
        if ([text rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void YTNicoLiveOnlyDisableControls(UIView *view) {
    if (!view) return;
    view.userInteractionEnabled = NO;
    if ([view isKindOfClass:UIControl.class]) ((UIControl *)view).enabled = NO;
    if ([view isKindOfClass:UILabel.class]) ((UILabel *)view).textColor = UIColor.tertiaryLabelColor;
    for (UIView *sub in view.subviews) YTNicoLiveOnlyDisableControls(sub);
}

static void YTNicoLiveOnlyMarkComingSoon(UIView *card) {
    if (!card || [card viewWithTag:kYTNicoComingSoonTag]) return;
    card.alpha = 0.58;
    card.userInteractionEnabled = NO;
    if ([card respondsToSelector:@selector(layer)]) {
        card.layer.borderWidth = 1.0;
        card.layer.borderColor = UIColor.separatorColor.CGColor;
    }
    YTNicoLiveOnlyDisableControls(card);

    UILabel *badge = [UILabel new];
    badge.tag = kYTNicoComingSoonTag;
    badge.text = @"Coming Soon…";
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    badge.textColor = UIColor.secondaryLabelColor;
    badge.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.92];
    badge.layer.cornerRadius = 10.0;
    badge.layer.masksToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:10.0],
        [badge.widthAnchor constraintGreaterThanOrEqualToConstant:116.0],
        [badge.heightAnchor constraintEqualToConstant:24.0]
    ]];
}

static void YTNicoLiveOnlyAddNotice(UIStackView *stack) {
    if (!stack || [objc_getAssociatedObject(stack, kYTNicoLiveOnlyProcessedKey) boolValue]) return;
    objc_setAssociatedObject(stack, kYTNicoLiveOnlyProcessedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;

    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 6.0;
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

    [box addArrangedSubview:YTNicoLiveOnlyLabel(@"ライブチャット専用モード", 17, UIFontWeightSemibold, nil)];
    [box addArrangedSubview:YTNicoLiveOnlyLabel(@"現在は安定性優先のため、通常コメントとチャットリプレイ関連の設定は無効です。リアルタイムライブチャットのみ動作します。", 12.5, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [stack insertArrangedSubview:card atIndex:MIN((NSUInteger)1, stack.arrangedSubviews.count)];
}

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIStackView *stack = nil;
    @try { stack = [self valueForKey:@"stack"]; } @catch (__unused NSException *e) {}
    if (![stack isKindOfClass:UIStackView.class]) return;

    YTNicoLiveOnlyAddNotice(stack);
    for (UIView *card in stack.arrangedSubviews) {
        if (YTNicoLiveOnlyShouldDisableCard(card)) YTNicoLiveOnlyMarkComingSoon(card);
    }
    [[DebugInspector shared] log:@"live-only settings processed"];
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIStackView *stack = nil;
    @try { stack = [self valueForKey:@"stack"]; } @catch (__unused NSException *e) {}
    if (![stack isKindOfClass:UIStackView.class]) return;
    for (UIView *card in stack.arrangedSubviews) {
        if (YTNicoLiveOnlyShouldDisableCard(card)) YTNicoLiveOnlyMarkComingSoon(card);
    }
}

%end

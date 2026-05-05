#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoHubBuiltKey = &kYTNicoHubBuiltKey;

@interface YTNicoCategoryViewController : UIViewController
@property (nonatomic, copy) NSString *categoryTitle;
@property (nonatomic, copy) NSString *categoryKind;
@end

static UILabel *YTHubLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}

static UIButton *YTHubButton(NSString *title, NSString *subtitle) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(9, 12, 9, 12);
    NSString *full = subtitle.length ? [NSString stringWithFormat:@"%@\n%@", title, subtitle] : title;
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:full];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:[full rangeOfString:title]];
    if (subtitle.length) {
        NSRange r = [full rangeOfString:subtitle];
        [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular] range:r];
        [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:r];
    }
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    return button;
}

static UIView *YTHubCard(void) {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 15.0;
    card.layer.masksToBounds = YES;
    return card;
}

static UISwitch *YTHubSwitch(BOOL on, id target, SEL action) {
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

static void YTHubPin(UIStackView *box, UIView *card) {
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
}

@implementation YTNicoCategoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.categoryTitle ?: @"設定";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.layoutMargins = UIEdgeInsetsMake(14, 14, 24, 14);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor]
    ]];
    if ([self.categoryKind isEqualToString:@"display"]) [self buildDisplay:stack];
    else if ([self.categoryKind isEqualToString:@"live"]) [self buildLive:stack];
    else if ([self.categoryKind isEqualToString:@"tools"]) [self buildTools:stack];
    else [self buildComingSoon:stack];
}

- (void)addRowToStack:(UIStackView *)stack title:(NSString *)title subtitle:(NSString *)subtitle control:(UIView *)control enabled:(BOOL)enabled {
    UIView *card = YTHubCard();
    card.alpha = enabled ? 1.0 : 0.48;
    card.userInteractionEnabled = enabled;
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisHorizontal;
    box.alignment = UIStackViewAlignmentCenter;
    box.spacing = 12;
    box.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
    box.layoutMarginsRelativeArrangement = YES;
    YTHubPin(box, card);
    UIStackView *texts = [UIStackView new];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 3;
    [texts addArrangedSubview:YTHubLabel(title, 15, UIFontWeightSemibold, enabled ? nil : UIColor.secondaryLabelColor)];
    if (subtitle.length) [texts addArrangedSubview:YTHubLabel(subtitle, 12, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [box addArrangedSubview:texts];
    if (control) [box addArrangedSubview:control];
    [stack addArrangedSubview:card];
}

- (void)addComingSoonRow:(UIStackView *)stack title:(NSString *)title {
    [self addRowToStack:stack title:title subtitle:@"Coming Soon…" control:nil enabled:NO];
}

- (void)buildDisplay:(UIStackView *)stack {
    SettingsManager *s = SettingsManager.shared;
    [self addRowToStack:stack title:@"表示を有効化" subtitle:@"ライブチャットのオーバーレイ表示" control:YTHubSwitch(s.enabled, self, @selector(toggleEnabled:)) enabled:YES];
    [self addRowToStack:stack title:@"投稿者名" subtitle:@"ニコニコ風ではOFF推奨" control:YTHubSwitch(s.showAuthorName, self, @selector(toggleAuthor:)) enabled:YES];
    UILabel *fontValue = YTHubLabel([NSString stringWithFormat:@"%.0f", s.fontSize], 13, UIFontWeightMedium, UIColor.secondaryLabelColor);
    UISlider *font = [UISlider new];
    font.minimumValue = 10;
    font.maximumValue = 34;
    font.value = s.fontSize;
    objc_setAssociatedObject(font, @selector(fontChanged:), fontValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [font addTarget:self action:@selector(fontChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *fontBox = [UIStackView new];
    fontBox.axis = UILayoutConstraintAxisVertical;
    fontBox.spacing = 6;
    fontBox.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
    fontBox.layoutMarginsRelativeArrangement = YES;
    UIStackView *top = [UIStackView new]; top.axis = UILayoutConstraintAxisHorizontal;
    [top addArrangedSubview:YTHubLabel(@"文字サイズ", 15, UIFontWeightSemibold, nil)];
    [top addArrangedSubview:fontValue];
    [fontBox addArrangedSubview:top];
    [fontBox addArrangedSubview:font];
    UIView *fontCard = YTHubCard();
    YTHubPin(fontBox, fontCard);
    [stack addArrangedSubview:fontCard];
    [self addComingSoonRow:stack title:@"ニコニコ風プリセット"];
    [self addComingSoonRow:stack title:@"スクロール時間"];
    [self addComingSoonRow:stack title:@"黒縁の強さ"];
    [self addComingSoonRow:stack title:@"動画サイズ連動フォント"];
}

- (void)buildLive:(UIStackView *)stack {
    SettingsManager *s = SettingsManager.shared;
    [self addRowToStack:stack title:@"自動取得" subtitle:@"ライブ再生開始時にチャット取得を試します" control:YTHubSwitch(s.autoFetch, self, @selector(toggleAutoFetch:)) enabled:YES];
    [self addRowToStack:stack title:@"ライブチャット優先" subtitle:@"ライブ配信ではリアルタイムチャットだけを使います" control:YTHubSwitch(s.preferLiveChat, self, @selector(togglePreferLive:)) enabled:YES];
    [self addComingSoonRow:stack title:@"通常動画コメント"];
    [self addComingSoonRow:stack title:@"チャットリプレイ"];
    [self addComingSoonRow:stack title:@"取得コメント数"];
    [self addComingSoonRow:stack title:@"クリップボードURL取得"];
}

- (void)buildTools:(UIStackView *)stack {
    SettingsManager *s = SettingsManager.shared;
    [self addRowToStack:stack title:@"デバッグログ" subtitle:@"不具合調査用" control:YTHubSwitch(s.debugLogging, self, @selector(toggleDebug:)) enabled:YES];
    UIButton *copy = YTHubButton(@"ログをコピー", @"最近のログをクリップボードへ");
    [copy addTarget:self action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:copy];
    UIButton *clear = YTHubButton(@"ログを消去", @"ログバッファを空にします");
    [clear addTarget:self action:@selector(clearLogs) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:clear];
    [self addComingSoonRow:stack title:@"テストコメント"];
}

- (void)buildComingSoon:(UIStackView *)stack {
    UIView *card = YTHubCard();
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 6;
    box.layoutMargins = UIEdgeInsetsMake(18, 16, 18, 16);
    box.layoutMarginsRelativeArrangement = YES;
    YTHubPin(box, card);
    [box addArrangedSubview:YTHubLabel(@"Coming Soon…", 18, UIFontWeightSemibold, UIColor.secondaryLabelColor)];
    [box addArrangedSubview:YTHubLabel(@"ライブチャット専用モードが安定したら開放予定です。", 13, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [stack addArrangedSubview:card];
}

- (void)toggleEnabled:(UISwitch *)sw { [SettingsManager.shared setEnabled:sw.on]; }
- (void)toggleAuthor:(UISwitch *)sw { [SettingsManager.shared setShowAuthorName:sw.on]; }
- (void)toggleAutoFetch:(UISwitch *)sw { [SettingsManager.shared setAutoFetch:sw.on]; }
- (void)togglePreferLive:(UISwitch *)sw { [SettingsManager.shared setPreferLiveChat:sw.on]; }
- (void)toggleDebug:(UISwitch *)sw { [SettingsManager.shared setDebugLogging:sw.on]; }
- (void)fontChanged:(UISlider *)sl { UILabel *v = objc_getAssociatedObject(sl, @selector(fontChanged:)); v.text = [NSString stringWithFormat:@"%.0f", sl.value]; [SettingsManager.shared setFontSize:sl.value]; }
- (void)copyLogs { UIPasteboard.generalPasteboard.string = DebugInspector.shared.recentLogText ?: @""; }
- (void)clearLogs { [DebugInspector.shared clearLogs]; }
@end

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, kYTNicoHubBuiltKey) boolValue]) return;
    objc_setAssociatedObject(self, kYTNicoHubBuiltKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIStackView *stack = nil;
    @try { stack = [self valueForKey:@"stack"]; } @catch (__unused NSException *e) {}
    if (![stack isKindOfClass:UIStackView.class]) return;
    for (UIView *v in stack.arrangedSubviews.copy) {
        [stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    stack.spacing = 7;
    stack.layoutMargins = UIEdgeInsetsMake(8, 12, 8, 12);
    UIView *summary = YTHubCard();
    UIStackView *sumBox = [UIStackView new];
    sumBox.axis = UILayoutConstraintAxisVertical;
    sumBox.spacing = 2;
    sumBox.layoutMargins = UIEdgeInsetsMake(9, 12, 9, 12);
    sumBox.layoutMarginsRelativeArrangement = YES;
    YTHubPin(sumBox, summary);
    [sumBox addArrangedSubview:YTHubLabel(@"ライブチャット専用モード", 17, UIFontWeightSemibold, nil)];
    [sumBox addArrangedSubview:YTHubLabel(@"通常コメント/リプレイはComing Soon…として無効化中", 11, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [stack addArrangedSubview:summary];
    NSArray *items = @[
        @[@"表示", @"文字・投稿者名", @"display"],
        @[@"ライブチャット", @"自動取得・優先設定", @"live"],
        @[@"操作/デバッグ", @"ログ・調査用", @"tools"],
        @[@"その他", @"Coming Soon…", @"soon"]
    ];
    for (NSArray *item in items) {
        UIButton *b = YTHubButton(item[0], item[1]);
        b.accessibilityIdentifier = item[2];
        [b addTarget:self action:@selector(ytnico_openHubCategory:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
        [b.heightAnchor constraintGreaterThanOrEqualToConstant:49].active = YES;
    }
    UILabel *credit = YTHubLabel(@"クレジット", 12, UIFontWeightMedium, UIColor.secondaryLabelColor);
    credit.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:credit];
    UIButton *dev = YTHubButton(@"開発者: 🦈", @"x.com/sa_me_kun");
    [dev addTarget:self action:@selector(ytnico_openHubCredit) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:dev];
    [dev.heightAnchor constraintGreaterThanOrEqualToConstant:45].active = YES;
    [[DebugInspector shared] log:@"settings hub built"];
}

%new
- (void)ytnico_openHubCategory:(UIButton *)sender {
    YTNicoCategoryViewController *vc = [YTNicoCategoryViewController new];
    NSString *kind = sender.accessibilityIdentifier ?: @"soon";
    vc.categoryKind = kind;
    if ([kind isEqualToString:@"display"]) vc.categoryTitle = @"表示設定";
    else if ([kind isEqualToString:@"live"]) vc.categoryTitle = @"ライブチャット設定";
    else if ([kind isEqualToString:@"tools"]) vc.categoryTitle = @"操作/デバッグ";
    else vc.categoryTitle = @"Coming Soon…";
    [self.navigationController pushViewController:vc animated:YES];
}

%new
- (void)ytnico_openHubCredit {
    NSURL *url = [NSURL URLWithString:@"https://x.com/sa_me_kun"];
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) [app openURL:url options:@{} completionHandler:nil];
    else [app openURL:url];
}

%end

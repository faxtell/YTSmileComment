#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "YouTubeChatAdapter.h"
#import <objc/runtime.h>

static NSString * const kYTNicoSupportURL = @"https://twitter.com/messages/compose?recipient_id=1678480958671163392";
static NSString * const kYTNicoDeveloperURL = @"https://x.com/sa_me_kun";
static NSString * const kYTNicoPrefsDomain = @"com.example.yt-nico-chat-overlay";

@interface YTNicoSettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@end

@interface YTNicoCategoryViewController : UIViewController
@property (nonatomic, copy) NSString *categoryKind;
@property (nonatomic, copy) void (^displayTestHandler)(void);
@property (nonatomic, copy) void (^clipboardFetchHandler)(void);
@end

@implementation YTNicoSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"YTSmileComment";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    [self setupScroll];
    [self build];
}

- (void)setupScroll {
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];
    self.stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 14.0;
    self.stack.layoutMargins = UIEdgeInsetsMake(18, 18, 24, 18);
    self.stack.layoutMarginsRelativeArrangement = YES;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
    ]];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color align:(NSTextAlignment)align {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    label.textAlignment = align;
    return label;
}

- (UIView *)roundedCard:(UIColor *)color radius:(CGFloat)radius {
    UIView *v = [UIView new];
    v.backgroundColor = color ?: UIColor.secondarySystemBackgroundColor;
    v.layer.cornerRadius = radius;
    v.layer.masksToBounds = YES;
    return v;
}

- (void)build {
    [self.stack addArrangedSubview:[self heroHeader]];
    [self.stack addArrangedSubview:[self categoryGrid]];
    [self.stack addArrangedSubview:[self quickActions]];
    [self.stack addArrangedSubview:[self footer]];
}

- (UIView *)heroHeader {
    UIView *card = [self roundedCard:UIColor.secondarySystemBackgroundColor radius:22.0];
    UIStackView *box = [UIStackView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.axis = UILayoutConstraintAxisVertical;
    box.alignment = UIStackViewAlignmentCenter;
    box.spacing = 6;
    box.layoutMargins = UIEdgeInsetsMake(18, 18, 18, 18);
    box.layoutMarginsRelativeArrangement = YES;
    [card addSubview:box];

    [box addArrangedSubview:[self label:@"🦈" size:42 weight:UIFontWeightBold color:nil align:NSTextAlignmentCenter]];
    [box addArrangedSubview:[self label:@"YTSmileComment" size:24 weight:UIFontWeightBold color:nil align:NSTextAlignmentCenter]];
    [box addArrangedSubview:[self label:@"v0.9.1 (2026.05)" size:12.5 weight:UIFontWeightSemibold color:UIColor.secondaryLabelColor align:NSTextAlignmentCenter]];
    [box addArrangedSubview:[self label:@"YouTubeのコメントをニコニコ風に流します" size:14 weight:UIFontWeightMedium color:UIColor.secondaryLabelColor align:NSTextAlignmentCenter]];

    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    return card;
}

- (UIView *)categoryGrid {
    UIStackView *grid = [UIStackView new];
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 12;
    NSArray *rows = @[
        @[@{@"icon":@"💬", @"title":@"コメント表示", @"sub":@"量・速度・サイズ", @"kind":@"display"},
          @{@"icon":@"📡", @"title":@"コメント取得", @"sub":@"自動取得とUI検出", @"kind":@"fetch"}],
        @[@{@"icon":@"🎨", @"title":@"見た目", @"sub":@"縁取り・影・透明度", @"kind":@"appearance"},
          @{@"icon":@"🛠", @"title":@"サポート", @"sub":@"使い方・報告・情報", @"kind":@"support"}]
    ];
    for (NSArray *rowInfo in rows) {
        UIStackView *row = [UIStackView new];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSDictionary *info in rowInfo) [row addArrangedSubview:[self categoryButton:info]];
        [grid addArrangedSubview:row];
    }
    return grid;
}

- (UIButton *)categoryButton:(NSDictionary *)info {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 18;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentTop;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    button.accessibilityLabel = info[@"title"];
    NSString *title = [NSString stringWithFormat:@"%@\n%@\n%@", info[@"icon"], info[@"title"], info[@"sub"]];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    NSRange iconRange = [title rangeOfString:info[@"icon"]];
    NSRange titleRange = [title rangeOfString:info[@"title"]];
    NSRange subRange = [title rangeOfString:info[@"sub"]];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:26 weight:UIFontWeightBold] range:iconRange];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16 weight:UIFontWeightBold] range:titleRange];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:subRange];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:subRange];
    button.titleLabel.numberOfLines = 3;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:112].active = YES;
    objc_setAssociatedObject(button, @selector(categoryTapped:), info[@"kind"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    [button addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIView *)quickActions {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.distribution = UIStackViewDistributionFillEqually;
    [row addArrangedSubview:[self actionButton:@"🐞 不具合を報告" subtitle:@"開発者へ送信" action:@selector(openReport)]];
    [row addArrangedSubview:[self actionButton:@"🦈 開発者をフォロー" subtitle:@"最新情報を見る" action:@selector(openDeveloper)]];
    return row;
}

- (UIButton *)actionButton:(NSString *)title subtitle:(NSString *)subtitle action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 15;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    NSString *t = [NSString stringWithFormat:@"%@\n%@", title, subtitle];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:t];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:14.5 weight:UIFontWeightBold] range:[t rangeOfString:title]];
    NSRange sub = [t rangeOfString:subtitle];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:56].active = YES;
    return button;
}

- (UIView *)footer {
    UILabel *label = [self label:@"🦈 Thank you for using YTSmileComment\n楽しいコメント体験を。" size:12.5 weight:UIFontWeightMedium color:UIColor.tertiaryLabelColor align:NSTextAlignmentCenter];
    return label;
}

- (void)categoryTapped:(UIButton *)button {
    NSString *kind = objc_getAssociatedObject(button, @selector(categoryTapped:));
    YTNicoCategoryViewController *vc = [YTNicoCategoryViewController new];
    vc.categoryKind = kind ?: @"display";
    vc.displayTestHandler = self.displayTestHandler;
    vc.clipboardFetchHandler = self.clipboardFetchHandler;
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openURLString:(NSString *)urlString {
    if (urlString.length == 0) return;
    UIPasteboard.generalPasteboard.string = urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) [app openURL:url options:@{} completionHandler:nil];
    else [app openURL:url];
}
- (void)openReport { [self openURLString:kYTNicoSupportURL]; }
- (void)openDeveloper { [self openURLString:kYTNicoDeveloperURL]; }
@end

@implementation YTNicoCategoryViewController {
    UIScrollView *_scrollView;
    UIStackView *_stack;
    BOOL _showAdvanced;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _showAdvanced = NO;
    [self setupScroll];
    [self rebuild];
}

- (void)setupScroll {
    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_scrollView];
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 12;
    _stack.layoutMargins = UIEdgeInsetsMake(18, 18, 24, 18);
    _stack.layoutMarginsRelativeArrangement = YES;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor]
    ]];
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    return label;
}

- (UIView *)card {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.secondarySystemBackgroundColor;
    v.layer.cornerRadius = 16;
    v.layer.masksToBounds = YES;
    return v;
}

- (void)rebuild {
    for (UIView *v in _stack.arrangedSubviews.copy) { [_stack removeArrangedSubview:v]; [v removeFromSuperview]; }
    if ([self.categoryKind isEqualToString:@"fetch"]) [self buildFetch];
    else if ([self.categoryKind isEqualToString:@"appearance"]) [self buildAppearance];
    else if ([self.categoryKind isEqualToString:@"support"] || [self.categoryKind isEqualToString:@"tools"]) [self buildSupport];
    else [self buildDisplay];
}

- (void)addHeader:(NSString *)title subtitle:(NSString *)subtitle {
    self.title = title;
    [_stack addArrangedSubview:[self label:title size:26 weight:UIFontWeightBold color:nil]];
    [_stack addArrangedSubview:[self label:subtitle size:13.5 weight:UIFontWeightMedium color:UIColor.secondaryLabelColor]];
}

- (void)buildDisplay {
    SettingsManager *s = SettingsManager.shared;
    [self addHeader:@"💬 コメント表示" subtitle:@"コメントの量・速度・サイズを調整します。迷ったら標準のままでOKです。"];
    [self addSwitch:@"💬 コメント表示" subtitle:@"動画上のコメント表示をON/OFFします" value:s.enabled action:^(BOOL v){ [s setEnabled:v]; }];
    [self addSlider:@"🔠 文字サイズ" subtitle:@"コメント文字の大きさ" value:s.fontSize min:10 max:36 format:@"%.0f pt" action:^(float v){ [s setFontSize:v]; } percent:NO];
    [self addSlider:@"🚀 表示速度" subtitle:@"横方向に流れる速度" value:s.speed min:35 max:260 format:@"%.0f" action:^(float v){ [s setSpeed:v]; } percent:NO];
    [self addSlider:@"🌊 コメントの量" subtitle:@"高いほど画面いっぱいに流れます" value:s.commentDensity min:0.1 max:1.0 format:@"%.0f%%" action:^(float v){ [s setCommentDensity:v]; } percent:YES];
    [self addSlider:@"🧱 レーン数" subtitle:@"動画内で使う最大行数。自動レーン補正も働きます" value:s.maxLines min:1 max:24 format:@"%.0f 行" action:^(float v){ [s setMaxLines:(NSInteger)roundf(v)]; } percent:NO];
    [self addSwitch:@"📏 ニコニコ風レーン配置" subtitle:@"上から順に空きレーンを使います" value:s.niconicoMode action:^(BOOL v){ [s setNiconicoMode:v]; }];
}

- (void)buildFetch {
    SettingsManager *s = SettingsManager.shared;
    [self addHeader:@"📡 コメント取得" subtitle:@"通常コメント・ライブチャット・チャットリプレイを自動で取得します。内部の複雑な方式は自動で切り替えます。"];
    [self addSwitch:@"⚡ 自動取得" subtitle:@"動画を開いたときにコメント取得を試します" value:s.autoFetch action:^(BOOL v){ [s setAutoFetch:v]; }];
    [self addSwitch:@"📺 ライブ/リプレイ優先" subtitle:@"ライブチャットやチャットリプレイを優先して取得します" value:s.preferLiveChat action:^(BOOL v){ [s setPreferLiveChat:v]; }];
    [self addSwitch:@"⏱ リプレイを時刻同期" subtitle:@"再生時間に近いコメントを流します" value:s.syncReplayToTimestamp action:^(BOOL v){ [s setSyncReplayToTimestamp:v]; }];
    [self addSwitch:@"🛟 UI検出フォールバック" subtitle:@"取得できない場合、YouTube上に表示されたコメントを読み取って流します" value:s.uiScrapeFallback action:^(BOOL v){ [s setUiScrapeFallback:v]; }];
    [self addButton:@"📋 コピーした動画URL/IDから取得" subtitle:@"自動取得できない時に使います" action:^{ [self dismissThenRun:self.clipboardFetchHandler]; }];
    [self addComingSoon:@"🚧 詳細な取得方式" subtitle:@"新API / 旧API / deep search / JSON / HTML は自動で切り替えます"];
}

- (void)buildAppearance {
    SettingsManager *s = SettingsManager.shared;
    [self addHeader:@"🎨 見た目" subtitle:@"読みやすさとニコニコ感を調整します。@ユーザー名は表示しないように処理しています。"];
    [self addSlider:@"✨ 透明度" subtitle:@"コメントの濃さ。ニコニコ風では見やすさ優先です" value:s.opacity min:0.15 max:1.0 format:@"%.0f%%" action:^(float v){ [s setOpacity:v]; } percent:YES];
    [self addSwitch:@"🖋 縁取り" subtitle:@"白文字を読みやすくします" value:s.enableOutline action:^(BOOL v){ [s setEnableOutline:v]; }];
    [self addSlider:@"🖊 縁取りの強さ" subtitle:@"強いほどくっきりします" value:s.outlineStrength min:0 max:8 format:@"%.1f" action:^(float v){ [s setOutlineStrength:v]; } percent:NO];
    [self addSwitch:@"🌑 影" subtitle:@"背景が明るい動画でも見やすくします" value:s.enableShadow action:^(BOOL v){ [s setEnableShadow:v]; }];
    [self addSwitch:@"👤 投稿者名を表示" subtitle:@"@ユーザー名は表示せず、通常名のみ表示します" value:s.showAuthorName action:^(BOOL v){ [s setShowAuthorName:v]; }];
    [self addButton:@"🎯 ニコニコ風おすすめ設定に戻す" subtitle:@"見やすさ重視の標準プリセット" action:^{ [SettingsManager.shared applyNiconicoPreset]; [self showToast:@"おすすめ設定を適用しました"]; [self rebuild]; }];
}

- (void)buildSupport {
    SettingsManager *s = SettingsManager.shared;
    [self addHeader:@"🛠 サポート・情報" subtitle:@"困った時の確認や、開発者への連絡はこちらです。"];
    [self addButton:@"🧭 使い方を見る" subtitle:@"チュートリアルをもう一度表示" action:^{ [self showToast:@"設定画面からチュートリアルを開けます"]; }];
    [self addButton:@"🐞 不具合を報告" subtitle:@"開発者へDMで報告" action:^{ [self openURL:kYTNicoSupportURL]; }];
    [self addButton:@"🦈 開発者をフォロー" subtitle:@"最新情報を見る" action:^{ [self openURL:kYTNicoDeveloperURL]; }];
    [self addButton:@"🧪 表示テストコメントを流す" subtitle:@"Overlayが動いているか確認" action:^{ [self dismissThenRun:self.displayTestHandler]; }];
    [self addSwitch:@"🔍 詳細設定を表示" subtitle:@"デバッグ用の項目を表示します" value:_showAdvanced action:^(BOOL v){ self->_showAdvanced = v; [self rebuild]; }];
    if (_showAdvanced) {
        [self addSwitch:@"📜 デバッグログ" subtitle:@"通常はOFFがおすすめです" value:s.debugLogging action:^(BOOL v){ [s setDebugLogging:v]; }];
        [self addSwitch:@"🧪 テストコメント自動生成" subtitle:@"開発確認用。通常はOFF" value:s.mockMode action:^(BOOL v){ [s setMockMode:v]; }];
        [self addSlider:@"📦 最大取得数" subtitle:@"多すぎると重くなる場合があります" value:s.maxFetchComments min:100 max:3000 format:@"%.0f 件" action:^(float v){ [s setMaxFetchComments:(NSInteger)roundf(v)]; } percent:NO];
        [self addButton:@"🧹 設定を初期化" subtitle:@"標準設定に戻します" action:^{ [self resetSettings]; }];
    }
    [self addComingSoon:@"🚧 準備中" subtitle:@"今後のアップデートでさらに安定化・便利機能を追加予定です"];
}

- (void)addSwitch:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL)value action:(void (^)(BOOL))action {
    UIView *card = [self card];
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    row.layoutMarginsRelativeArrangement = YES;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [row.topAnchor constraintEqualToAnchor:card.topAnchor], [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]]];
    UIStackView *texts = [UIStackView new];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 3;
    [texts addArrangedSubview:[self label:title size:16 weight:UIFontWeightSemibold color:nil]];
    [texts addArrangedSubview:[self label:subtitle size:12 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor]];
    [row addArrangedSubview:texts];
    UISwitch *sw = [UISwitch new];
    sw.on = value;
    objc_setAssociatedObject(sw, @selector(addSwitch:subtitle:value:action:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:sw];
    [_stack addArrangedSubview:card];
}

- (void)switchChanged:(UISwitch *)sw {
    void (^action)(BOOL) = objc_getAssociatedObject(sw, @selector(addSwitch:subtitle:value:action:));
    if (action) action(sw.on);
    [self showToast:sw.on ? @"ONにしました" : @"OFFにしました"];
}

- (void)addSlider:(NSString *)title subtitle:(NSString *)subtitle value:(CGFloat)value min:(CGFloat)min max:(CGFloat)max format:(NSString *)format action:(void (^)(float))action percent:(BOOL)percent {
    UIView *card = [self card];
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 8;
    box.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[[box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [box.topAnchor constraintEqualToAnchor:card.topAnchor], [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]]];
    UILabel *titleLabel = [self label:title size:16 weight:UIFontWeightSemibold color:nil];
    UILabel *valueLabel = [self label:@"" size:14 weight:UIFontWeightMedium color:UIColor.secondaryLabelColor];
    valueLabel.textAlignment = NSTextAlignmentRight;
    UIStackView *top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    [top addArrangedSubview:titleLabel];
    [top addArrangedSubview:valueLabel];
    [box addArrangedSubview:top];
    [box addArrangedSubview:[self label:subtitle size:12 weight:UIFontWeightRegular color:UIColor.secondaryLabelColor]];
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    [box addArrangedSubview:progress];
    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    [box addArrangedSubview:slider];
    void (^updateLabel)(float) = ^(float v) { valueLabel.text = [NSString stringWithFormat:format, percent ? v * 100.0f : v]; progress.progress = (v - min) / MAX(0.001, (max - min)); };
    updateLabel(value);
    NSDictionary *payload = @{@"action":[action copy], @"update":[updateLabel copy]};
    objc_setAssociatedObject(slider, @selector(addSlider:subtitle:value:min:max:format:action:percent:), payload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:card];
}

- (void)sliderChanged:(UISlider *)slider {
    NSDictionary *payload = objc_getAssociatedObject(slider, @selector(addSlider:subtitle:value:min:max:format:action:percent:));
    void (^action)(float) = payload[@"action"];
    void (^update)(float) = payload[@"update"];
    if (update) update(slider.value);
    if (action) action(slider.value);
}

- (void)addButton:(NSString *)title subtitle:(NSString *)subtitle action:(void (^)(void))action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 15;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(13, 14, 13, 14);
    NSString *t = [NSString stringWithFormat:@"%@\n%@", title, subtitle];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:t];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16 weight:UIFontWeightBold] range:[t rangeOfString:title]];
    NSRange sub = [t rangeOfString:subtitle];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    objc_setAssociatedObject(button, @selector(addButton:subtitle:action:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:button];
}

- (void)buttonTapped:(UIButton *)button { void (^action)(void) = objc_getAssociatedObject(button, @selector(addButton:subtitle:action:)); if (action) action(); }

- (void)addComingSoon:(NSString *)title subtitle:(NSString *)subtitle {
    UIView *card = [self card];
    card.alpha = 0.58;
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 3;
    box.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [box addArrangedSubview:[self label:title size:16 weight:UIFontWeightBold color:UIColor.secondaryLabelColor]];
    [box addArrangedSubview:[self label:subtitle size:12 weight:UIFontWeightRegular color:UIColor.tertiaryLabelColor]];
    [NSLayoutConstraint activateConstraints:@[[box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor], [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor], [box.topAnchor constraintEqualToAnchor:card.topAnchor], [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]]];
    [_stack addArrangedSubview:card];
}

- (void)dismissThenRun:(dispatch_block_t)block { [self dismissViewControllerAnimated:YES completion:^{ if (block) block(); }]; }

- (void)openURL:(NSString *)urlString {
    UIPasteboard.generalPasteboard.string = urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) [app openURL:url options:@{} completionHandler:nil];
    else [app openURL:url];
}

- (void)resetSettings {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kYTNicoPrefsDomain] ?: NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[@"fontSize", @"opacity", @"speed", @"maxLines", @"showAuthorName", @"enableShadow", @"enableOutline", @"outlineStrength", @"niconicoMode", @"adaptiveFontSize", @"scrollDuration", @"mockMode", @"debugLogging", @"commentDensity", @"longevity", @"syncReplayToTimestamp", @"preferLiveChat", @"autoFetch", @"uiScrapeFallback", @"maxFetchComments"];
    for (NSString *k in keys) [d removeObjectForKey:k];
    [d synchronize];
    [SettingsManager.shared applyNiconicoPreset];
    [self showToast:@"設定を初期化しました"];
    [self rebuild];
}

- (void)showToast:(NSString *)text {
    if (text.length == 0) return;
    UILabel *toast = [UILabel new];
    toast.text = text;
    toast.textColor = UIColor.whiteColor;
    toast.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    toast.layer.cornerRadius = 14;
    toast.layer.masksToBounds = YES;
    toast.alpha = 0;
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[[toast.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor], [toast.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18], [toast.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor constant:-48], [toast.heightAnchor constraintGreaterThanOrEqualToConstant:34]]];
    [UIView animateWithDuration:0.18 animations:^{ toast.alpha = 1; } completion:^(__unused BOOL finished) { [UIView animateWithDuration:0.25 delay:1.0 options:0 animations:^{ toast.alpha = 0; } completion:^(__unused BOOL f){ [toast removeFromSuperview]; }]; }];
}
@end

#import "YTNicoSettingsViewController.h"
#import "SettingsManager.h"
#import "YouTubeChatAdapter.h"

@interface YTNicoSettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation YTNicoSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ニコニコ風コメント設定";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    self.stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 14.0;
    self.stack.layoutMargins = UIEdgeInsetsMake(20, 20, 28, 20);
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

    [self build];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    return label;
}

- (UIView *)card {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.secondarySystemBackgroundColor;
    v.layer.cornerRadius = 16.0;
    v.layer.masksToBounds = YES;
    return v;
}

- (void)build {
    SettingsManager *s = SettingsManager.shared;
    [self.stack addArrangedSubview:[self label:@"コメントの流れ方や見た目を調整できます。おすすめは密度70〜85%、長持ち70〜90%です。" size:14 weight:UIFontWeightRegular]];

    [self addSwitch:@"コメント表示" subtitle:@"動画上のコメント表示をON/OFFします" value:s.enabled action:^(BOOL v){ [s setEnabled:v]; }];
    [self addSwitch:@"プレミア/ライブチャットを優先" subtitle:@"通常コメントよりチャット/リプレイを優先して取得します" value:s.preferLiveChat action:^(BOOL v){ [s setPreferLiveChat:v]; }];
    [self addSwitch:@"リプレイを時刻同期" subtitle:@"チャットリプレイのtimestampUsecを使って、動画の進行に近い順序で流します" value:s.syncReplayToTimestamp action:^(BOOL v){ [s setSyncReplayToTimestamp:v]; }];

    [self addSlider:@"コメント密度" subtitle:@"高いほど画面いっぱいに流れます" value:s.commentDensity min:0.1 max:1.0 format:@"%.0f%%" action:^(float v){ [s setCommentDensity:v]; } percent:YES];
    [self addSlider:@"長持ち" subtitle:@"高いほどコメントをゆっくり消費します" value:s.longevity min:0.1 max:1.0 format:@"%.0f%%" action:^(float v){ [s setLongevity:v]; } percent:YES];
    [self addSlider:@"文字サイズ" subtitle:@"コメント文字の大きさ" value:s.fontSize min:10 max:36 format:@"%.0f pt" action:^(float v){ [s setFontSize:v]; } percent:NO];
    [self addSlider:@"流れる速度" subtitle:@"横方向に流れる速度" value:s.speed min:35 max:260 format:@"%.0f" action:^(float v){ [s setSpeed:v]; } percent:NO];
    [self addSlider:@"表示行数" subtitle:@"動画内に使う最大レーン数" value:s.maxLines min:1 max:20 format:@"%.0f 行" action:^(float v){ [s setMaxLines:(NSInteger)roundf(v)]; } percent:NO];
    [self addSlider:@"透明度" subtitle:@"コメントの濃さ" value:s.opacity min:0.15 max:1.0 format:@"%.0f%%" action:^(float v){ [s setOpacity:v]; } percent:YES];

    [self addSwitch:@"投稿者名を表示" subtitle:@"コメントの前に名前を出します" value:s.showAuthorName action:^(BOOL v){ [s setShowAuthorName:v]; }];
    [self addSwitch:@"影を付ける" subtitle:@"白文字を見やすくします" value:s.enableShadow action:^(BOOL v){ [s setEnableShadow:v]; }];
    [self addSwitch:@"アウトライン" subtitle:@"文字に縁取りを付けます" value:s.enableOutline action:^(BOOL v){ [s setEnableOutline:v]; }];
    [self addSwitch:@"テストコメント" subtitle:@"動作確認用コメントを自動で流します" value:s.mockMode action:^(BOOL v){ [s setMockMode:v]; }];

    [self addButton:@"表示テストコメントを流す" action:^{ if (self.displayTestHandler) self.displayTestHandler(); }];
    [self addButton:@"クリップボードの動画URL/IDから取得" action:^{ if (self.clipboardFetchHandler) self.clipboardFetchHandler(); }];
}

- (void)addSwitch:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL)value action:(void (^)(BOOL))action {
    UIView *card = [self card];
    UIStackView *row = [[UIStackView alloc] init];
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
    [texts addArrangedSubview:[self label:title size:16 weight:UIFontWeightSemibold]];
    UILabel *sub = [self label:subtitle size:12 weight:UIFontWeightRegular];
    sub.textColor = UIColor.secondaryLabelColor;
    [texts addArrangedSubview:sub];
    [row addArrangedSubview:texts];

    UISwitch *sw = [UISwitch new];
    sw.on = value;
    objc_setAssociatedObject(sw, @selector(addSwitch:subtitle:value:action:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addArrangedSubview:sw];
    [self.stack addArrangedSubview:card];
}

- (void)switchChanged:(UISwitch *)sw {
    void (^action)(BOOL) = objc_getAssociatedObject(sw, @selector(addSwitch:subtitle:value:action:));
    if (action) action(sw.on);
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

    UILabel *titleLabel = [self label:title size:16 weight:UIFontWeightSemibold];
    UILabel *valueLabel = [self label:@"" size:14 weight:UIFontWeightMedium];
    valueLabel.textAlignment = NSTextAlignmentRight;
    UIStackView *top = [UIStackView new];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    [top addArrangedSubview:titleLabel];
    [top addArrangedSubview:valueLabel];
    [box addArrangedSubview:top];

    UILabel *sub = [self label:subtitle size:12 weight:UIFontWeightRegular];
    sub.textColor = UIColor.secondaryLabelColor;
    [box addArrangedSubview:sub];

    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.progress = (value - min) / (max - min);
    [box addArrangedSubview:progress];

    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    [box addArrangedSubview:slider];

    void (^updateLabel)(float) = ^(float v) {
        float shown = percent ? v * 100.0f : v;
        valueLabel.text = [NSString stringWithFormat:format, shown];
        progress.progress = (v - min) / (max - min);
    };
    updateLabel(value);

    NSDictionary *payload = @{@"action":[action copy], @"update":[updateLabel copy]};
    objc_setAssociatedObject(slider, @selector(addSlider:subtitle:value:min:max:format:action:percent:), payload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.stack addArrangedSubview:card];
}

- (void)sliderChanged:(UISlider *)slider {
    NSDictionary *payload = objc_getAssociatedObject(slider, @selector(addSlider:subtitle:value:min:max:format:action:percent:));
    void (^action)(float) = payload[@"action"];
    void (^update)(float) = payload[@"update"];
    if (update) update(slider.value);
    if (action) action(slider.value);
}

- (void)addButton:(NSString *)title action:(void (^)(void))action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 14;
    button.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
    objc_setAssociatedObject(button, @selector(addButton:action:), action, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:button];
}

- (void)buttonTapped:(UIButton *)button {
    void (^action)(void) = objc_getAssociatedObject(button, @selector(addButton:action:));
    if (action) action();
}

@end

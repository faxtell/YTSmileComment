#import <UIKit/UIKit.h>

static NSString * const kYTNicoTutorialDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoTutorialShownKey = @"tutorial.shown.v1";
static NSString * const kYTNicoLicenseReadyKey = @"ready.v1";
static NSString * const kYTNicoSuppressTutorialUntilKey = @"tutorial.suppress.until";

@interface YTNicoTutorialViewController : UIViewController
+ (BOOL)shouldShowTutorial;
+ (void)markTutorialShown;
@end

@implementation YTNicoTutorialViewController {
    UIScrollView *_scrollView;
    UIStackView *_stack;
    UIPageControl *_page;
    NSArray<NSDictionary *> *_pages;
    NSInteger _index;
    BOOL _licenseVerifiedInSession;
    UILabel *_icon;
    UIView *_iconBackground;
    UILabel *_titleLabel;
    UILabel *_bodyLabel;
    UIStackView *_tipsStack;
    UIStackView *_actionStack;
    UIButton *_followButton;
    UIButton *_requestButton;
    UITextField *_licenseField;
    UIButton *_licenseVisibilityButton;
    UILabel *_licenseHintLabel;
    UILabel *_statusLabel;
    UIButton *_backButton;
    UIButton *_nextButton;
    UIButton *_skipButton;
}

+ (NSUserDefaults *)defaults {
    return [[NSUserDefaults alloc] initWithSuiteName:kYTNicoTutorialDomain] ?: NSUserDefaults.standardUserDefaults;
}

+ (BOOL)shouldShowTutorial {
    return ![[self defaults] boolForKey:kYTNicoTutorialShownKey];
}

+ (void)markTutorialShown {
    NSUserDefaults *d = [self defaults];
    [d setBool:YES forKey:kYTNicoTutorialShownKey];
    [d synchronize];
}

static BOOL YTNicoLicenseReady(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kYTNicoTutorialDomain] ?: NSUserDefaults.standardUserDefaults;
    return [d boolForKey:kYTNicoLicenseReadyKey];
}

static BOOL YTNicoTutorialCheckLicense(NSString *s) {
    NSString *trim = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSData *a = [trim dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSData *b = [[NSData alloc] initWithBase64EncodedString:@"8J+NjA==" options:0] ?: [NSData data];
    return [a isEqualToData:b];
}

static void YTNicoTutorialSetLicenseReady(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kYTNicoTutorialDomain] ?: NSUserDefaults.standardUserDefaults;
    [d setBool:YES forKey:kYTNicoLicenseReadyKey];
    [d setBool:YES forKey:@"enabled"];
    [d synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.example.ytnico.settings.changed" object:nil];
}

static void YTNicoSuppressTutorialForSeconds(NSTimeInterval seconds) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kYTNicoTutorialDomain] ?: NSUserDefaults.standardUserDefaults;
    [d setDouble:[NSDate.date timeIntervalSince1970] + seconds forKey:kYTNicoSuppressTutorialUntilKey];
    [d synchronize];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    _index = 0;
    _licenseVerifiedInSession = YTNicoLicenseReady();
    _pages = @[
        @{@"kind":@"intro", @"accent":UIColor.systemRedColor, @"icon":@"📺", @"title":@"ようこそ", @"body":@"YouTubeのライブチャットを、動画上にニコニコ風で流せます。\n\n現在は安定性優先のライブチャット専用モードです。", @"tips":@[@"ライブ配信のリアルタイムチャットに対応", @"通常コメントとリプレイは Coming Soon…", @"動画の上にコメントが流れます"]},
        @{@"kind":@"usage", @"accent":UIColor.systemBlueColor, @"icon":@"💬", @"title":@"使い方", @"body":@"ライブ配信を開くと、リアルタイムチャットの取得を試します。\n\n自動取得できない場合は、手動取得も使えます。", @"tips":@[@"ライブ配信を開く", @"吹き出しボタンでON/OFF", @"自動取得できない時は共有ボタンからリンクをコピー", @"その後、吹き出しボタンから手動でコメント取得"]},
        @{@"kind":@"settings", @"accent":UIColor.systemPurpleColor, @"icon":@"🎨", @"title":@"設定", @"body":@"設定は2列のカテゴリに整理されています。\n\n必要な項目だけをすぐに見つけられるようにしています。", @"tips":@[@"🎨 表示 = 文字や投稿者名", @"📡 ライブチャット = 取得まわり", @"🛠️ 操作/デバッグ = ログ確認", @"🚧 Coming Soon… = 今後追加予定"]},
        @{@"kind":@"request", @"accent":UIColor.systemTealColor, @"icon":@"🦈", @"title":@"ライセンスの受け取り", @"body":@"利用にはライセンスが必要です。\n\n下の手順で申請してください。", @"tips":@[@"開発者をフォロー", @"ライセンスを申請", @"受け取ったキーを次のページで入力"]},
        @{@"kind":@"license", @"accent":UIColor.systemOrangeColor, @"icon":@"🔑", @"title":@"ライセンス認証", @"body":@"受け取ったライセンスキーを入力してください。\n\n認証が完了するまで、このページから先には進めません。", @"tips":@[@"キー入力後、ライセンス認証を押してください", @"まだ持っていない場合は戻って申請してください"]},
        @{@"kind":@"start", @"accent":UIColor.systemGreenColor, @"icon":@"🚀", @"title":@"さぁ、はじめよう", @"body":@"準備が完了しました。\n\nこのボタンを押すと機能が有効になり、ライブチャット表示を利用できます。", @"tips":@[@"✅ ライセンス認証済み", @"✅ ライブチャット専用モード", @"✅ 自動取得ON", @"✅ 困った時は操作/デバッグへ"]}
    ];

    _skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_skipButton setTitle:@"あとで" forState:UIControlStateNormal];
    _skipButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_skipButton addTarget:self action:@selector(skipTutorial) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_skipButton];

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_backButton setTitle:@"戻る" forState:UIControlStateNormal];
    _backButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_backButton];

    _scrollView = [UIScrollView new];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scrollView];

    _stack = [UIStackView new];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.alignment = UIStackViewAlignmentCenter;
    _stack.spacing = 14.0;
    _stack.layoutMargins = UIEdgeInsetsMake(18, 24, 22, 24);
    _stack.layoutMarginsRelativeArrangement = YES;
    [_scrollView addSubview:_stack];

    _iconBackground = [UIView new];
    _iconBackground.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBackground.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _iconBackground.layer.cornerRadius = 34.0;
    _iconBackground.layer.masksToBounds = YES;
    [_stack addArrangedSubview:_iconBackground];
    [_iconBackground.widthAnchor constraintEqualToConstant:132].active = YES;
    [_iconBackground.heightAnchor constraintEqualToConstant:132].active = YES;

    _icon = [UILabel new];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.font = [UIFont systemFontOfSize:64 weight:UIFontWeightRegular];
    _icon.textAlignment = NSTextAlignmentCenter;
    [_iconBackground addSubview:_icon];
    [NSLayoutConstraint activateConstraints:@[
        [_icon.centerXAnchor constraintEqualToAnchor:_iconBackground.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBackground.centerYAnchor]
    ]];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_titleLabel];
    [_titleLabel.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-16].active = YES;

    _bodyLabel = [UILabel new];
    _bodyLabel.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightRegular];
    _bodyLabel.textColor = UIColor.secondaryLabelColor;
    _bodyLabel.textAlignment = NSTextAlignmentCenter;
    _bodyLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_bodyLabel];
    [_bodyLabel.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-16].active = YES;

    _statusLabel = [UILabel new];
    _statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _statusLabel.textColor = UIColor.systemGreenColor;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_statusLabel];
    [_statusLabel.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-24].active = YES;

    _tipsStack = [UIStackView new];
    _tipsStack.axis = UILayoutConstraintAxisVertical;
    _tipsStack.spacing = 8.0;
    _tipsStack.alignment = UIStackViewAlignmentFill;
    [_stack addArrangedSubview:_tipsStack];
    [_tipsStack.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-8].active = YES;

    _actionStack = [UIStackView new];
    _actionStack.axis = UILayoutConstraintAxisVertical;
    _actionStack.alignment = UIStackViewAlignmentCenter;
    _actionStack.spacing = 10.0;
    [_stack addArrangedSubview:_actionStack];
    [_actionStack.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-8].active = YES;

    _followButton = [self actionButtonWithTitle:@"🦈 開発者をフォロー" subtitle:nil];
    [_followButton addTarget:self action:@selector(openDeveloper) forControlEvents:UIControlEventTouchUpInside];
    [_actionStack addArrangedSubview:_followButton];

    _requestButton = [self actionButtonWithTitle:@"🔑 ライセンスを申請" subtitle:nil];
    [_requestButton addTarget:self action:@selector(openLicenseRequest) forControlEvents:UIControlEventTouchUpInside];
    [_actionStack addArrangedSubview:_requestButton];

    _licenseField = [UITextField new];
    _licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseField.placeholder = @"ライセンスキー";
    _licenseField.textAlignment = NSTextAlignmentCenter;
    _licenseField.borderStyle = UITextBorderStyleRoundedRect;
    _licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    _licenseField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _licenseField.secureTextEntry = YES;
    _licenseVisibilityButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_licenseVisibilityButton setTitle:@"表示" forState:UIControlStateNormal];
    [_licenseVisibilityButton addTarget:self action:@selector(toggleLicenseVisibility) forControlEvents:UIControlEventTouchUpInside];
    _licenseField.rightView = _licenseVisibilityButton;
    _licenseField.rightViewMode = UITextFieldViewModeAlways;
    [_actionStack addArrangedSubview:_licenseField];
    [_licenseField.widthAnchor constraintEqualToConstant:250].active = YES;
    [_licenseField.heightAnchor constraintEqualToConstant:44].active = YES;

    _licenseHintLabel = [UILabel new];
    _licenseHintLabel.text = @"未認証の場合、このページから先には進めません。";
    _licenseHintLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular];
    _licenseHintLabel.textColor = UIColor.secondaryLabelColor;
    _licenseHintLabel.textAlignment = NSTextAlignmentCenter;
    _licenseHintLabel.numberOfLines = 0;
    [_actionStack addArrangedSubview:_licenseHintLabel];
    [_licenseHintLabel.widthAnchor constraintEqualToAnchor:_actionStack.widthAnchor constant:-20].active = YES;

    _page = [UIPageControl new];
    _page.translatesAutoresizingMaskIntoConstraints = NO;
    _page.numberOfPages = _pages.count;
    [self.view addSubview:_page];

    _nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _nextButton.translatesAutoresizingMaskIntoConstraints = NO;
    _nextButton.backgroundColor = UIColor.systemRedColor;
    _nextButton.layer.cornerRadius = 15.0;
    _nextButton.layer.masksToBounds = YES;
    [_nextButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _nextButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [_nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_nextButton];

    [NSLayoutConstraint activateConstraints:@[
        [_backButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_backButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [_skipButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [_skipButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:_skipButton.bottomAnchor constant:6],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_page.topAnchor constant:-8],
        [_stack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor],
        [_page.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_page.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-12],
        [_nextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_nextButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_nextButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18],
        [_nextButton.heightAnchor constraintEqualToConstant:52]
    ]];
    [self renderPage];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 16.0;
    button.layer.masksToBounds = YES;
    button.contentEdgeInsets = UIEdgeInsetsMake(12, 16, 12, 16);
    button.titleLabel.numberOfLines = subtitle.length ? 2 : 1;
    NSString *full = subtitle.length ? [NSString stringWithFormat:@"%@\n%@", title, subtitle] : title;
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:full];
    [a addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] range:[full rangeOfString:title]];
    if (subtitle.length) {
        NSRange sub = [full rangeOfString:subtitle];
        [a addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
        [a addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    }
    [button setAttributedTitle:a forState:UIControlStateNormal];
    [button.widthAnchor constraintEqualToConstant:260].active = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    return button;
}

- (UIView *)tipCard:(NSString *)text accent:(UIColor *)accent {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 13.0;
    card.layer.masksToBounds = YES;
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [accent colorWithAlphaComponent:0.65];
    [card addSubview:bar];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    label.text = text ?: @"";
    [card addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [bar.topAnchor constraintEqualToAnchor:card.topAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [bar.widthAnchor constraintEqualToConstant:4.0],
        [label.leadingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:10.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10.0],
        [label.topAnchor constraintEqualToAnchor:card.topAnchor constant:9.0],
        [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-9.0]
    ]];
    return card;
}

- (void)fillTips:(NSArray<NSString *> *)tips accent:(UIColor *)accent {
    for (UIView *v in _tipsStack.arrangedSubviews.copy) {
        [_tipsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSString *tip in tips) [_tipsStack addArrangedSubview:[self tipCard:tip accent:accent ?: UIColor.systemRedColor]];
}

- (NSString *)currentKind {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    return p[@"kind"] ?: @"";
}

- (void)renderPage {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    NSString *kind = p[@"kind"] ?: @"";
    UIColor *accent = p[@"accent"] ?: UIColor.systemRedColor;
    BOOL requestPage = [kind isEqualToString:@"request"];
    BOOL licensePage = [kind isEqualToString:@"license"];
    BOOL startPage = [kind isEqualToString:@"start"];

    _icon.text = p[@"icon"];
    _iconBackground.backgroundColor = [accent colorWithAlphaComponent:0.14];
    _titleLabel.text = p[@"title"];
    _bodyLabel.text = p[@"body"];
    [self fillTips:p[@"tips"] ?: @[] accent:accent];
    _page.currentPage = _index;
    _nextButton.backgroundColor = accent;

    _followButton.hidden = !requestPage;
    _requestButton.hidden = !requestPage;
    _licenseField.hidden = !licensePage;
    _licenseHintLabel.hidden = !licensePage;
    _actionStack.hidden = !(requestPage || licensePage);

    BOOL licensed = YTNicoLicenseReady() || _licenseVerifiedInSession;
    _skipButton.hidden = !licensed;
    _backButton.hidden = (_index == 0);
    _statusLabel.hidden = _statusLabel.text.length == 0;

    if (licensePage) [_nextButton setTitle:@"ライセンス認証" forState:UIControlStateNormal];
    else if (startPage) [_nextButton setTitle:@"さぁ、はじめよう" forState:UIControlStateNormal];
    else [_nextButton setTitle:@"次へ" forState:UIControlStateNormal];
    [_scrollView setContentOffset:CGPointZero animated:NO];
}

- (void)nextTapped {
    NSString *kind = [self currentKind];
    if ([kind isEqualToString:@"license"]) {
        if (YTNicoTutorialCheckLicense(_licenseField.text ?: @"")) {
            _licenseVerifiedInSession = YES;
            _statusLabel.text = @"✅ 認証できました";
            _licenseHintLabel.text = @"認証が完了しました。次のページへ進みます。";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self goNextWithAnimation];
            });
        } else {
            [self showLicenseRequiredAlert];
        }
        return;
    }
    if ([kind isEqualToString:@"start"]) {
        if (_licenseVerifiedInSession || YTNicoLicenseReady()) {
            YTNicoTutorialSetLicenseReady();
            [self closeTutorial];
        } else {
            [self showLicenseRequiredAlert];
            _index = MAX(0, (NSInteger)_pages.count - 2);
            [self renderPage];
        }
        return;
    }
    NSInteger next = _index + 1;
    if (next < (NSInteger)_pages.count) {
        NSDictionary *nextPage = _pages[next];
        if ([nextPage[@"kind"] isEqualToString:@"start"] && !(_licenseVerifiedInSession || YTNicoLicenseReady())) {
            [self showLicenseRequiredAlert];
            return;
        }
    }
    [self goNextWithAnimation];
}

- (void)goNextWithAnimation {
    if (_index >= (NSInteger)_pages.count - 1) return;
    _index++;
    _statusLabel.text = @"";
    [UIView transitionWithView:self.view duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self renderPage];
    } completion:nil];
}

- (void)backTapped {
    if (_index <= 0) return;
    _index--;
    _statusLabel.text = @"";
    [UIView transitionWithView:self.view duration:0.18 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self renderPage];
    } completion:nil];
}

- (void)toggleLicenseVisibility {
    _licenseField.secureTextEntry = !_licenseField.secureTextEntry;
    [_licenseVisibilityButton setTitle:(_licenseField.secureTextEntry ? @"表示" : @"隠す") forState:UIControlStateNormal];
}

- (void)showLicenseRequiredAlert {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"ライセンスが必要です" message:@"ライセンスキーを入力してください。まだ持っていない場合は、前のページから申請できます。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openURLString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) [app openURL:url options:@{} completionHandler:nil];
    else [app openURL:url];
}

- (void)openDeveloper {
    YTNicoSuppressTutorialForSeconds(45.0);
    _statusLabel.text = @"戻ったら、ライセンスを申請してください。";
    [self openURLString:@"https://x.com/sa_me_kun"];
}

- (void)openLicenseRequest {
    YTNicoSuppressTutorialForSeconds(60.0);
    _statusLabel.text = @"申請後、受け取ったキーを次のページで入力してください。";
    [self openURLString:@"https://twitter.com/messages/compose?recipient_id=1678480958671163392"];
}

- (void)skipTutorial {
    if (!YTNicoLicenseReady()) return;
    [YTNicoTutorialViewController markTutorialShown];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)closeTutorial {
    [YTNicoTutorialViewController markTutorialShown];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

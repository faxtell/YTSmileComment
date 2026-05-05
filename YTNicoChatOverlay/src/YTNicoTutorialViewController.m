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
    UIPageControl *_pageControl;
    NSArray<NSDictionary *> *_pages;
    NSInteger _index;
    BOOL _licenseVerifiedInSession;

    UIView *_iconBackground;
    UILabel *_iconLabel;
    UILabel *_titleLabel;
    UILabel *_bodyLabel;
    UIStackView *_tipsStack;
    UIStackView *_requestStack;
    UILabel *_statusLabel;

    UIButton *_followButton;
    UIButton *_requestButton;
    UIButton *_backButton;
    UIButton *_skipButton;
    UIButton *_nextButton;
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

static BOOL YTNicoTutorialCheckLicense(NSString *input) {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSData *given = [trimmed dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSData *expected = [[NSData alloc] initWithBase64EncodedString:@"8J+NjA==" options:0] ?: [NSData data];
    return [given isEqualToData:expected];
}

static void YTNicoTutorialSetReady(void) {
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
        @{@"kind":@"request", @"accent":UIColor.systemTealColor, @"icon":@"🦈", @"title":@"ライセンスを受け取る", @"body":@"ライセンスを持っていない場合は、下の2つの手順を進めてください。", @"tips":@[]},
        @{@"kind":@"license", @"accent":UIColor.systemOrangeColor, @"icon":@"🔑", @"title":@"ライセンス認証", @"body":@"下部の「認証する」ボタンを押して、受け取ったライセンスキーを入力してください。\n\n認証が完了するまで、このページから先には進めません。", @"tips":@[@"キーを持っていない場合は、戻るボタンで前のページへ", @"認証に成功すると最後のページへ進めます"]},
        @{@"kind":@"start", @"accent":UIColor.systemGreenColor, @"icon":@"🚀", @"title":@"さぁ、はじめよう", @"body":@"準備が完了しました。\n\nこのボタンを押すと機能が有効になり、ライブチャット表示を利用できます。", @"tips":@[@"✅ ライセンス認証済み", @"✅ ライブチャット専用モード", @"✅ 自動取得ON", @"✅ 困った時は操作/デバッグへ"]}
    ];

    [self buildBaseLayout];
    [self renderPage];
}

- (void)buildBaseLayout {
    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_backButton setTitle:@"戻る" forState:UIControlStateNormal];
    _backButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_backButton];

    _skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_skipButton setTitle:@"あとで" forState:UIControlStateNormal];
    _skipButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_skipButton addTarget:self action:@selector(skipTutorial) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_skipButton];

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
    _iconBackground.layer.cornerRadius = 34.0;
    _iconBackground.layer.masksToBounds = YES;
    [_stack addArrangedSubview:_iconBackground];
    [_iconBackground.widthAnchor constraintEqualToConstant:132].active = YES;
    [_iconBackground.heightAnchor constraintEqualToConstant:132].active = YES;

    _iconLabel = [UILabel new];
    _iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _iconLabel.font = [UIFont systemFontOfSize:64 weight:UIFontWeightRegular];
    _iconLabel.textAlignment = NSTextAlignmentCenter;
    [_iconBackground addSubview:_iconLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_iconLabel.centerXAnchor constraintEqualToAnchor:_iconBackground.centerXAnchor],
        [_iconLabel.centerYAnchor constraintEqualToAnchor:_iconBackground.centerYAnchor]
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
    _tipsStack.alignment = UIStackViewAlignmentFill;
    _tipsStack.spacing = 8.0;
    [_stack addArrangedSubview:_tipsStack];
    [_tipsStack.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-8].active = YES;

    _requestStack = [UIStackView new];
    _requestStack.axis = UILayoutConstraintAxisVertical;
    _requestStack.alignment = UIStackViewAlignmentFill;
    _requestStack.spacing = 14.0;
    [_stack addArrangedSubview:_requestStack];
    [_requestStack.widthAnchor constraintEqualToAnchor:_stack.widthAnchor constant:-8].active = YES;
    [self buildRequestControls];

    _pageControl = [UIPageControl new];
    _pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    _pageControl.numberOfPages = _pages.count;
    [self.view addSubview:_pageControl];

    _nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _nextButton.translatesAutoresizingMaskIntoConstraints = NO;
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
        [_scrollView.bottomAnchor constraintEqualToAnchor:_pageControl.topAnchor constant:-8],
        [_stack.leadingAnchor constraintEqualToAnchor:_scrollView.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scrollView.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scrollView.widthAnchor],
        [_pageControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_pageControl.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-12],
        [_nextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_nextButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_nextButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18],
        [_nextButton.heightAnchor constraintEqualToConstant:52]
    ]];
}

- (void)buildRequestControls {
    UIView *step1 = [self stepBlockWithStep:@"STEP1" title:@"開発者をフォロー" buttonTitle:@"開発者をフォロー" icon:@"🦈" action:@selector(openDeveloper)];
    [_requestStack addArrangedSubview:step1];
    UIView *step2 = [self stepBlockWithStep:@"STEP2" title:@"ライセンスを要求" buttonTitle:@"ライセンスを要求" icon:@"🔑" action:@selector(openLicenseRequest)];
    [_requestStack addArrangedSubview:step2];
}

- (UIView *)stepBlockWithStep:(NSString *)step title:(NSString *)title buttonTitle:(NSString *)buttonTitle icon:(NSString *)icon action:(SEL)action {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 18.0;
    card.layer.masksToBounds = YES;
    UIStackView *box = [UIStackView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 9.0;
    box.layoutMargins = UIEdgeInsetsMake(15, 15, 15, 15);
    box.layoutMarginsRelativeArrangement = YES;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    UILabel *stepLabel = [UILabel new];
    stepLabel.text = step;
    stepLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    stepLabel.textColor = UIColor.secondaryLabelColor;
    [box addArrangedSubview:stepLabel];
    UILabel *titleLabel = [UILabel new];
    titleLabel.text = [NSString stringWithFormat:@"%@ %@", icon ?: @"", title ?: @""];
    titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    titleLabel.numberOfLines = 0;
    [box addArrangedSubview:titleLabel];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.systemTealColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    [button setTitle:buttonTitle forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    button.userInteractionEnabled = YES;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [box addArrangedSubview:button];
    [button.heightAnchor constraintEqualToConstant:50].active = YES;
    return card;
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

- (NSDictionary *)currentPageInfo {
    return _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
}

- (NSString *)currentKind {
    return [self currentPageInfo][@"kind"] ?: @"";
}

- (void)renderPage {
    NSDictionary *page = [self currentPageInfo];
    NSString *kind = page[@"kind"] ?: @"";
    UIColor *accent = page[@"accent"] ?: UIColor.systemRedColor;
    BOOL requestPage = [kind isEqualToString:@"request"];
    BOOL licensePage = [kind isEqualToString:@"license"];
    BOOL startPage = [kind isEqualToString:@"start"];
    BOOL licensed = YTNicoLicenseReady() || _licenseVerifiedInSession;

    _iconLabel.text = page[@"icon"];
    _iconBackground.backgroundColor = [accent colorWithAlphaComponent:0.14];
    _titleLabel.text = page[@"title"];
    _bodyLabel.text = page[@"body"];
    _nextButton.backgroundColor = accent;
    _pageControl.currentPage = _index;

    [self fillTips:page[@"tips"] ?: @[] accent:accent];
    _requestStack.hidden = !requestPage;
    _skipButton.hidden = !licensed;
    _backButton.hidden = (_index == 0);
    _statusLabel.hidden = (_statusLabel.text.length == 0);

    if (licensePage) [_nextButton setTitle:@"認証する" forState:UIControlStateNormal];
    else if (startPage) [_nextButton setTitle:@"さぁ、はじめよう" forState:UIControlStateNormal];
    else [_nextButton setTitle:@"次へ" forState:UIControlStateNormal];
    [_scrollView setContentOffset:CGPointZero animated:NO];
}

- (void)nextTapped {
    NSString *kind = [self currentKind];
    if ([kind isEqualToString:@"license"]) {
        [self showLicensePrompt];
        return;
    }
    if ([kind isEqualToString:@"start"]) {
        if (_licenseVerifiedInSession || YTNicoLicenseReady()) {
            YTNicoTutorialSetReady();
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

- (void)showLicensePrompt {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ライセンス認証" message:@"ライセンスキーを入力してください。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"ライセンスキー";
        textField.textAlignment = NSTextAlignmentCenter;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"認証" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        YTNicoTutorialViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *input = alert.textFields.firstObject.text ?: @"";
        if (YTNicoTutorialCheckLicense(input)) {
            strongSelf->_licenseVerifiedInSession = YES;
            strongSelf->_statusLabel.text = @"✅ 認証できました。";
            [strongSelf goNextWithAnimation];
        } else {
            [strongSelf showLicenseRequiredAlert];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"キャンセル" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)goNextWithAnimation {
    if (_index >= (NSInteger)_pages.count - 1) return;
    _index++;
    if (![[self currentKind] isEqualToString:@"start"]) _statusLabel.text = @"";
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

- (void)showLicenseRequiredAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ライセンスが必要です" message:@"ライセンスキーを入力してください。まだ持っていない場合は、前のページから要求できます。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
    _statusLabel.text = @"戻ったら、STEP2へ進んでください。";
    [self renderPage];
    [self openURLString:@"https://x.com/sa_me_kun"];
}

- (void)openLicenseRequest {
    YTNicoSuppressTutorialForSeconds(60.0);
    _statusLabel.text = @"要求後、受け取ったキーを次のページで入力してください。";
    [self renderPage];
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

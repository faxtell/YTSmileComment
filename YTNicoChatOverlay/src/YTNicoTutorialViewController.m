#import <UIKit/UIKit.h>

static NSString * const kYTNicoTutorialDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoTutorialShownKey = @"tutorial.shown.v1";
static NSString * const kYTNicoLicenseReadyKey = @"ready.v1";

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
    UILabel *_titleLabel;
    UILabel *_bodyLabel;
    UIStackView *_tipsStack;
    UIStackView *_actionStack;
    UIButton *_followButton;
    UIButton *_requestButton;
    UITextField *_licenseField;
    UILabel *_licenseHintLabel;
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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    _index = 0;
    _licenseVerifiedInSession = YTNicoLicenseReady();
    _pages = @[
        @{@"kind":@"intro", @"icon":@"📺", @"title":@"ようこそ", @"body":@"YouTubeのライブチャットを、動画上にニコニコ風で流せます。\n\n現在は安定性優先のライブチャット専用モードです。", @"tips":@[@"ライブ配信のリアルタイムチャットに対応", @"通常コメントとリプレイはComing Soon…", @"動画の上にコメントが流れます"]},
        @{@"kind":@"usage", @"icon":@"💬", @"title":@"使い方", @"body":@"ライブ配信を開くと、リアルタイムチャットの取得を試します。\n\n自動取得できない場合は、手動取得も使えます。", @"tips":@[@"ライブ配信を開く", @"吹き出しボタンでON/OFF", @"自動取得できない時は、動画の共有ボタンからリンクをコピー", @"その後、吹き出しボタンから手動でコメント取得"]},
        @{@"kind":@"settings", @"icon":@"🎨", @"title":@"設定", @"body":@"設定は2列のカテゴリに整理されています。\n\n必要な項目だけをすぐに見つけられるようにしています。", @"tips":@[@"🎨 表示 = 文字や投稿者名", @"📡 ライブチャット = 取得まわり", @"🛠️ 操作/デバッグ = ログ確認", @"🚧 Coming Soon… = 今後追加予定"]},
        @{@"kind":@"request", @"icon":@"🦈", @"title":@"ライセンスの受け取り", @"body":@"利用にはライセンスが必要です。\n\n下の手順で申請してください。", @"tips":@[@"開発者をフォロー", @"ライセンスを申請", @"受け取ったキーを次のページで入力"]},
        @{@"kind":@"license", @"icon":@"🔑", @"title":@"ライセンス認証", @"body":@"受け取ったライセンスキーを入力してください。\n\n認証が完了するまで、このページから先には進めません。", @"tips":@[@"キー入力後、ライセンス認証を押してください", @"成功すると最後のページへ進みます"]},
        @{@"kind":@"start", @"icon":@"🚀", @"title":@"さぁ、はじめよう", @"body":@"準備が完了しました。\n\nこのボタンを押すと機能が有効になり、ライブチャット表示を利用できます。", @"tips":@[@"ライブ配信を開いて試してみましょう", @"困った時は設定の操作/デバッグを確認"]}
    ];

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

    UIView *illustration = [UIView new];
    illustration.translatesAutoresizingMaskIntoConstraints = NO;
    illustration.backgroundColor = UIColor.secondarySystemBackgroundColor;
    illustration.layer.cornerRadius = 34.0;
    illustration.layer.masksToBounds = YES;
    [_stack addArrangedSubview:illustration];
    [illustration.widthAnchor constraintEqualToConstant:132].active = YES;
    [illustration.heightAnchor constraintEqualToConstant:132].active = YES;

    _icon = [UILabel new];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.font = [UIFont systemFontOfSize:64 weight:UIFontWeightRegular];
    _icon.textAlignment = NSTextAlignmentCenter;
    [illustration addSubview:_icon];
    [NSLayoutConstraint activateConstraints:@[
        [_icon.centerXAnchor constraintEqualToAnchor:illustration.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:illustration.centerYAnchor]
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

- (UILabel *)tipLabel:(NSString *)text {
    UILabel *label = [UILabel new];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
    label.backgroundColor = UIColor.secondarySystemBackgroundColor;
    label.layer.cornerRadius = 12.0;
    label.layer.masksToBounds = YES;
    label.text = [NSString stringWithFormat:@"  %@  ", text ?: @""];
    return label;
}

- (void)fillTips:(NSArray<NSString *> *)tips {
    for (UIView *v in _tipsStack.arrangedSubviews.copy) {
        [_tipsStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSString *tip in tips) [_tipsStack addArrangedSubview:[self tipLabel:tip]];
}

- (NSString *)currentKind {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    return p[@"kind"] ?: @"";
}

- (void)renderPage {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    NSString *kind = p[@"kind"] ?: @"";
    BOOL requestPage = [kind isEqualToString:@"request"];
    BOOL licensePage = [kind isEqualToString:@"license"];
    BOOL startPage = [kind isEqualToString:@"start"];

    _icon.text = p[@"icon"];
    _titleLabel.text = p[@"title"];
    _bodyLabel.text = p[@"body"];
    [self fillTips:p[@"tips"] ?: @[]];
    _page.currentPage = _index;

    _followButton.hidden = !requestPage;
    _requestButton.hidden = !requestPage;
    _licenseField.hidden = !licensePage;
    _licenseHintLabel.hidden = !licensePage;
    _actionStack.hidden = !(requestPage || licensePage);
    _skipButton.hidden = licensePage || startPage;

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
            [self goNextWithAnimation];
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
    [UIView transitionWithView:self.view duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self renderPage];
    } completion:nil];
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

- (void)openDeveloper { [self openURLString:@"https://x.com/sa_me_kun"]; }
- (void)openLicenseRequest { [self openURLString:@"https://twitter.com/messages/compose?recipient_id=1678480958671163392"]; }

- (void)skipTutorial {
    [YTNicoTutorialViewController markTutorialShown];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)closeTutorial {
    [YTNicoTutorialViewController markTutorialShown];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

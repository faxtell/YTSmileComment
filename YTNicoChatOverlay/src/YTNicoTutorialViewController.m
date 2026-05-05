#import <UIKit/UIKit.h>

static NSString * const kYTNicoTutorialDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoTutorialShownKey = @"tutorial.shown.v1";
static NSString * const kYTNicoLicenseReadyKey = @"ready.v1";

@interface YTNicoTutorialViewController : UIViewController
+ (BOOL)shouldShowTutorial;
+ (void)markTutorialShown;
@end

@implementation YTNicoTutorialViewController {
    UIStackView *_stack;
    UIPageControl *_page;
    NSArray<NSDictionary *> *_pages;
    NSInteger _index;
    UILabel *_icon;
    UILabel *_titleLabel;
    UILabel *_bodyLabel;
    UIButton *_followButton;
    UIButton *_requestButton;
    UITextField *_licenseField;
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
    _pages = @[
        @{@"icon":@"📺", @"title":@"ようこそ", @"body":@"YouTubeのライブチャットを、動画上にニコニコ風で流せます。\n\n現在は安定性優先のライブチャット専用モードです。"},
        @{@"icon":@"💬", @"title":@"使い方", @"body":@"ライブ配信を開くと、リアルタイムチャットの取得を試します。\n\n吹き出しボタンから表示のON/OFFもできます。"},
        @{@"icon":@"🎨", @"title":@"表示", @"body":@"コメントは見やすい白文字＋黒縁で流れます。\n\n文字サイズや投稿者名は、表示カテゴリから変更できます。"},
        @{@"icon":@"🛠️", @"title":@"設定", @"body":@"設定は2列のカテゴリに整理されています。\n\nComing Soon… の項目は、今後の安定化後に開放予定です。"},
        @{@"icon":@"🔑", @"title":@"ライセンス認証", @"body":@"利用するにはライセンス認証が必要です。\n\n1. 開発者をフォロー\n2. ライセンス要求を送信\n3. 受け取ったライセンスキーを入力してください。"}
    ];

    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 26.0;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    _stack = [UIStackView new];
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.alignment = UIStackViewAlignmentCenter;
    _stack.spacing = 12.0;
    _stack.layoutMargins = UIEdgeInsetsMake(24, 24, 24, 24);
    _stack.layoutMarginsRelativeArrangement = YES;
    [card addSubview:_stack];

    _icon = [UILabel new];
    _icon.font = [UIFont systemFontOfSize:58 weight:UIFontWeightRegular];
    _icon.textAlignment = NSTextAlignmentCenter;
    [_stack addArrangedSubview:_icon];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:27 weight:UIFontWeightBold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_titleLabel];

    _bodyLabel = [UILabel new];
    _bodyLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightRegular];
    _bodyLabel.textColor = UIColor.secondaryLabelColor;
    _bodyLabel.textAlignment = NSTextAlignmentCenter;
    _bodyLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_bodyLabel];

    _followButton = [self actionButtonWithTitle:@"🦈 開発者をフォロー" subtitle:@"x.com/sa_me_kun"];
    [_followButton addTarget:self action:@selector(openDeveloper) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_followButton];

    _requestButton = [self actionButtonWithTitle:@"🔑 ライセンス要求" subtitle:@"DMでライセンスを要求"];
    [_requestButton addTarget:self action:@selector(openLicenseRequest) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_requestButton];

    _licenseField = [UITextField new];
    _licenseField.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseField.placeholder = @"ライセンスキー";
    _licenseField.textAlignment = NSTextAlignmentCenter;
    _licenseField.borderStyle = UITextBorderStyleRoundedRect;
    _licenseField.autocorrectionType = UITextAutocorrectionTypeNo;
    _licenseField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [_stack addArrangedSubview:_licenseField];
    [_licenseField.widthAnchor constraintEqualToConstant:220].active = YES;
    [_licenseField.heightAnchor constraintEqualToConstant:42].active = YES;

    _page = [UIPageControl new];
    _page.translatesAutoresizingMaskIntoConstraints = NO;
    _page.numberOfPages = _pages.count;
    [self.view addSubview:_page];

    _skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_skipButton setTitle:@"あとで" forState:UIControlStateNormal];
    _skipButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_skipButton addTarget:self action:@selector(skipTutorial) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_skipButton];

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
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [card.topAnchor constraintEqualToAnchor:_skipButton.bottomAnchor constant:16],
        [card.bottomAnchor constraintEqualToAnchor:_page.topAnchor constant:-16],
        [_stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [_page.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_page.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-16],
        [_nextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_nextButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_nextButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18],
        [_nextButton.heightAnchor constraintEqualToConstant:52]
    ]];
    [self renderPage];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentEdgeInsets = UIEdgeInsetsMake(9, 12, 9, 12);
    button.titleLabel.numberOfLines = 2;
    NSString *full = [NSString stringWithFormat:@"%@\n%@", title, subtitle ?: @""];
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:full];
    [a addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:[full rangeOfString:title]];
    NSRange sub = [full rangeOfString:subtitle ?: @""];
    if (sub.location != NSNotFound && sub.length > 0) {
        [a addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
        [a addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    }
    [button setAttributedTitle:a forState:UIControlStateNormal];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:230].active = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    return button;
}

- (void)renderPage {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    BOOL licensePage = (_index == (NSInteger)_pages.count - 1);
    _icon.text = p[@"icon"];
    _titleLabel.text = p[@"title"];
    _bodyLabel.text = p[@"body"];
    _page.currentPage = _index;
    _followButton.hidden = !licensePage;
    _requestButton.hidden = !licensePage;
    _licenseField.hidden = !licensePage;
    _skipButton.hidden = licensePage && !YTNicoLicenseReady();
    if (licensePage) {
        [_nextButton setTitle:(YTNicoLicenseReady() ? @"はじめる" : @"ライセンス認証") forState:UIControlStateNormal];
    } else {
        [_nextButton setTitle:@"次へ" forState:UIControlStateNormal];
    }
}

- (void)nextTapped {
    BOOL licensePage = (_index == (NSInteger)_pages.count - 1);
    if (licensePage) {
        if (YTNicoLicenseReady()) {
            [self closeTutorial];
            return;
        }
        if (YTNicoTutorialCheckLicense(_licenseField.text ?: @"")) {
            YTNicoTutorialSetLicenseReady();
            [self closeTutorial];
            return;
        }
        [self showLicenseRequiredAlert];
        return;
    }
    _index++;
    [UIView transitionWithView:self.view duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self renderPage];
    } completion:nil];
}

- (void)showLicenseRequiredAlert {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"ライセンスが必要です" message:@"ライセンスキーがない場合は、開発者をフォローしてライセンス要求を送信してください。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"ライセンス要求" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [self openLicenseRequest]; }]];
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

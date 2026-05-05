#import <UIKit/UIKit.h>

static NSString * const kYTNicoTutorialDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoTutorialShownKey = @"tutorial.shown.v1";

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

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    _index = 0;
    _pages = @[
        @{@"icon":@"📺", @"title":@"ようこそ", @"body":@"YouTubeのライブチャットを、動画上にニコニコ風で流せます。\n\n現在は安定性優先のライブチャット専用モードです。"},
        @{@"icon":@"💬", @"title":@"使い方", @"body":@"ライブ配信を開くと、リアルタイムチャットの取得を試します。\n\n吹き出しボタンから表示のON/OFFもできます。"},
        @{@"icon":@"🎨", @"title":@"表示", @"body":@"コメントは見やすい白文字＋黒縁で流れます。\n\n文字サイズや投稿者名は、表示カテゴリから変更できます。"},
        @{@"icon":@"🛠️", @"title":@"設定", @"body":@"設定は2列のカテゴリに整理されています。\n\nComing Soon… の項目は、今後の安定化後に開放予定です。"}
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
    _stack.spacing = 14.0;
    _stack.layoutMargins = UIEdgeInsetsMake(28, 24, 28, 24);
    _stack.layoutMarginsRelativeArrangement = YES;
    [card addSubview:_stack];

    _icon = [UILabel new];
    _icon.font = [UIFont systemFontOfSize:64 weight:UIFontWeightRegular];
    _icon.textAlignment = NSTextAlignmentCenter;
    [_stack addArrangedSubview:_icon];

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_titleLabel];

    _bodyLabel = [UILabel new];
    _bodyLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _bodyLabel.textColor = UIColor.secondaryLabelColor;
    _bodyLabel.textAlignment = NSTextAlignmentCenter;
    _bodyLabel.numberOfLines = 0;
    [_stack addArrangedSubview:_bodyLabel];

    _page = [UIPageControl new];
    _page.translatesAutoresizingMaskIntoConstraints = NO;
    _page.numberOfPages = _pages.count;
    [self.view addSubview:_page];

    UIButton *skip = [UIButton buttonWithType:UIButtonTypeSystem];
    skip.translatesAutoresizingMaskIntoConstraints = NO;
    [skip setTitle:@"スキップ" forState:UIControlStateNormal];
    skip.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [skip addTarget:self action:@selector(closeTutorial) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:skip];

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
        [skip.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [skip.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [card.topAnchor constraintEqualToAnchor:skip.bottomAnchor constant:24],
        [card.bottomAnchor constraintEqualToAnchor:_page.topAnchor constant:-22],
        [_stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [_page.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_page.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-18],
        [_nextButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22],
        [_nextButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22],
        [_nextButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18],
        [_nextButton.heightAnchor constraintEqualToConstant:52]
    ]];
    [self renderPage];
}

- (void)renderPage {
    NSDictionary *p = _pages[MAX(0, MIN(_index, (NSInteger)_pages.count - 1))];
    _icon.text = p[@"icon"];
    _titleLabel.text = p[@"title"];
    _bodyLabel.text = p[@"body"];
    _page.currentPage = _index;
    [_nextButton setTitle:(_index >= (NSInteger)_pages.count - 1 ? @"はじめる" : @"次へ") forState:UIControlStateNormal];
}

- (void)nextTapped {
    if (_index >= (NSInteger)_pages.count - 1) {
        [self closeTutorial];
        return;
    }
    _index++;
    [UIView transitionWithView:self.view duration:0.22 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self renderPage];
    } completion:nil];
}

- (void)closeTutorial {
    [YTNicoTutorialViewController markTutorialShown];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

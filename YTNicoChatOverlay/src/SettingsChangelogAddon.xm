#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const void *kYTNicoChangelogButtonKey = &kYTNicoChangelogButtonKey;
static const void *kYTNicoChangelogCardKey = &kYTNicoChangelogCardKey;

@interface YTNicoChangelogViewController : UIViewController
@end

static UILabel *YTNicoCLLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color ?: UIColor.labelColor;
    return label;
}

static UIView *YTNicoCLCard(void) {
    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    return card;
}

static void YTNicoCLAddVersion(UIStackView *stack, NSString *version, NSString *date, NSString *badge, NSArray<NSString *> *items) {
    UIView *card = YTNicoCLCard();
    UIStackView *box = [UIStackView new];
    box.axis = UILayoutConstraintAxisVertical;
    box.spacing = 7.0;
    box.layoutMargins = UIEdgeInsetsMake(15, 15, 15, 15);
    box.layoutMarginsRelativeArrangement = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:box];
    [NSLayoutConstraint activateConstraints:@[
        [box.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [box.topAnchor constraintEqualToAnchor:card.topAnchor],
        [box.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];

    NSString *title = badge.length ? [NSString stringWithFormat:@"%@  %@", version, badge] : version;
    [box addArrangedSubview:YTNicoCLLabel(title, 17.0, UIFontWeightBold, nil)];
    [box addArrangedSubview:YTNicoCLLabel(date, 12.0, UIFontWeightSemibold, UIColor.secondaryLabelColor)];
    for (NSString *item in items) [box addArrangedSubview:YTNicoCLLabel([NSString stringWithFormat:@"・%@", item], 13.0, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [stack addArrangedSubview:card];
}

@implementation YTNicoChangelogViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"更新履歴";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.layoutMargins = UIEdgeInsetsMake(18, 18, 24, 18);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];

    [stack addArrangedSubview:YTNicoCLLabel(@"📝 更新履歴", 28.0, UIFontWeightBold, nil)];
    [stack addArrangedSubview:YTNicoCLLabel(@"Nightly単位で細かく変更内容を記録します。次回以降の変更もここに追記して、ユーザーが何が変わったかわかるようにします。", 13.5, UIFontWeightMedium, UIColor.secondaryLabelColor)];

    YTNicoCLAddVersion(stack, @"Nightly 0.9.2", @"2026.05.09", @"最新", @[
        @"💬ボタンでチャット追跡モードを開始できるようにしました。ボタンを押すと、動画を変えるまで表示中のチャット欄を定期的に読み取ります。",
        @"チャットリプレイがAPIから取得できない動画でも、開いているチャット欄の表示内容からコメントを流せるようにしました。",
        @"@ユーザー名はできるだけ消して、コメント本文だけを流すように調整しました。",
        @"2行コメントや少し位置がズレたコメントも欠けにくいように、行の組み立て範囲を広げました。",
        @"GitHub Actionsの成果物をYTNicoChatOverlay.debとして扱いやすくしました。"
    ]);

    YTNicoCLAddVersion(stack, @"Nightly 0.9.1", @"2026.05", @"安定化", @[
        @"設定画面をリリース向けに整理し、コメント表示・コメント取得・見た目・サポートに分けました。",
        @"🦈アイコンとバージョン表示を設定画面の上部に追加しました。",
        @"不具合報告ボタン、開発者フォローボタン、表示テストコメントを追加しました。",
        @"チュートリアル中は吹き出しボタンを隠し、終了後に表示するようにしました。",
        @"PiP中の吹き出しボタン表示や、横画面/縦画面切り替え時のコメント表示を調整しました。"
    ]);

    YTNicoCLAddVersion(stack, @"Nightly 0.9.0", @"2026.05", @"取得改善", @[
        @"通常コメント・ライブチャット・チャットリプレイの取得を強化しました。",
        @"新API → 旧API → deep search → HTML/JSONフォールバックの順に取得を試すようにしました。",
        @"コメントが取得できない場合に、YouTubeアプリ内のチャットUIを検出するフォールバックを追加しました。",
        @"コメント量に応じた自動レーン調整を追加し、画面いっぱいにコメントが流れやすくしました。"
    ]);

    YTNicoCLAddVersion(stack, @"Nightly 0.8.x", @"2026.05", @"初期UI", @[
        @"初回チュートリアルを全画面表示に変更しました。",
        @"使い方に、共有ボタンからリンクをコピーして手動取得できる説明を追加しました。",
        @"ライセンス要求・ライセンス認証画面を通常チュートリアルとは違う作りにしました。",
        @"STEP1 開発者をフォロー、STEP2 ライセンスを要求、という流れを追加しました。"
    ]);

    UIView *note = YTNicoCLCard();
    UIStackView *noteBox = [UIStackView new];
    noteBox.axis = UILayoutConstraintAxisVertical;
    noteBox.spacing = 5.0;
    noteBox.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    noteBox.layoutMarginsRelativeArrangement = YES;
    noteBox.translatesAutoresizingMaskIntoConstraints = NO;
    [note addSubview:noteBox];
    [NSLayoutConstraint activateConstraints:@[
        [noteBox.leadingAnchor constraintEqualToAnchor:note.leadingAnchor],
        [noteBox.trailingAnchor constraintEqualToAnchor:note.trailingAnchor],
        [noteBox.topAnchor constraintEqualToAnchor:note.topAnchor],
        [noteBox.bottomAnchor constraintEqualToAnchor:note.bottomAnchor]
    ]];
    [noteBox addArrangedSubview:YTNicoCLLabel(@"次回以降の書き方", 15.0, UIFontWeightBold, nil)];
    [noteBox addArrangedSubview:YTNicoCLLabel(@"例：Nightly 0.9.3 / 2026.05.xx / ユーザー向けに『何が便利になったか』を短く追記します。", 12.5, UIFontWeightRegular, UIColor.secondaryLabelColor)];
    [stack addArrangedSubview:note];
}
@end

static UIButton *YTNicoCLButton(NSString *title, NSString *subtitle, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = UIColor.tertiarySystemBackgroundColor;
    button.layer.cornerRadius = 15.0;
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
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

%hook YTNicoSettingsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        id obj = (id)self;
        UIStackView *stack = [obj valueForKey:@"stack"];
        if (![stack isKindOfClass:UIStackView.class] || objc_getAssociatedObject(obj, kYTNicoChangelogCardKey)) return;

        UIView *card = YTNicoCLCard();
        UIStackView *box = [UIStackView new];
        box.axis = UILayoutConstraintAxisVertical;
        box.spacing = 8.0;
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
        [box addArrangedSubview:YTNicoCLLabel(@"📝 最新の更新", 15.5, UIFontWeightBold, nil)];
        [box addArrangedSubview:YTNicoCLLabel(@"Nightly 0.9.2：💬を押すとチャット欄を継続追跡。動画を変えるまで表示中コメントを拾い続けます。", 12.5, UIFontWeightRegular, UIColor.secondaryLabelColor)];
        UIButton *button = YTNicoCLButton(@"📝 更新履歴を見る", @"これまでの変更とNightlyバージョン", obj, @selector(ytnico_openChangelog));
        [box addArrangedSubview:button];
        objc_setAssociatedObject(obj, kYTNicoChangelogButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NSUInteger index = stack.arrangedSubviews.count > 0 ? stack.arrangedSubviews.count - 1 : stack.arrangedSubviews.count;
        [stack insertArrangedSubview:card atIndex:index];
        objc_setAssociatedObject(obj, kYTNicoChangelogCardKey, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {}
}

%new
- (void)ytnico_openChangelog {
    YTNicoChangelogViewController *vc = [YTNicoChangelogViewController new];
    UIViewController *controller = (UIViewController *)self;
    [controller.navigationController pushViewController:vc animated:YES];
}
%end

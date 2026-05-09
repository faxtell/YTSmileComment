#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTNicoTutorialViewController : UIViewController
- (void)ytnico_rewireLicenseButtons;
- (void)ytnico_openExternalURLString:(NSString *)urlString fallback:(NSString *)fallbackURLString;
- (void)ytnico_followDeveloperDirect;
- (void)ytnico_requestLicenseDirect;
@end

static const void *kYTNicoTutorialButtonRewiredKey = &kYTNicoTutorialButtonRewiredKey;
static const void *kYTNicoTutorialCardTapKey = &kYTNicoTutorialCardTapKey;

static NSArray<UIButton *> *YTNicoFindButtons(UIView *view) {
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    if ([view isKindOfClass:UIButton.class]) [buttons addObject:(UIButton *)view];
    for (UIView *sub in view.subviews) [buttons addObjectsFromArray:YTNicoFindButtons(sub)];
    return buttons;
}

static NSString *YTNicoButtonTitle(UIButton *button) {
    NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
    if (title.length == 0) title = button.currentTitle ?: @"";
    if (title.length == 0) title = button.accessibilityLabel ?: @"";
    NSString *at = button.currentAttributedTitle.string ?: @"";
    if (at.length) title = [title.length ? [title stringByAppendingFormat:@" %@", at] : at copy];
    return title ?: @"";
}

%hook YTNicoTutorialViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [self ytnico_rewireLicenseButtons];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [self ytnico_rewireLicenseButtons];
}

%new
- (void)ytnico_rewireLicenseButtons {
    for (UIButton *button in YTNicoFindButtons(self.view)) {
        NSString *title = YTNicoButtonTitle(button);
        BOOL developer = [title rangeOfString:@"開発者をフォロー"].location != NSNotFound;
        BOOL request = [title rangeOfString:@"ライセンスを要求"].location != NSNotFound;
        if (!developer && !request) continue;

        button.enabled = YES;
        button.userInteractionEnabled = YES;
        button.exclusiveTouch = NO;
        button.alpha = 1.0;
        button.accessibilityTraits |= UIAccessibilityTraitButton;
        button.accessibilityLabel = developer ? @"開発者をフォロー" : @"ライセンスを要求";

        if (![objc_getAssociatedObject(button, kYTNicoTutorialButtonRewiredKey) boolValue]) {
            [button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self action:(developer ? @selector(ytnico_followDeveloperDirect) : @selector(ytnico_requestLicenseDirect)) forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(button, kYTNicoTutorialButtonRewiredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        UIView *card = button.superview.superview ?: button.superview;
        card.userInteractionEnabled = YES;
        if (![objc_getAssociatedObject(card, kYTNicoTutorialCardTapKey) boolValue]) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:(developer ? @selector(ytnico_followDeveloperDirect) : @selector(ytnico_requestLicenseDirect))];
            tap.cancelsTouchesInView = NO;
            [card addGestureRecognizer:tap];
            objc_setAssociatedObject(card, kYTNicoTutorialCardTapKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

%new
- (void)ytnico_openExternalURLString:(NSString *)urlString fallback:(NSString *)fallbackURLString {
    if (urlString.length == 0) return;
    UIPasteboard.generalPasteboard.string = urlString;
    NSURL *url = [NSURL URLWithString:urlString];
    NSURL *fallback = fallbackURLString.length ? [NSURL URLWithString:fallbackURLString] : nil;
    UIApplication *app = UIApplication.sharedApplication;
    dispatch_async(dispatch_get_main_queue(), ^{
        void (^showFallback)(void) = ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"リンクをコピーしました" message:@"ブラウザで開けない場合は、コピー済みのURLをSafariなどに貼り付けてください。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        };
        if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
            [app openURL:url options:@{} completionHandler:^(BOOL success) {
                if (!success && fallback) {
                    [app openURL:fallback options:@{} completionHandler:^(BOOL ok) { if (!ok) showFallback(); }];
                } else if (!success) {
                    showFallback();
                }
            }];
        } else {
            BOOL ok = [app openURL:url];
            if (!ok && fallback) ok = [app openURL:fallback];
            if (!ok) showFallback();
        }
    });
}

%new
- (void)ytnico_followDeveloperDirect {
    [self ytnico_openExternalURLString:@"https://x.com/sa_me_kun" fallback:@"https://twitter.com/sa_me_kun"];
}

%new
- (void)ytnico_requestLicenseDirect {
    [self ytnico_openExternalURLString:@"https://twitter.com/messages/compose?recipient_id=1678480958671163392" fallback:@"https://x.com/messages/compose?recipient_id=1678480958671163392"];
}

%end

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString * const kYTNicoTutorialVisibleNotification = @"com.example.ytnico.tutorial.visible.changed";
static const void *kYTNicoHiddenForTutorialKey = &kYTNicoHiddenForTutorialKey;
static BOOL gYTNicoTutorialVisible = NO;

static BOOL YTNicoIsDescendantOfTutorial(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        UIResponder *r = v.nextResponder;
        while (r) {
            NSString *name = NSStringFromClass(r.class);
            if ([name rangeOfString:@"YTNicoTutorialViewController"].location != NSNotFound) return YES;
            r = r.nextResponder;
        }
    }
    return NO;
}

static NSString *YTNicoViewText(UIView *view) {
    NSMutableString *text = [NSMutableString stringWithString:NSStringFromClass(view.class) ?: @""];
    NSString *a = view.accessibilityLabel ?: @"";
    if (a.length) [text appendFormat:@" %@", a];
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *b = (UIButton *)view;
        NSString *t = [b titleForState:UIControlStateNormal] ?: b.currentTitle ?: @"";
        if (t.length) [text appendFormat:@" %@", t];
        NSString *at = b.currentAttributedTitle.string ?: @"";
        if (at.length) [text appendFormat:@" %@", at];
    }
    return text;
}

static BOOL YTNicoLooksLikeBubbleButton(UIView *view) {
    if (!view || YTNicoIsDescendantOfTutorial(view)) return NO;
    NSString *text = YTNicoViewText(view);
    BOOL named = [text rangeOfString:@"YTNico" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                 [text rangeOfString:@"Nico" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                 [text rangeOfString:@"Bubble" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                 [text rangeOfString:@"コメント"].location != NSNotFound ||
                 [text rangeOfString:@"吹き出し"].location != NSNotFound ||
                 [text rangeOfString:@"💬"].location != NSNotFound;
    if (named) return YES;

    if (![view isKindOfClass:UIButton.class]) return NO;
    CGRect f = [view.superview convertRect:view.frame toView:nil];
    CGFloat w = CGRectGetWidth(f), h = CGRectGetHeight(f);
    BOOL floatingSize = w >= 34 && w <= 88 && h >= 34 && h <= 88 && fabs(w - h) <= 28;
    BOOL nearEdge = CGRectGetMinX(f) < 96 || CGRectGetMaxX(f) > UIScreen.mainScreen.bounds.size.width - 96;
    return floatingSize && nearEdge;
}

static void YTNicoScanAndSetBubbleHiddenInView(UIView *view, BOOL hidden) {
    if (!view) return;
    if (YTNicoLooksLikeBubbleButton(view)) {
        if (hidden) {
            objc_setAssociatedObject(view, kYTNicoHiddenForTutorialKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.alpha = 0.0;
            view.hidden = YES;
        } else if ([objc_getAssociatedObject(view, kYTNicoHiddenForTutorialKey) boolValue]) {
            objc_setAssociatedObject(view, kYTNicoHiddenForTutorialKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            view.hidden = NO;
            view.alpha = 0.0;
            view.transform = CGAffineTransformMakeScale(0.45, 0.45);
            [UIView animateWithDuration:0.34 delay:0.18 usingSpringWithDamping:0.42 initialSpringVelocity:0.9 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                view.alpha = 1.0;
                view.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }
    for (UIView *sub in view.subviews) YTNicoScanAndSetBubbleHiddenInView(sub, hidden);
}

static void YTNicoSetBubbleHiddenForTutorial(BOOL hidden) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            YTNicoScanAndSetBubbleHiddenInView(window, hidden);
        }
    });
}

%hook YTNicoTutorialViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gYTNicoTutorialVisible = YES;
    YTNicoSetBubbleHiddenForTutorial(YES);
    [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoTutorialVisibleNotification object:nil userInfo:@{@"visible":@YES}];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gYTNicoTutorialVisible = YES;
    YTNicoSetBubbleHiddenForTutorial(YES);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    gYTNicoTutorialVisible = NO;
    YTNicoSetBubbleHiddenForTutorial(NO);
    [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoTutorialVisibleNotification object:nil userInfo:@{@"visible":@NO}];
}

%end

%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (gYTNicoTutorialVisible) YTNicoSetBubbleHiddenForTutorial(YES);
}

%end

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL YTNicoStringContainsAnyForPiPBubble(NSString *s, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        if ([s rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static NSString *YTNicoViewTextForPiPBubble(UIView *view) {
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

static BOOL YTNicoLooksLikePiPWindowOrView(UIView *view) {
    NSArray<NSString *> *pipNeedles = @[@"PiP", @"PIP", @"PictureInPicture", @"Picture", @"Pinnable"];
    for (UIView *v = view; v; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if (YTNicoStringContainsAnyForPiPBubble(name, pipNeedles)) return YES;
        if ([v isKindOfClass:UIWindow.class]) {
            NSString *wn = NSStringFromClass(v.class);
            if (YTNicoStringContainsAnyForPiPBubble(wn, pipNeedles)) return YES;
        }
    }
    return NO;
}

static BOOL YTNicoLooksLikeBubbleButtonInPiP(UIView *view) {
    if (![view isKindOfClass:UIButton.class]) return NO;
    if (!YTNicoLooksLikePiPWindowOrView(view)) return NO;

    NSString *text = YTNicoViewTextForPiPBubble(view);
    if (YTNicoStringContainsAnyForPiPBubble(text, @[@"YTNico", @"Nico", @"Bubble", @"コメント", @"吹き出し", @"💬"])) return YES;

    CGRect f = [view.superview convertRect:view.frame toView:nil];
    CGFloat w = CGRectGetWidth(f), h = CGRectGetHeight(f);
    return w >= 30 && w <= 92 && h >= 30 && h <= 92 && fabs(w - h) <= 30;
}

static void YTNicoHidePiPBubbleButtonsInView(UIView *view) {
    if (!view) return;
    if (YTNicoLooksLikeBubbleButtonInPiP(view)) {
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
    }
    for (UIView *sub in view.subviews) YTNicoHidePiPBubbleButtonsInView(sub);
}

static void YTNicoHidePiPBubbleButtons(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            YTNicoHidePiPBubbleButtonsInView(window);
        }
    });
}

%hook UIView

- (void)didMoveToWindow {
    %orig;
    YTNicoHidePiPBubbleButtons();
}

- (void)layoutSubviews {
    %orig;
    YTNicoHidePiPBubbleButtons();
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        YTNicoHidePiPBubbleButtons();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoHidePiPBubbleButtons();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoHidePiPBubbleButtons();
        }];
    });
}

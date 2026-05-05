#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static const void *kYTNicoBubblePositionedKey = &kYTNicoBubblePositionedKey;

static BOOL YTNicoStringContainsAnyForBubblePosition(NSString *s, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        if ([s rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static NSString *YTNicoBubblePositionText(UIView *view) {
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

static BOOL YTNicoViewIsInPiP(UIView *view) {
    NSArray<NSString *> *pipNeedles = @[@"PiP", @"PIP", @"PictureInPicture", @"Picture", @"Pinnable"];
    for (UIView *v = view; v; v = v.superview) {
        if (YTNicoStringContainsAnyForBubblePosition(NSStringFromClass(v.class), pipNeedles)) return YES;
    }
    return NO;
}

static BOOL YTNicoLooksLikeBubbleButtonForPosition(UIView *view) {
    if (![view isKindOfClass:UIButton.class]) return NO;
    if (YTNicoViewIsInPiP(view)) return NO;
    NSString *text = YTNicoBubblePositionText(view);
    if (YTNicoStringContainsAnyForBubblePosition(text, @[@"YTNico", @"Nico", @"Bubble", @"コメント", @"吹き出し", @"💬"])) return YES;
    CGRect f = [view.superview convertRect:view.frame toView:nil];
    CGFloat w = CGRectGetWidth(f), h = CGRectGetHeight(f);
    BOOL floatingSize = w >= 34 && w <= 92 && h >= 34 && h <= 92 && fabs(w - h) <= 30;
    if (!floatingSize) return NO;
    BOOL nearEdge = CGRectGetMinX(f) < 120 || CGRectGetMaxX(f) > UIScreen.mainScreen.bounds.size.width - 120;
    return nearEdge;
}

static UIEdgeInsets YTNicoSafeInsetsForView(UIView *view) {
    if (@available(iOS 11.0, *)) return view.safeAreaInsets;
    return UIEdgeInsetsZero;
}

static void YTNicoMoveBubbleToBottomRight(UIView *button) {
    UIView *superview = button.superview;
    if (!superview || superview.bounds.size.width < 100 || superview.bounds.size.height < 100) return;
    CGSize size = button.bounds.size;
    if (size.width < 10 || size.height < 10) size = button.frame.size;
    if (size.width < 10 || size.height < 10) size = CGSizeMake(52, 52);

    UIEdgeInsets inset = YTNicoSafeInsetsForView(superview);
    CGFloat margin = 14.0;
    CGFloat x = superview.bounds.size.width - inset.right - margin - size.width;
    CGFloat y = superview.bounds.size.height - inset.bottom - margin - size.height;
    // Keep it above home indicator / bottom controls a bit.
    y = MAX(inset.top + margin, y - 18.0);

    CGRect target = CGRectMake(x, y, size.width, size.height);
    if (CGRectEqualToRect(button.frame, target)) return;
    button.hidden = NO;
    button.alpha = MAX(button.alpha, 1.0);
    objc_setAssociatedObject(button, kYTNicoBubblePositionedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        button.frame = target;
    } completion:nil];
}

static void YTNicoScanMoveBubbleButtons(UIView *view) {
    if (!view) return;
    if (YTNicoLooksLikeBubbleButtonForPosition(view)) YTNicoMoveBubbleToBottomRight(view);
    for (UIView *sub in view.subviews) YTNicoScanMoveBubbleButtons(sub);
}

static void YTNicoApplyBubbleButtonPosition(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            YTNicoScanMoveBubbleButtons(window);
        }
    });
}

%hook UIView

- (void)didMoveToWindow {
    %orig;
    YTNicoApplyBubbleButtonPosition();
}

- (void)layoutSubviews {
    %orig;
    YTNicoApplyBubbleButtonPosition();
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        YTNicoApplyBubbleButtonPosition();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoApplyBubbleButtonPosition();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoApplyBubbleButtonPosition();
        }];
    });
}

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static CFTimeInterval gYTNicoLastBubblePositionScan = 0;
static BOOL gYTNicoBubblePositionScanQueued = NO;
static CGSize gYTNicoLastBubbleScreenSize = {0, 0};

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
    y = MAX(inset.top + margin, y - 18.0);

    CGRect target = CGRectIntegral(CGRectMake(x, y, size.width, size.height));
    if (fabs(button.frame.origin.x - target.origin.x) < 1.0 && fabs(button.frame.origin.y - target.origin.y) < 1.0) return;

    button.hidden = NO;
    button.alpha = 1.0;

    // Do not animate here. Repeated layout passes made the button look like it was
    // falling from above and also caused avoidable UI work.
    [UIView performWithoutAnimation:^{
        button.frame = target;
        [button.superview layoutIfNeeded];
    }];
}

static void YTNicoScanMoveBubbleButtons(UIView *view, NSUInteger *count) {
    if (!view || *count > 4) return;
    if (YTNicoLooksLikeBubbleButtonForPosition(view)) {
        YTNicoMoveBubbleToBottomRight(view);
        (*count)++;
    }
    for (UIView *sub in view.subviews) YTNicoScanMoveBubbleButtons(sub, count);
}

static void YTNicoApplyBubbleButtonPositionNow(void) {
    NSUInteger moved = 0;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        YTNicoScanMoveBubbleButtons(window, &moved);
        if (moved > 4) break;
    }
}

static void YTNicoApplyBubbleButtonPositionDebounced(NSTimeInterval delay) {
    CFTimeInterval now = CACurrentMediaTime();
    if (gYTNicoBubblePositionScanQueued) return;
    if (now - gYTNicoLastBubblePositionScan < 0.75) return;
    gYTNicoBubblePositionScanQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gYTNicoBubblePositionScanQueued = NO;
        gYTNicoLastBubblePositionScan = CACurrentMediaTime();
        YTNicoApplyBubbleButtonPositionNow();
    });
}

%hook UIView

- (void)didMoveToWindow {
    %orig;
    // Only run a throttled scan when views are attached. Avoid hooking layoutSubviews;
    // that was too frequent and caused visible repeated repositioning.
    YTNicoApplyBubbleButtonPositionDebounced(0.25);
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        gYTNicoLastBubbleScreenSize = UIScreen.mainScreen.bounds.size;
        YTNicoApplyBubbleButtonPositionDebounced(0.6);
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            gYTNicoLastBubbleScreenSize = UIScreen.mainScreen.bounds.size;
            gYTNicoLastBubblePositionScan = 0;
            YTNicoApplyBubbleButtonPositionDebounced(0.35);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            gYTNicoLastBubblePositionScan = 0;
            YTNicoApplyBubbleButtonPositionDebounced(0.35);
        }];
    });
}

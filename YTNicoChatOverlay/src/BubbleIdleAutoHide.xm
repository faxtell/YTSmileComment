#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSTimeInterval const kYTNicoBubbleIdleSeconds = 5.0;
static BOOL gYTNicoBubbleIdleHideInstalled = NO;
static NSInteger gYTNicoBubbleIdleGeneration = 0;
static CFTimeInterval gYTNicoLastBubbleScan = 0;
static BOOL gYTNicoBubbleScanQueued = NO;

static BOOL YTNicoContainsAnyForIdleBubble(NSString *s, NSArray<NSString *> *needles) {
    for (NSString *n in needles) {
        if ([s rangeOfString:n options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL YTNicoViewIsInPiPForIdleBubble(UIView *view) {
    NSArray<NSString *> *pipNeedles = @[@"PiP", @"PIP", @"PictureInPicture", @"Picture", @"Pinnable"];
    for (UIView *v = view; v; v = v.superview) {
        if (YTNicoContainsAnyForIdleBubble(NSStringFromClass(v.class), pipNeedles)) return YES;
    }
    return NO;
}

static NSString *YTNicoIdleBubbleText(UIView *view) {
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

static BOOL YTNicoLooksLikeIdleBubbleButton(UIView *view) {
    if (![view isKindOfClass:UIButton.class]) return NO;
    if (YTNicoViewIsInPiPForIdleBubble(view)) return NO;

    NSString *text = YTNicoIdleBubbleText(view);
    if (YTNicoContainsAnyForIdleBubble(text, @[@"YTNico", @"Nico", @"Bubble", @"コメント", @"吹き出し", @"💬"])) return YES;

    CGRect f = [view.superview convertRect:view.frame toView:nil];
    CGFloat w = CGRectGetWidth(f), h = CGRectGetHeight(f);
    BOOL floatingSize = w >= 34 && w <= 92 && h >= 34 && h <= 92 && fabs(w - h) <= 30;
    BOOL nearEdge = CGRectGetMinX(f) < 130 || CGRectGetMaxX(f) > UIScreen.mainScreen.bounds.size.width - 130 || CGRectGetMinY(f) < 180;
    return floatingSize && nearEdge;
}

static void YTNicoScanBubbleButtons(UIView *view, NSMutableArray<UIView *> *out, NSUInteger *scanCount) {
    if (!view || *scanCount > 450) return;
    (*scanCount)++;
    if (YTNicoLooksLikeIdleBubbleButton(view)) [out addObject:view];
    for (UIView *sub in view.subviews) YTNicoScanBubbleButtons(sub, out, scanCount);
}

static NSArray<UIView *> *YTNicoCurrentBubbleButtons(void) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    NSUInteger scanCount = 0;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        YTNicoScanBubbleButtons(window, buttons, &scanCount);
        if (buttons.count >= 4 || scanCount > 450) break;
    }
    return buttons;
}

static void YTNicoSetBubbleAlpha(CGFloat alpha, BOOL animated) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<UIView *> *buttons = YTNicoCurrentBubbleButtons();
        void (^changes)(void) = ^{
            for (UIView *button in buttons) {
                if (button.hidden && alpha > 0.0) button.hidden = NO;
                button.alpha = alpha;
            }
        };
        if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
        else changes();
    });
}

static void YTNicoScheduleBubbleIdleHide(void) {
    NSInteger generation = ++gYTNicoBubbleIdleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYTNicoBubbleIdleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gYTNicoBubbleIdleGeneration) return;
        YTNicoSetBubbleAlpha(0.0, YES);
    });
}

static void YTNicoUserTouchedScreen(void) {
    YTNicoSetBubbleAlpha(1.0, YES);
    YTNicoScheduleBubbleIdleHide();
}

static void YTNicoInstallIdleTouchOverlay(void) {
    if (gYTNicoBubbleIdleHideInstalled) return;
    gYTNicoBubbleIdleHideInstalled = YES;

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        YTNicoUserTouchedScreen();
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        YTNicoUserTouchedScreen();
    }];

    YTNicoUserTouchedScreen();
}

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return;
    BOOL relevant = NO;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseEnded) {
            relevant = YES;
            break;
        }
    }
    if (relevant) YTNicoUserTouchedScreen();
}

%end

%hook UIView

- (void)didMoveToWindow {
    %orig;
    CFTimeInterval now = CACurrentMediaTime();
    if (gYTNicoBubbleScanQueued || now - gYTNicoLastBubbleScan < 1.0) return;
    gYTNicoBubbleScanQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gYTNicoBubbleScanQueued = NO;
        gYTNicoLastBubbleScan = CACurrentMediaTime();
        YTNicoSetBubbleAlpha(1.0, NO);
        YTNicoScheduleBubbleIdleHide();
    });
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        YTNicoInstallIdleTouchOverlay();
    });
}

#import <UIKit/UIKit.h>

static NSTimeInterval const kYTNicoBubbleStrictIdleSeconds = 5.0;
static NSInteger gYTNicoBubbleStrictGeneration = 0;
static BOOL gYTNicoBubbleStrictInstalled = NO;

static BOOL YTNicoStrictContains(NSString *s, NSString *needle) {
    return [s rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSString *YTNicoStrictBubbleText(UIView *view) {
    NSMutableString *text = [NSMutableString string];
    NSString *className = NSStringFromClass(view.class) ?: @"";
    if (className.length) [text appendFormat:@" %@", className];
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

static BOOL YTNicoIsStrictBubbleButton(UIView *view) {
    if (![view isKindOfClass:UIButton.class]) return NO;
    NSString *text = YTNicoStrictBubbleText(view);

    // Strict mode: do not use generic round-button geometry. That caused unrelated
    // circular buttons to be touched. Only target buttons that clearly look like this tweak.
    if (YTNicoStrictContains(text, @"YTNico")) return YES;
    if (YTNicoStrictContains(text, @"Nico")) return YES;
    if (YTNicoStrictContains(text, @"吹き出し")) return YES;
    if (YTNicoStrictContains(text, @"コメント表示")) return YES;
    if (YTNicoStrictContains(text, @"💬")) return YES;
    return NO;
}

static void YTNicoFindStrictBubbleButtons(UIView *view, NSMutableArray<UIView *> *out, NSUInteger *scanned) {
    if (!view || *scanned > 600) return;
    (*scanned)++;
    if (YTNicoIsStrictBubbleButton(view)) [out addObject:view];
    for (UIView *sub in view.subviews) YTNicoFindStrictBubbleButtons(sub, out, scanned);
}

static NSArray<UIView *> *YTNicoStrictBubbleButtons(void) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    NSUInteger scanned = 0;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        YTNicoFindStrictBubbleButtons(window, buttons, &scanned);
        if (buttons.count >= 3 || scanned > 600) break;
    }
    return buttons;
}

static void YTNicoSetStrictBubbleAlpha(CGFloat alpha, BOOL animated) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<UIView *> *buttons = YTNicoStrictBubbleButtons();
        if (buttons.count == 0) return;
        void (^changes)(void) = ^{
            for (UIView *button in buttons) {
                button.hidden = NO;
                button.userInteractionEnabled = YES;
                button.alpha = alpha;
            }
        };
        if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
        else changes();
    });
}

static void YTNicoScheduleStrictBubbleHide(void) {
    NSInteger gen = ++gYTNicoBubbleStrictGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYTNicoBubbleStrictIdleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != gYTNicoBubbleStrictGeneration) return;
        YTNicoSetStrictBubbleAlpha(0.0, YES);
    });
}

static void YTNicoStrictUserInteraction(void) {
    YTNicoSetStrictBubbleAlpha(1.0, YES);
    YTNicoScheduleStrictBubbleHide();
}

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseEnded) {
            YTNicoStrictUserInteraction();
            break;
        }
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gYTNicoBubbleStrictInstalled) return;
        gYTNicoBubbleStrictInstalled = YES;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoStrictUserInteraction();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoStrictUserInteraction();
        }];
        YTNicoStrictUserInteraction();
    });
}

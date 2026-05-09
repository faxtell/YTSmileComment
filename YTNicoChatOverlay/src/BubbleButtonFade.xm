#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoBubbleFadeArmedKey = &kYTNicoBubbleFadeArmedKey;
static NSTimeInterval const kYTNicoBubbleFullHideDelay = 5.0;
static NSInteger gYTNicoBubbleFadeGeneration = 0;
static NSHashTable<UIButton *> *gYTNicoBubbleButtons = nil;
static CFTimeInterval gYTNicoLastBubbleScan = 0;
static BOOL gYTNicoBubbleScanQueued = NO;

static BOOL YTNicoIsYouTubeProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTNicoBubbleStringContains(NSString *s, NSString *needle) {
    return [s rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSString *YTNicoBubbleButtonText(UIButton *button) {
    NSMutableString *s = [NSMutableString string];
    NSString *className = NSStringFromClass(button.class) ?: @"";
    if (className.length) [s appendFormat:@" %@", className];
    NSString *title = [button titleForState:UIControlStateNormal] ?: button.currentTitle ?: @"";
    if (title.length) [s appendFormat:@" %@", title];
    NSString *attributed = button.currentAttributedTitle.string ?: @"";
    if (attributed.length) [s appendFormat:@" %@", attributed];
    NSString *accessibility = button.accessibilityLabel ?: @"";
    if (accessibility.length) [s appendFormat:@" %@", accessibility];
    NSString *identifier = button.accessibilityIdentifier ?: @"";
    if (identifier.length) [s appendFormat:@" %@", identifier];
    NSString *imageName = button.currentImage.accessibilityIdentifier ?: @"";
    if (imageName.length) [s appendFormat:@" %@", imageName];
    return s;
}

static BOOL YTNicoButtonInTutorialOrPiP(UIButton *button) {
    for (UIView *v = button; v; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if (YTNicoBubbleStringContains(name, @"Tutorial")) return YES;
        if (YTNicoBubbleStringContains(name, @"PiP") || YTNicoBubbleStringContains(name, @"PictureInPicture")) return YES;
    }
    return NO;
}

static BOOL YTNicoIsBubbleButton(UIButton *button) {
    if (!YTNicoIsYouTubeProcess()) return NO;
    if (![button isKindOfClass:UIButton.class]) return NO;
    if (YTNicoButtonInTutorialOrPiP(button)) return NO;

    NSString *text = YTNicoBubbleButtonText(button);
    BOOL explicitMatch = NO;
    if (YTNicoBubbleStringContains(text, @"💬")) explicitMatch = YES;
    if (YTNicoBubbleStringContains(text, @"💭")) explicitMatch = YES;
    if (YTNicoBubbleStringContains(text, @"YTNico")) explicitMatch = YES;
    if (YTNicoBubbleStringContains(text, @"Nico")) explicitMatch = YES;
    if (YTNicoBubbleStringContains(text, @"吹き出し")) explicitMatch = YES;
    if (YTNicoBubbleStringContains(text, @"コメント表示")) explicitMatch = YES;
    if (explicitMatch) return YES;

    // Fallback: our floating bubble is a small circular button. Keep this narrow to avoid
    // touching random YouTube controls.
    CGRect f = button.frame;
    CGFloat w = CGRectGetWidth(f), h = CGRectGetHeight(f);
    if (w < 34 || w > 64 || h < 34 || h > 64 || fabs(w - h) > 10) return NO;
    if (!button.superview || !button.window) return NO;
    CGRect screenFrame = [button.superview convertRect:button.frame toView:nil];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    BOOL nearFloatingEdge = CGRectGetMinX(screenFrame) < 96 || CGRectGetMaxX(screenFrame) > screenW - 96 || CGRectGetMaxY(screenFrame) > screenH - 140;
    if (!nearFloatingEdge) return NO;

    // Avoid common YouTube controls that are usually image-only but not our bubble.
    NSString *className = NSStringFromClass(button.class);
    if (YTNicoBubbleStringContains(className, @"YT")) return NO;
    return button.backgroundColor != nil || button.layer.cornerRadius >= 12.0;
}

static void YTNicoRegisterBubbleButton(UIButton *button) {
    if (!YTNicoIsBubbleButton(button)) return;
    if (!gYTNicoBubbleButtons) gYTNicoBubbleButtons = [NSHashTable weakObjectsHashTable];
    [gYTNicoBubbleButtons addObject:button];
    if (![objc_getAssociatedObject(button, kYTNicoBubbleFadeArmedKey) boolValue]) {
        objc_setAssociatedObject(button, kYTNicoBubbleFadeArmedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[DebugInspector shared] log:@"bubble full idle fade armed text=%@ frame=%@", YTNicoBubbleButtonText(button), NSStringFromCGRect(button.frame)];
    }
}

static void YTNicoScanBubbleButtonsInView(UIView *view, NSUInteger *scanned) {
    if (!view || *scanned > 800) return;
    (*scanned)++;
    if ([view isKindOfClass:UIButton.class]) YTNicoRegisterBubbleButton((UIButton *)view);
    for (UIView *sub in view.subviews) YTNicoScanBubbleButtonsInView(sub, scanned);
}

static void YTNicoScanForBubbleButtonsIfNeeded(void) {
    if (!YTNicoIsYouTubeProcess()) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (gYTNicoBubbleScanQueued || now - gYTNicoLastBubbleScan < 1.5) return;
    gYTNicoBubbleScanQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gYTNicoBubbleScanQueued = NO;
        gYTNicoLastBubbleScan = CACurrentMediaTime();
        NSUInteger scanned = 0;
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            YTNicoScanBubbleButtonsInView(window, &scanned);
            if (scanned > 800) break;
        }
    });
}

static NSArray<UIButton *> *YTNicoRegisteredBubbleButtons(void) {
    NSMutableArray<UIButton *> *alive = [NSMutableArray array];
    if (gYTNicoBubbleButtons) {
        for (UIButton *button in gYTNicoBubbleButtons) {
            if (YTNicoIsBubbleButton(button) && button.window) [alive addObject:button];
        }
    }
    if (alive.count == 0) YTNicoScanForBubbleButtonsIfNeeded();
    return alive;
}

static void YTNicoSetRegisteredBubbleAlpha(CGFloat alpha, BOOL animated) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<UIButton *> *buttons = YTNicoRegisteredBubbleButtons();
        if (buttons.count == 0) return;
        void (^changes)(void) = ^{
            for (UIButton *button in buttons) {
                button.hidden = NO;
                button.userInteractionEnabled = YES;
                button.alpha = alpha;
            }
        };
        if (animated) {
            [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
        } else {
            changes();
        }
    });
}

static void YTNicoScheduleBubbleFullHide(void) {
    NSInteger generation = ++gYTNicoBubbleFadeGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYTNicoBubbleFullHideDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gYTNicoBubbleFadeGeneration) return;
        YTNicoScanForBubbleButtonsIfNeeded();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != gYTNicoBubbleFadeGeneration) return;
            YTNicoSetRegisteredBubbleAlpha(0.0, YES);
        });
    });
}

static void YTNicoShowBubbleAndRestartIdleTimer(void) {
    if (!YTNicoIsYouTubeProcess()) return;
    YTNicoScanForBubbleButtonsIfNeeded();
    YTNicoSetRegisteredBubbleAlpha(0.96, YES);
    YTNicoScheduleBubbleFullHide();
}

%hook UIButton

- (void)didMoveToSuperview {
    %orig;
    YTNicoRegisterBubbleButton(self);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)didMoveToWindow {
    %orig;
    YTNicoRegisterBubbleButton(self);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    %orig(title, state);
    YTNicoRegisterBubbleButton(self);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    %orig(title, state);
    YTNicoRegisterBubbleButton(self);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
    %orig(touches, event);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig(touches, event);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig(touches, event);
    if (YTNicoIsBubbleButton(self)) YTNicoShowBubbleAndRestartIdleTimer();
}

%end

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (!YTNicoIsYouTubeProcess()) return;
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseEnded) {
            YTNicoShowBubbleAndRestartIdleTimer();
            break;
        }
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoIsYouTubeProcess()) return;
        gYTNicoBubbleButtons = [NSHashTable weakObjectsHashTable];
        YTNicoShowBubbleAndRestartIdleTimer();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoShowBubbleAndRestartIdleTimer();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoShowBubbleAndRestartIdleTimer();
        }];
    });
}

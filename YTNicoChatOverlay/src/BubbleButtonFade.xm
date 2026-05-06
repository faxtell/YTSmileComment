#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kYTNicoBubbleFadeArmedKey = &kYTNicoBubbleFadeArmedKey;
static NSTimeInterval const kYTNicoBubbleFullHideDelay = 5.0;
static NSInteger gYTNicoBubbleFadeGeneration = 0;
static NSHashTable<UIButton *> *gYTNicoBubbleButtons = nil;

static BOOL YTNicoIsYouTubeProcess(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTNicoIsBubbleButton(UIButton *button) {
    if (!YTNicoIsYouTubeProcess()) return NO;
    if (![button isKindOfClass:UIButton.class]) return NO;
    NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
    if (![title isEqualToString:@"💬"] && ![title isEqualToString:@"💭"]) return NO;
    CGRect f = button.frame;
    if (fabs(f.size.width - 44.0) > 10.0 || fabs(f.size.height - 44.0) > 10.0) return NO;
    return YES;
}

static void YTNicoRegisterBubbleButton(UIButton *button) {
    if (!YTNicoIsBubbleButton(button)) return;
    if (!gYTNicoBubbleButtons) gYTNicoBubbleButtons = [NSHashTable weakObjectsHashTable];
    [gYTNicoBubbleButtons addObject:button];
}

static NSArray<UIButton *> *YTNicoRegisteredBubbleButtons(void) {
    if (!gYTNicoBubbleButtons) return @[];
    NSMutableArray<UIButton *> *alive = [NSMutableArray array];
    for (UIButton *button in gYTNicoBubbleButtons) {
        if (YTNicoIsBubbleButton(button) && button.window) [alive addObject:button];
    }
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
        YTNicoSetRegisteredBubbleAlpha(0.0, YES);
    });
}

static void YTNicoShowBubbleAndRestartIdleTimer(void) {
    if (!YTNicoIsYouTubeProcess()) return;
    YTNicoSetRegisteredBubbleAlpha(0.96, YES);
    YTNicoScheduleBubbleFullHide();
}

%hook UIButton

- (void)didMoveToSuperview {
    %orig;
    if (!YTNicoIsBubbleButton(self)) return;
    YTNicoRegisterBubbleButton(self);
    if (![objc_getAssociatedObject(self, kYTNicoBubbleFadeArmedKey) boolValue]) {
        objc_setAssociatedObject(self, kYTNicoBubbleFadeArmedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [[DebugInspector shared] log:@"bubble full idle fade armed"];
    }
    YTNicoShowBubbleAndRestartIdleTimer();
}

- (void)didMoveToWindow {
    %orig;
    if (!YTNicoIsBubbleButton(self)) return;
    YTNicoRegisterBubbleButton(self);
    YTNicoShowBubbleAndRestartIdleTimer();
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
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoShowBubbleAndRestartIdleTimer();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoShowBubbleAndRestartIdleTimer();
        }];
    });
}

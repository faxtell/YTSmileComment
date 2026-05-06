#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTNicoController : NSObject
@property (nonatomic, weak) UIWindow *window;
- (void)ensureToggleButton;
- (void)updateToggleButtonAppearance;
@end

static NSTimeInterval const kYTNicoControllerBubbleIdleSeconds = 5.0;
static const void *kYTNicoControllerBubbleRegisteredKey = &kYTNicoControllerBubbleRegisteredKey;
static const void *kYTNicoControllerBubbleIdleHiddenKey = &kYTNicoControllerBubbleIdleHiddenKey;
static NSInteger gYTNicoControllerBubbleGeneration = 0;
static NSHashTable<UIButton *> *gYTNicoControllerBubbleButtons = nil;

static BOOL YTNicoControllerBubbleIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoControllerButtonTitle(UIButton *button) {
    NSString *title = [button titleForState:UIControlStateNormal] ?: button.currentTitle ?: @"";
    if (title.length == 0) title = button.currentAttributedTitle.string ?: @"";
    return title ?: @"";
}

static BOOL YTNicoControllerButtonLooksLikeBubble(UIButton *button) {
    if (!button || ![button isKindOfClass:UIButton.class]) return NO;
    NSString *title = YTNicoControllerButtonTitle(button);
    if ([title isEqualToString:@"💬"] || [title isEqualToString:@"💭"]) return YES;
    NSString *label = button.accessibilityLabel ?: @"";
    if ([label rangeOfString:@"YTNico" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    if ([label rangeOfString:@"吹き出し"].location != NSNotFound) return YES;
    return NO;
}

static UIButton *YTNicoFindBubbleButtonForController(YTNicoController *controller) {
    UIWindow *window = controller.window;
    if (!window) return nil;

    // The original controller adds the bubble button directly to the host window.
    for (UIView *sub in window.subviews.reverseObjectEnumerator) {
        if (![sub isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)sub;
        if (YTNicoControllerButtonLooksLikeBubble(button)) return button;
    }

    // Fallback: exact frame pattern from ensureToggleButton: 44x44 around y=96.
    for (UIView *sub in window.subviews.reverseObjectEnumerator) {
        if (![sub isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)sub;
        CGRect f = button.frame;
        BOOL sizeMatch = fabs(f.size.width - 44.0) <= 4.0 && fabs(f.size.height - 44.0) <= 4.0;
        BOOL yMatch = fabs(f.origin.y - 96.0) <= 28.0;
        BOOL rightSide = f.origin.x >= window.bounds.size.width - 92.0;
        if (sizeMatch && yMatch && rightSide) return button;
    }
    return nil;
}

static CGFloat YTNicoVisibleAlphaForBubble(UIButton *button) {
    NSString *title = YTNicoControllerButtonTitle(button);
    if ([title isEqualToString:@"💭"]) return 0.45;
    return 0.92;
}

static NSArray<UIButton *> *YTNicoAliveControllerBubbleButtons(void) {
    if (!gYTNicoControllerBubbleButtons) return @[];
    NSMutableArray<UIButton *> *alive = [NSMutableArray array];
    for (UIButton *button in gYTNicoControllerBubbleButtons) {
        if (button.window && YTNicoControllerButtonLooksLikeBubble(button)) [alive addObject:button];
    }
    return alive;
}

static void YTNicoApplyBubbleAlpha(UIButton *button, CGFloat alpha, BOOL animated) {
    if (!button) return;
    void (^changes)(void) = ^{
        button.hidden = NO;
        button.userInteractionEnabled = YES;
        button.alpha = alpha;
    };
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil];
    } else {
        changes();
    }
}

static void YTNicoHideRegisteredControllerBubbles(void) {
    for (UIButton *button in YTNicoAliveControllerBubbleButtons()) {
        objc_setAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTNicoApplyBubbleAlpha(button, 0.0, YES);
    }
}

static void YTNicoScheduleControllerBubbleHide(void) {
    NSInteger generation = ++gYTNicoControllerBubbleGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kYTNicoControllerBubbleIdleSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != gYTNicoControllerBubbleGeneration) return;
        YTNicoHideRegisteredControllerBubbles();
    });
}

static void YTNicoShowRegisteredControllerBubbles(void) {
    if (!YTNicoControllerBubbleIsYouTube()) return;
    for (UIButton *button in YTNicoAliveControllerBubbleButtons()) {
        objc_setAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTNicoApplyBubbleAlpha(button, YTNicoVisibleAlphaForBubble(button), YES);
    }
    YTNicoScheduleControllerBubbleHide();
}

static void YTNicoRegisterControllerBubbleButton(UIButton *button) {
    if (!YTNicoControllerBubbleIsYouTube() || !YTNicoControllerButtonLooksLikeBubble(button)) return;
    if (!gYTNicoControllerBubbleButtons) gYTNicoControllerBubbleButtons = [NSHashTable weakObjectsHashTable];
    [gYTNicoControllerBubbleButtons addObject:button];
    button.accessibilityLabel = @"YTNico コメント表示 吹き出し";
    if (![objc_getAssociatedObject(button, kYTNicoControllerBubbleRegisteredKey) boolValue]) {
        objc_setAssociatedObject(button, kYTNicoControllerBubbleRegisteredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    YTNicoShowRegisteredControllerBubbles();
}

%hook YTNicoController

- (void)ensureToggleButton {
    %orig;
    UIButton *button = YTNicoFindBubbleButtonForController(self);
    if (button) YTNicoRegisterControllerBubbleButton(button);
}

- (void)updateToggleButtonAppearance {
    %orig;
    UIButton *button = YTNicoFindBubbleButtonForController(self);
    if (!button) return;
    YTNicoRegisterControllerBubbleButton(button);
    if ([objc_getAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey) boolValue]) {
        button.alpha = 0.0;
    }
}

%end

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (!YTNicoControllerBubbleIsYouTube()) return;
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved || touch.phase == UITouchPhaseEnded) {
            YTNicoShowRegisteredControllerBubbles();
            break;
        }
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoControllerBubbleIsYouTube()) return;
        gYTNicoControllerBubbleButtons = [NSHashTable weakObjectsHashTable];
    });
}

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTNicoController : NSObject
@property (nonatomic, weak) UIWindow *window;
- (void)ensureToggleButton;
- (void)updateToggleButtonAppearance;
@end

static NSString * const kYTNicoBubblePrefsDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoBubblePosXKey = @"bubble.position.xRatio";
static NSString * const kYTNicoBubblePosYKey = @"bubble.position.yRatio";
static NSTimeInterval const kYTNicoControllerBubbleIdleSeconds = 5.0;
static const void *kYTNicoControllerBubbleRegisteredKey = &kYTNicoControllerBubbleRegisteredKey;
static const void *kYTNicoControllerBubbleIdleHiddenKey = &kYTNicoControllerBubbleIdleHiddenKey;
static const void *kYTNicoControllerBubblePanKey = &kYTNicoControllerBubblePanKey;
static NSInteger gYTNicoControllerBubbleGeneration = 0;
static NSHashTable<UIButton *> *gYTNicoControllerBubbleButtons = nil;

static BOOL YTNicoControllerBubbleIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSUserDefaults *YTNicoBubblePrefs(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kYTNicoBubblePrefsDomain] ?: NSUserDefaults.standardUserDefaults;
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

    for (UIView *sub in window.subviews.reverseObjectEnumerator) {
        if (![sub isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)sub;
        if (YTNicoControllerButtonLooksLikeBubble(button)) return button;
    }

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

static CGRect YTNicoClampBubbleFrame(UIButton *button, CGRect frame) {
    UIView *host = button.superview;
    if (!host) return frame;
    UIEdgeInsets inset = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) inset = host.safeAreaInsets;
    CGFloat margin = 6.0;
    CGFloat minX = inset.left + margin;
    CGFloat minY = inset.top + margin;
    CGFloat maxX = host.bounds.size.width - inset.right - margin - frame.size.width;
    CGFloat maxY = host.bounds.size.height - inset.bottom - margin - frame.size.height;
    if (maxX < minX) maxX = minX;
    if (maxY < minY) maxY = minY;
    frame.origin.x = MIN(MAX(frame.origin.x, minX), maxX);
    frame.origin.y = MIN(MAX(frame.origin.y, minY), maxY);
    return CGRectIntegral(frame);
}

static void YTNicoSaveBubblePosition(UIButton *button) {
    UIView *host = button.superview;
    if (!host || host.bounds.size.width <= 0 || host.bounds.size.height <= 0) return;
    CGFloat x = (CGRectGetMidX(button.frame) / MAX(host.bounds.size.width, 1.0));
    CGFloat y = (CGRectGetMidY(button.frame) / MAX(host.bounds.size.height, 1.0));
    x = MIN(MAX(x, 0.0), 1.0);
    y = MIN(MAX(y, 0.0), 1.0);
    NSUserDefaults *d = YTNicoBubblePrefs();
    [d setDouble:x forKey:kYTNicoBubblePosXKey];
    [d setDouble:y forKey:kYTNicoBubblePosYKey];
    [d synchronize];
}

static BOOL YTNicoHasSavedBubblePosition(void) {
    NSUserDefaults *d = YTNicoBubblePrefs();
    return [d objectForKey:kYTNicoBubblePosXKey] != nil && [d objectForKey:kYTNicoBubblePosYKey] != nil;
}

static void YTNicoApplySavedBubblePosition(UIButton *button) {
    if (!YTNicoHasSavedBubblePosition()) return;
    UIView *host = button.superview;
    if (!host || host.bounds.size.width <= 0 || host.bounds.size.height <= 0) return;
    NSUserDefaults *d = YTNicoBubblePrefs();
    CGFloat xRatio = MIN(MAX([d doubleForKey:kYTNicoBubblePosXKey], 0.0), 1.0);
    CGFloat yRatio = MIN(MAX([d doubleForKey:kYTNicoBubblePosYKey], 0.0), 1.0);
    CGSize size = button.frame.size;
    if (size.width <= 0 || size.height <= 0) size = CGSizeMake(44, 44);
    CGFloat centerX = host.bounds.size.width * xRatio;
    CGFloat centerY = host.bounds.size.height * yRatio;
    CGRect frame = CGRectMake(centerX - size.width / 2.0, centerY - size.height / 2.0, size.width, size.height);
    frame = YTNicoClampBubbleFrame(button, frame);
    [UIView performWithoutAnimation:^{ button.frame = frame; }];
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

static void YTNicoShowRegisteredControllerBubblesFromUserTouch(void) {
    if (!YTNicoControllerBubbleIsYouTube()) return;
    for (UIButton *button in YTNicoAliveControllerBubbleButtons()) {
        objc_setAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTNicoApplyBubbleAlpha(button, YTNicoVisibleAlphaForBubble(button), YES);
    }
    YTNicoScheduleControllerBubbleHide();
}

static void YTNicoKeepBubbleCurrentIdleState(UIButton *button) {
    if (!button) return;
    if ([objc_getAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey) boolValue]) {
        button.hidden = NO;
        button.userInteractionEnabled = YES;
        button.alpha = 0.0;
    }
}

@interface YTNicoBubblePanHandler : NSObject <UIGestureRecognizerDelegate>
@end

@implementation YTNicoBubblePanHandler
- (void)ytnico_handleBubblePan:(UIPanGestureRecognizer *)pan {
    UIButton *button = (UIButton *)pan.view;
    if (![button isKindOfClass:UIButton.class]) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        YTNicoShowRegisteredControllerBubblesFromUserTouch();
    }
    CGPoint translation = [pan translationInView:button.superview];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGRect frame = button.frame;
        frame.origin.x += translation.x;
        frame.origin.y += translation.y;
        frame = YTNicoClampBubbleFrame(button, frame);
        button.frame = frame;
        [pan setTranslation:CGPointZero inView:button.superview];
    }
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        YTNicoSaveBubblePosition(button);
        YTNicoShowRegisteredControllerBubblesFromUserTouch();
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

static void YTNicoInstallBubblePan(UIButton *button) {
    if (!button || objc_getAssociatedObject(button, kYTNicoControllerBubblePanKey)) return;
    YTNicoBubblePanHandler *handler = [YTNicoBubblePanHandler new];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(ytnico_handleBubblePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = NO;
    pan.delegate = handler;
    [button addGestureRecognizer:pan];
    objc_setAssociatedObject(button, kYTNicoControllerBubblePanKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTNicoRegisterControllerBubbleButton(UIButton *button) {
    if (!YTNicoControllerBubbleIsYouTube() || !YTNicoControllerButtonLooksLikeBubble(button)) return;
    if (!gYTNicoControllerBubbleButtons) gYTNicoControllerBubbleButtons = [NSHashTable weakObjectsHashTable];
    [gYTNicoControllerBubbleButtons addObject:button];
    button.accessibilityLabel = @"YTNico コメント表示 吹き出し";
    YTNicoInstallBubblePan(button);
    YTNicoApplySavedBubblePosition(button);
    BOOL firstRegister = ![objc_getAssociatedObject(button, kYTNicoControllerBubbleRegisteredKey) boolValue];
    if (firstRegister) {
        objc_setAssociatedObject(button, kYTNicoControllerBubbleRegisteredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(button, kYTNicoControllerBubbleIdleHiddenKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YTNicoScheduleControllerBubbleHide();
    } else {
        YTNicoKeepBubbleCurrentIdleState(button);
    }
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
    YTNicoApplySavedBubblePosition(button);
    YTNicoKeepBubbleCurrentIdleState(button);
}

%end

%hook UIWindow

- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (!YTNicoControllerBubbleIsYouTube()) return;
    NSSet<UITouch *> *touches = [event allTouches];
    if (touches.count == 0) return;
    for (UITouch *touch in touches) {
        if (touch.phase == UITouchPhaseBegan) {
            YTNicoShowRegisteredControllerBubblesFromUserTouch();
            break;
        }
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoControllerBubbleIsYouTube()) return;
        gYTNicoControllerBubbleButtons = [NSHashTable weakObjectsHashTable];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            for (UIButton *button in YTNicoAliveControllerBubbleButtons()) {
                YTNicoApplySavedBubblePosition(button);
                YTNicoKeepBubbleCurrentIdleState(button);
            }
        }];
    });
}

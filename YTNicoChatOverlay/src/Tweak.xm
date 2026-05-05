#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NicoChatOverlayView.h"
#import "NicoChatMessage.h"
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kOverlayKey = &kOverlayKey;
static const void *kAdapterKey = &kAdapterKey;
static const void *kButtonKey = &kButtonKey;
static const void *kCtlKey = &kCtlKey;

@interface YTNicoController : NSObject <YouTubeChatAdapterDelegate>
@property (nonatomic, weak) UIWindow *window;
@end

@implementation YTNicoController

- (instancetype)initWithWindow:(UIWindow *)window {
    if ((self = [super init])) {
        _window = window;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSettings) name:kYTNicoSettingsChangedNotification object:nil];
        [self setup];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    [adapter stopObserving];
}

- (void)reloadSettings {
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (![SettingsManager shared].enabled) [overlay clearComments];
    [self updateToggleButtonAppearance];
    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    [adapter stopObserving];
    [self setup];
}

- (void)setup {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setup]; });
        return;
    }
    if (!self.window || self.window.hidden || self.window.alpha < 0.05) return;

    [self ensureOverlayAttached];
    [self ensureToggleButton];

    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    if (!adapter) {
        adapter = [YouTubeChatAdapter new];
        adapter.delegate = self;
        objc_setAssociatedObject(self, kAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [adapter startObservingInRootView:self.window];
}

#pragma mark - Overlay

- (NicoChatOverlayView *)overlayForTargetView:(UIView *)target frame:(CGRect)frame {
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay) {
        overlay = [[NicoChatOverlayView alloc] initWithFrame:frame];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = UIColor.clearColor;
        overlay.clipsToBounds = YES;
        overlay.layer.masksToBounds = YES;
        overlay.layer.zPosition = 9999;
        objc_setAssociatedObject(self, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != target) {
        [overlay removeFromSuperview];
        overlay.frame = frame;
        [target addSubview:overlay];
    } else if (!CGRectEqualToRect(overlay.frame, frame)) {
        overlay.frame = frame;
    }
    [target bringSubviewToFront:overlay];
    return overlay;
}

- (void)ensureFallbackOverlayAttached {
    if (!self.window) return;
    CGRect bounds = self.window.bounds;
    CGFloat h = MIN(bounds.size.height, MAX(160.0, bounds.size.width * 9.0 / 16.0));
    CGRect frame = CGRectMake(0, 0, bounds.size.width, h);
    [self overlayForTargetView:self.window frame:frame];
    [[DebugInspector shared] log:@"Attached fallback overlay frame=%@", NSStringFromCGRect(frame)];
}

- (void)ensureOverlayAttached {
    UIView *player = [self findBestPlayerCandidateInView:self.window];
    if (!player) {
        [[DebugInspector shared] log:@"No player candidate found in window; using fallback"];
        [self ensureFallbackOverlayAttached];
        return;
    }

    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (player == overlay || [player isKindOfClass:NicoChatOverlayView.class] || [player isKindOfClass:UIControl.class] || [player isKindOfClass:UIWindow.class]) {
        [[DebugInspector shared] log:@"Rejected unsafe player candidate %@; using fallback", NSStringFromClass(player.class)];
        [self ensureFallbackOverlayAttached];
        return;
    }

    if (overlay && (player == overlay || [player isDescendantOfView:overlay])) {
        [self ensureFallbackOverlayAttached];
        return;
    }

    [self overlayForTargetView:player frame:player.bounds];
    player.clipsToBounds = YES;
}

- (UIView *)findBestPlayerCandidateInView:(UIView *)root {
    if (!root) return nil;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    [self collectPlayerCandidatesFromView:root into:candidates];

    UIView *bestView = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (UIView *candidate in candidates) {
        CGFloat score = [self scorePlayerCandidate:candidate];
        if (score > bestScore) {
            bestScore = score;
            bestView = candidate;
        }
    }
    return bestView;
}

- (BOOL)shouldSkipPlayerCandidateView:(UIView *)view {
    if (!view) return YES;
    if ([view isKindOfClass:NicoChatOverlayView.class]) return YES;
    if ([view isKindOfClass:UIControl.class]) return YES;
    if ([view isKindOfClass:UIWindow.class]) return YES;
    NSString *className = NSStringFromClass(view.class).lowercaseString;
    if ([className containsString:@"comment"]) return YES;
    if ([className containsString:@"chat"]) return YES;
    if ([className containsString:@"caption"]) return YES;
    if ([className containsString:@"subtitle"]) return YES;
    return NO;
}

- (void)collectPlayerCandidatesFromView:(UIView *)view into:(NSMutableArray<UIView *> *)candidates {
    if (!view || view.hidden || view.alpha < 0.05) return;
    if (view.bounds.size.width < 120 || view.bounds.size.height < 70) return;

    if (![self shouldSkipPlayerCandidateView:view]) {
        CGRect rect = [view convertRect:view.bounds toView:nil];
        if (!CGRectIsEmpty(rect) && !CGRectIsInfinite(rect)) {
            CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
            CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
            CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
            BOOL portraitLikePlayer = (ratio > 1.35 && ratio < 2.20 && rect.size.width >= screenW * 0.60 && rect.origin.y <= screenH * 0.55);
            BOOL fullscreenLandscapePlayer = (ratio > 1.20 && ratio < 2.50 && rect.size.width >= screenW * 0.80 && rect.size.height >= screenH * 0.42);
            if (portraitLikePlayer || fullscreenLandscapePlayer) [candidates addObject:view];
        }
    }

    for (UIView *subview in view.subviews) [self collectPlayerCandidatesFromView:subview into:candidates];
}

- (CGFloat)scorePlayerCandidate:(UIView *)view {
    CGRect rect = [view convertRect:view.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
    CGFloat aspectDelta = fabs(ratio - (16.0 / 9.0));
    CGFloat widthScore = MIN(rect.size.width / MAX(screen.width, 1.0), 1.2) * 40.0;
    CGFloat topBias = (rect.origin.y <= screen.height * 0.25) ? 22.0 : ((rect.origin.y <= screen.height * 0.55) ? 8.0 : -35.0);
    CGFloat aspectScore = MAX(0.0, 45.0 - aspectDelta * 70.0);
    CGFloat fullscreenBonus = (rect.size.width >= screen.width * 0.95 && ratio > 1.20) ? 14.0 : 0.0;
    CGFloat clutterPenalty = view.subviews.count > 90 ? -14.0 : 0.0;
    return widthScore + topBias + aspectScore + fullscreenBonus + clutterPenalty;
}

#pragma mark - Floating controls

- (void)ensureToggleButton {
    UIWindow *hostView = self.window;
    UIButton *button = objc_getAssociatedObject(self, kButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(MAX(12.0, hostView.bounds.size.width - 58.0), 96.0, 44.0, 44.0);
        button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        button.layer.cornerRadius = 22.0;
        button.layer.masksToBounds = YES;
        button.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
        [button setTitle:@"💬" forState:UIControlStateNormal];
        [button addTarget:self action:@selector(toggleOverlayEnabled) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleSettingsLongPress:)];
        longPress.minimumPressDuration = 0.45;
        [button addGestureRecognizer:longPress];
        objc_setAssociatedObject(self, kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (button.superview != hostView) {
        [button removeFromSuperview];
        [hostView addSubview:button];
    }
    button.frame = CGRectMake(MAX(12.0, hostView.bounds.size.width - 58.0), 96.0, 44.0, 44.0);
    [hostView bringSubviewToFront:button];
    [self updateToggleButtonAppearance];
}

- (void)updateToggleButtonAppearance {
    UIButton *button = objc_getAssociatedObject(self, kButtonKey);
    if (!button) return;
    BOOL enabled = [SettingsManager shared].enabled;
    button.alpha = enabled ? 0.92 : 0.45;
    button.backgroundColor = enabled ? [[UIColor blackColor] colorWithAlphaComponent:0.62] : [[UIColor grayColor] colorWithAlphaComponent:0.48];
    [button setTitle:enabled ? @"💬" : @"💭" forState:UIControlStateNormal];
    [button setTintColor:UIColor.whiteColor];
}

- (void)toggleOverlayEnabled {
    SettingsManager *settings = [SettingsManager shared];
    [settings setEnabled:!settings.enabled];
}

- (void)handleSettingsLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self presentSettingsPanelFromView:gesture.view ?: self.window];
    }
}

- (UIViewController *)visiblePresenter {
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

- (void)emitDisplayTestComment {
    [self ensureOverlayAttached];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:NSUUID.UUID.UUIDString authorName:@"YTNico" text:@"表示テスト: これが流れればOverlayは正常です" timestamp:NSDate.date];
    [overlay enqueueMessage:msg];
}

- (void)presentSettingsPanelFromView:(UIView *)sourceView {
    SettingsManager *s = [SettingsManager shared];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"YT Nico Chat Overlay" message:@"短押し: 表示/非表示\n長押し: この設定" preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"表示テストコメントを流す" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [weakSelf emitDisplayTestComment]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:(s.enabled ? @"コメント表示をOFF" : @"コメント表示をON") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setEnabled:!s.enabled]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:(s.showAuthorName ? @"投稿者名を非表示" : @"投稿者名を表示") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setShowAuthorName:!s.showAuthorName]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"文字サイズ +  現在 %.0f", s.fontSize] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setFontSize:s.fontSize + 2.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"文字サイズ -  現在 %.0f", s.fontSize] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setFontSize:s.fontSize - 2.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"流れる速度 +  現在 %.0f", s.speed] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setSpeed:s.speed + 20.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"流れる速度 -  現在 %.0f", s.speed] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setSpeed:s.speed - 20.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"表示行数 +  現在 %ld", (long)s.maxLines] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMaxLines:s.maxLines + 1]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"表示行数 -  現在 %ld", (long)s.maxLines] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMaxLines:s.maxLines - 1]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"透明度切替  現在 %.0f%%", s.opacity * 100.0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { CGFloat next = s.opacity >= 0.9 ? 0.55 : (s.opacity >= 0.7 ? 0.9 : 0.75); [s setOpacity:next]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:(s.mockMode ? @"テストコメントをOFF" : @"テストコメントをON") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMockMode:!s.mockMode]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"今流れているコメントを消す" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { NicoChatOverlayView *overlay = objc_getAssociatedObject(weakSelf, kOverlayKey); [overlay clearComments]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) { popover.sourceView = sourceView; popover.sourceRect = sourceView.bounds; popover.permittedArrowDirections = UIPopoverArrowDirectionAny; }
    [[self visiblePresenter] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Chat delegate

- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message {
    if (!message || message.text.length == 0 || ![SettingsManager shared].enabled) return;
    [self ensureOverlayAttached];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay) [self ensureFallbackOverlayAttached];
    overlay = objc_getAssociatedObject(self, kOverlayKey);
    [overlay enqueueMessage:message];
}
@end

static void YTNicoEnsureControllerForWindow(UIWindow *window) {
    if (!window || ![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    YTNicoController *ctl = objc_getAssociatedObject(window, kCtlKey);
    if (!ctl) {
        ctl = [[YTNicoController alloc] initWithWindow:window];
        objc_setAssociatedObject(window, kCtlKey, ctl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        [ctl setup];
    }
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated { %orig; YTNicoEnsureControllerForWindow(self.view.window); }
- (void)viewDidLayoutSubviews { %orig; YTNicoEnsureControllerForWindow(self.view.window); }
%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) [[DebugInspector shared] log:@"YTNico loaded"];
    }
}

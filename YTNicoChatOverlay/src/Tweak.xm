#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NicoChatOverlayView.h"
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kOverlayKey = &kOverlayKey;
static const void *kAdapterKey = &kAdapterKey;
static const void *kButtonKey = &kButtonKey;
static const void *kCtlKey = &kCtlKey;

@interface YTNicoController : NSObject <YouTubeChatAdapterDelegate>
@property (nonatomic, weak) UIViewController *hostVC;
@end

@implementation YTNicoController

- (instancetype)initWithVC:(UIViewController *)vc {
    if ((self = [super init])) {
        _hostVC = vc;
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
    if (!self.hostVC || !self.hostVC.view || !self.hostVC.view.window) return;

    [self ensureOverlayAttached];
    [self ensureToggleButton];

    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    if (!adapter) {
        adapter = [YouTubeChatAdapter new];
        adapter.delegate = self;
        objc_setAssociatedObject(self, kAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [adapter startObservingInRootView:self.hostVC.view];
}

#pragma mark - Overlay

- (void)ensureOverlayAttached {
    UIView *player = [self findBestPlayerCandidateInView:self.hostVC.view];
    if (!player) {
        [[DebugInspector shared] log:@"No player candidate found for %@", NSStringFromClass(self.hostVC.class)];
        return;
    }

    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay) {
        overlay = [[NicoChatOverlayView alloc] initWithFrame:player.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = UIColor.clearColor;
        overlay.clipsToBounds = YES;
        overlay.layer.masksToBounds = YES;
        overlay.layer.zPosition = 9999;
        objc_setAssociatedObject(self, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (overlay.superview != player) {
        [overlay removeFromSuperview];
        overlay.frame = player.bounds;
        [player addSubview:overlay];
        [[DebugInspector shared] log:@"Attached overlay to %@ frame=%@", NSStringFromClass(player.class), NSStringFromCGRect(player.frame)];
    } else if (!CGRectEqualToRect(overlay.frame, player.bounds)) {
        overlay.frame = player.bounds;
    }

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

- (void)collectPlayerCandidatesFromView:(UIView *)view into:(NSMutableArray<UIView *> *)candidates {
    if (!view || view.hidden || view.alpha < 0.05) return;
    if (view.bounds.size.width < 120 || view.bounds.size.height < 70) return;

    CGRect rect = [view convertRect:view.bounds toView:nil];
    if (!CGRectIsEmpty(rect) && !CGRectIsInfinite(rect)) {
        CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
        CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
        CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
        BOOL portraitLikePlayer = (ratio > 1.45 && ratio < 2.05 &&
                                   rect.size.width >= screenW * 0.70 &&
                                   rect.origin.y <= screenH * 0.48);
        BOOL fullscreenLandscapePlayer = (ratio > 1.35 && ratio < 2.25 &&
                                          rect.size.width >= screenW * 0.85 &&
                                          rect.size.height >= screenH * 0.45);
        if (portraitLikePlayer || fullscreenLandscapePlayer) [candidates addObject:view];
    }

    for (UIView *subview in view.subviews) [self collectPlayerCandidatesFromView:subview into:candidates];
}

- (CGFloat)scorePlayerCandidate:(UIView *)view {
    CGRect rect = [view convertRect:view.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
    CGFloat aspectDelta = fabs(ratio - (16.0 / 9.0));
    CGFloat widthScore = MIN(rect.size.width / MAX(screen.width, 1.0), 1.2) * 40.0;
    CGFloat topBias = (rect.origin.y <= screen.height * 0.25) ? 22.0 : ((rect.origin.y <= screen.height * 0.48) ? 8.0 : -28.0);
    CGFloat aspectScore = MAX(0.0, 45.0 - aspectDelta * 70.0);
    CGFloat fullscreenBonus = (rect.size.width >= screen.width * 0.95 && ratio > 1.35) ? 14.0 : 0.0;
    CGFloat clutterPenalty = view.subviews.count > 50 ? -12.0 : 0.0;
    return widthScore + topBias + aspectScore + fullscreenBonus + clutterPenalty;
}

#pragma mark - Floating controls

- (void)ensureToggleButton {
    UIView *hostView = self.hostVC.view;
    UIButton *button = objc_getAssociatedObject(self, kButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(MAX(12.0, hostView.bounds.size.width - 58.0), 88.0, 44.0, 44.0);
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
        [hostView bringSubviewToFront:button];
    }
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
        [self presentSettingsPanelFromView:gesture.view ?: self.hostVC.view];
    }
}

- (UIViewController *)visiblePresenter {
    UIViewController *presenter = self.hostVC;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

- (void)presentSettingsPanelFromView:(UIView *)sourceView {
    SettingsManager *s = [SettingsManager shared];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"YT Nico Chat Overlay"
                                                                   message:@"短押し: 表示/非表示\n長押し: この設定"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:(s.enabled ? @"コメント表示をOFF" : @"コメント表示をON") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setEnabled:!s.enabled]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:(s.showAuthorName ? @"投稿者名を非表示" : @"投稿者名を表示") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setShowAuthorName:!s.showAuthorName]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"文字サイズ +  現在 %.0f", s.fontSize] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setFontSize:s.fontSize + 2.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"文字サイズ -  現在 %.0f", s.fontSize] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setFontSize:s.fontSize - 2.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"流れる速度 +  現在 %.0f", s.speed] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setSpeed:s.speed + 20.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"流れる速度 -  現在 %.0f", s.speed] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setSpeed:s.speed - 20.0]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"表示行数 +  現在 %ld", (long)s.maxLines] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMaxLines:s.maxLines + 1]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"表示行数 -  現在 %ld", (long)s.maxLines] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMaxLines:s.maxLines - 1]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"透明度切替  現在 %.0f%%", s.opacity * 100.0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        CGFloat next = s.opacity >= 0.9 ? 0.55 : (s.opacity >= 0.7 ? 0.9 : 0.75);
        [s setOpacity:next];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:(s.mockMode ? @"テストコメントをOFF" : @"テストコメントをON") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [s setMockMode:!s.mockMode]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"今流れているコメントを消す" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        NicoChatOverlayView *overlay = objc_getAssociatedObject(weakSelf, kOverlayKey);
        [overlay clearComments];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"閉じる" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView;
        popover.sourceRect = sourceView.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [[self visiblePresenter] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Chat delegate

- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message {
    if (!message || message.text.length == 0 || ![SettingsManager shared].enabled) return;
    [self ensureOverlayAttached];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    [overlay enqueueMessage:message];
}
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!self.view.window) return;
    YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey);
    if (!ctl) {
        ctl = [[YTNicoController alloc] initWithVC:self];
        objc_setAssociatedObject(self, kCtlKey, ctl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        [ctl setup];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey);
    [ctl setup];
}
%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
            [[DebugInspector shared] log:@"YTNico loaded"];
        }
    }
}

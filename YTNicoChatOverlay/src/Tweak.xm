#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NicoChatOverlayView.h"
#import "NicoChatMessage.h"
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"
#import "YTNicoSettingsViewController.h"

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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearOverlayForVideoChange) name:kYTNicoClearOverlayNotification object:nil];
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
    if (![SettingsManager shared].enabled) [self clearOverlayForVideoChange];
    [self updateToggleButtonAppearance];
    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    [adapter stopObserving];
    [self setup];
}

- (void)clearAllOverlaysInView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:NicoChatOverlayView.class]) {
        NicoChatOverlayView *overlay = (NicoChatOverlayView *)view;
        [overlay clearComments];
    }
    for (UIView *subview in view.subviews) [self clearAllOverlaysInView:subview];
}

- (void)clearOverlayForVideoChange {
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    [overlay clearComments];
    [self clearAllOverlaysInView:self.window];
}

- (void)detachOverlay {
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay) return;
    [overlay clearComments];
    [overlay removeFromSuperview];
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
        [overlay clearComments];
        [overlay removeFromSuperview];
        overlay.frame = frame;
        [target addSubview:overlay];
    } else if (!CGRectEqualToRect(overlay.frame, frame)) {
        [overlay clearComments];
        overlay.frame = frame;
    }
    [target bringSubviewToFront:overlay];
    return overlay;
}

- (void)ensureFallbackOverlayAttached {
    if (!self.window) return;
    CGRect bounds = self.window.bounds;
    CGFloat safeTop = 20.0;
    CGFloat safeBottom = 0.0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.window.safeAreaInsets.top;
        safeBottom = self.window.safeAreaInsets.bottom;
    }

    BOOL portrait = bounds.size.height >= bounds.size.width;
    if (!portrait) {
        [self detachOverlay];
        return;
    }

    CGFloat y = MAX(safeTop + 8.0, 32.0);
    CGFloat width = bounds.size.width;
    CGFloat height = MIN(width * 9.0 / 16.0, bounds.size.height - y - safeBottom - 80.0);
    if (height < 120.0) {
        [self detachOverlay];
        return;
    }

    CGRect frame = CGRectMake(0, y, width, height);
    [self overlayForTargetView:self.window frame:frame];
    [[DebugInspector shared] log:@"Attached safe portrait fallback overlay frame=%@", NSStringFromCGRect(frame)];
}

- (void)ensureOverlayAttached {
    UIView *player = [self findBestPlayerCandidateInView:self.window];
    if (!player) {
        [[DebugInspector shared] log:@"No safe player candidate found; using safe portrait fallback if possible"];
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
    if ([className containsString:@"statusbar"]) return YES;
    if ([className containsString:@"navigationbar"]) return YES;
    if ([className containsString:@"tabbar"]) return YES;
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
            CGFloat safeTop = 20.0;
            if (@available(iOS 11.0, *)) safeTop = self.window.safeAreaInsets.top;
            BOOL belowStatusBar = rect.origin.y >= MAX(0.0, safeTop - 2.0);
            BOOL portraitLikePlayer = (ratio > 1.20 && ratio < 2.35 && rect.size.width >= screenW * 0.45 && rect.origin.y <= screenH * 0.70 && belowStatusBar);
            BOOL fullscreenLandscapePlayer = (ratio > 1.20 && ratio < 2.70 && rect.size.width >= screenW * 0.80 && rect.size.height >= screenH * 0.42);
            BOOL thumbnailLikePlayer = (ratio > 1.20 && ratio < 2.35 && rect.size.width >= screenW * 0.32 && rect.size.width <= screenW * 0.98 && rect.origin.y >= safeTop + 8.0 && rect.origin.y <= screenH * 0.85);
            if (portraitLikePlayer || fullscreenLandscapePlayer || thumbnailLikePlayer) [candidates addObject:view];
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
    CGFloat topBias = (rect.origin.y <= screen.height * 0.25) ? 18.0 : ((rect.origin.y <= screen.height * 0.70) ? 10.0 : -18.0);
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
    if (gesture.state == UIGestureRecognizerStateBegan) [self presentSettingsPage];
}

- (UIViewController *)visiblePresenter {
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    return presenter;
}

- (void)emitDisplayTestComment {
    [self ensureOverlayAttached];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay.superview) return;
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:NSUUID.UUID.UUIDString authorName:@"YTNico" text:@"表示テスト: これが流れればOverlayは正常です" timestamp:NSDate.date];
    [overlay enqueueMessage:msg];
}

- (void)fetchCommentsFromClipboard {
    NSString *clip = UIPasteboard.generalPasteboard.string ?: @"";
    NSString *videoId = [YouTubeChatAdapter extractVideoIdFromString:clip];
    if (videoId.length != 11) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"動画URL/IDが見つかりません" message:@"YouTubeの共有URL、watch URL、shorts URL、または11文字の動画IDをコピーしてから再実行してください。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self visiblePresenter] presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self ensureOverlayAttached];
    [YouTubeChatAdapter resetForVideoId:videoId];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (overlay.superview) {
        NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:NSUUID.UUID.UUIDString authorName:@"YTNico" text:[NSString stringWithFormat:@"コメント取得開始: %@", videoId] timestamp:NSDate.date];
        [overlay enqueueMessage:msg];
    }
    [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
}

- (void)presentSettingsPage {
    YTNicoSettingsViewController *vc = [YTNicoSettingsViewController new];
    __weak typeof(self) weakSelf = self;
    vc.displayTestHandler = ^{ [weakSelf emitDisplayTestComment]; };
    vc.clipboardFetchHandler = ^{ [weakSelf fetchCommentsFromClipboard]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [[self visiblePresenter] presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Chat delegate

- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message {
    if (!message || message.text.length == 0 || ![SettingsManager shared].enabled) return;
    [self ensureOverlayAttached];
    NicoChatOverlayView *overlay = objc_getAssociatedObject(self, kOverlayKey);
    if (!overlay || !overlay.superview) return;
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

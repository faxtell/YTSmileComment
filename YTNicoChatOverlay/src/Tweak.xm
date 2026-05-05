#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "NicoChatOverlayView.h"
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static const void *kOverlayKey = &kOverlayKey;
static const void *kAdapterKey = &kAdapterKey;

@interface YTNicoController : NSObject <YouTubeChatAdapterDelegate>
@property (nonatomic, weak) UIViewController *hostVC;
@property (nonatomic, weak) UIView *attachedPlayer;
@end

@implementation YTNicoController
- (instancetype)initWithVC:(UIViewController *)vc {
    if ((self=[super init])) {
        _hostVC = vc;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSettings) name:kYTNicoSettingsChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
        [self setupOrRefresh];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)reloadSettings { [self setupOrRefresh]; }
- (void)onAppDidEnterBackground {
    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    [adapter stopObserving];
}
- (void)onAppWillEnterForeground { [self setupOrRefresh]; }

- (BOOL)isVisibleCandidate:(UIView *)v {
    if (!v || v.hidden || v.alpha < 0.1 || v.bounds.size.width < 200 || v.bounds.size.height < 110) return NO;
    if (!v.window) return NO;
    CGRect frameInWindow = [v convertRect:v.bounds toView:nil];
    return CGRectIntersectsRect(frameInWindow, v.window.bounds);
}

- (CGFloat)scoreForView:(UIView *)v {
    if (![self isVisibleCandidate:v]) return -CGFLOAT_MAX;
    CGRect f = [v convertRect:v.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    BOOL portrait = screen.height >= screen.width;
    if (portrait && CGRectGetMinY(f) > screen.height * 0.55) return -CGFLOAT_MAX;
    if (portrait && CGRectGetHeight(f) > screen.height * 0.65) return -CGFLOAT_MAX;
    CGFloat wRatio = MIN(1.2, f.size.width / MAX(screen.width, 1));
    CGFloat ratio = f.size.width / MAX(f.size.height, 1.0);
    CGFloat ratioScore = MAX(0, 1.0 - fabs(ratio - (16.0/9.0)) / 1.2);
    CGFloat topScore = portrait ? MAX(0, 1.0 - (CGRectGetMinY(f) / MAX(screen.height, 1))) : 0.5;
    CGFloat fullscreenBonus = (!portrait && f.size.width > screen.width * 0.75 && f.size.height > screen.height * 0.65) ? 0.8 : 0.0;
    CGFloat areaScore = MIN(1.0, (f.size.width * f.size.height) / MAX(screen.width*screen.height, 1));
    return ratioScore * 2.0 + wRatio * 2.0 + topScore + fullscreenBonus + areaScore;
}

- (UIView *)bestPlayerCandidateInView:(UIView *)root currentBest:(UIView *)best bestScore:(CGFloat *)bestScore {
    if (!root) return best;
    CGFloat score = [self scoreForView:root];
    if (score > *bestScore) { *bestScore = score; best = root; }
    for (UIView *sub in root.subviews) {
        best = [self bestPlayerCandidateInView:sub currentBest:best bestScore:bestScore];
    }
    return best;
}

- (UIView *)findBestPlayerView {
    if (!self.hostVC.view) return nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    UIView *best = [self bestPlayerCandidateInView:self.hostVC.view currentBest:nil bestScore:&bestScore];
    return bestScore > 2.0 ? best : nil;
}

- (void)setupOrRefresh {
    UIView *player = [self findBestPlayerView];
    if (!player) {
        if (self.attachedPlayer) {
            NicoChatOverlayView *old = objc_getAssociatedObject(self.attachedPlayer, kOverlayKey);
            [old removeFromSuperview];
            objc_setAssociatedObject(self.attachedPlayer, kOverlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
            self.attachedPlayer = nil;
        }
        return;
    }
    player.clipsToBounds = YES;

    NicoChatOverlayView *overlay = nil;
    if (self.attachedPlayer && self.attachedPlayer != player) {
        NicoChatOverlayView *old = objc_getAssociatedObject(self.attachedPlayer, kOverlayKey);
        [old removeFromSuperview];
        objc_setAssociatedObject(self.attachedPlayer, kOverlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    self.attachedPlayer = player;

    overlay = objc_getAssociatedObject(player, kOverlayKey);
    if (!overlay) {
        overlay = [[NicoChatOverlayView alloc] initWithFrame:player.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.clipsToBounds = YES;
        overlay.layer.masksToBounds = YES;
        [player addSubview:overlay];
        objc_setAssociatedObject(player, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    overlay.frame = player.bounds;

    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    if (!adapter) {
        adapter = [YouTubeChatAdapter new];
        adapter.delegate = self;
        objc_setAssociatedObject(self, kAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [adapter startObservingInRootView:self.hostVC.view];
}

- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message {
    UIView *player = self.attachedPlayer ?: [self findBestPlayerView];
    NicoChatOverlayView *overlay = player ? objc_getAssociatedObject(player, kOverlayKey) : nil;
    [overlay enqueueMessage:message];
}
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!self.view.window) return;
    static const void *kCtlKey = "ytnico_controller";
    YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey);
    if (!ctl) {
        ctl = [[YTNicoController alloc] initWithVC:self];
        objc_setAssociatedObject(self, kCtlKey, ctl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        [ctl setupOrRefresh];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    static const void *kCtlKey = "ytnico_controller";
    YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey);
    [ctl setupOrRefresh];
}
%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
            [[DebugInspector shared] log:@"YTNico loaded"];
        }
    }
}

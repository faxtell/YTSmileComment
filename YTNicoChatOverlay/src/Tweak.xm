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
- (instancetype)initWithVC:(UIViewController *)vc { if ((self=[super init])) { _hostVC = vc; [self setupOrRefresh]; } return self; }

- (BOOL)shouldSkipPlayerCandidateView:(UIView *)view {
    if (!view) return YES;
    if ([view isKindOfClass:NicoChatOverlayView.class]) return YES;
    if ([view isKindOfClass:UIControl.class]) return YES;
    if ([view isKindOfClass:UIWindow.class]) return YES;
    NSString *className = NSStringFromClass(view.class).lowercaseString;
    for (NSString *k in @[@"overlay",@"button",@"comment",@"chat",@"caption",@"subtitle"]) if ([className containsString:k]) return YES;
    return NO;
}
- (BOOL)isVisibleCandidate:(UIView *)v {
    if ([self shouldSkipPlayerCandidateView:v]) return NO;
    if (v.hidden || v.alpha < 0.1 || v.bounds.size.width < 200 || v.bounds.size.height < 110 || !v.window) return NO;
    return CGRectIntersectsRect([v convertRect:v.bounds toView:nil], v.window.bounds);
}
- (CGFloat)scoreForView:(UIView *)v {
    if (![self isVisibleCandidate:v]) return -CGFLOAT_MAX;
    CGRect f = [v convertRect:v.bounds toView:nil]; CGSize screen = UIScreen.mainScreen.bounds.size; BOOL portrait = screen.height >= screen.width;
    if (portrait && CGRectGetMinY(f) > screen.height * 0.55) return -CGFLOAT_MAX;
    CGFloat ratio = f.size.width / MAX(f.size.height, 1.0);
    CGFloat ratioScore = MAX(0, 1.0 - fabs(ratio - (16.0/9.0)) / 1.2);
    CGFloat wRatio = MIN(1.2, f.size.width / MAX(screen.width, 1));
    CGFloat topScore = portrait ? MAX(0, 1.0 - (CGRectGetMinY(f) / MAX(screen.height, 1))) : 0.6;
    return ratioScore * 2.0 + wRatio * 2.0 + topScore;
}
- (UIView *)bestPlayerCandidateInView:(UIView *)root currentBest:(UIView *)best bestScore:(CGFloat *)bestScore {
    if (!root || [self shouldSkipPlayerCandidateView:root]) return best;
    CGFloat score = [self scoreForView:root]; if (score > *bestScore) { *bestScore = score; best = root; }
    for (UIView *sub in root.subviews) best = [self bestPlayerCandidateInView:sub currentBest:best bestScore:bestScore];
    return best;
}
- (UIView *)findBestPlayerView { CGFloat bestScore=-CGFLOAT_MAX; UIView *best=[self bestPlayerCandidateInView:self.hostVC.view currentBest:nil bestScore:&bestScore]; return bestScore > 1.5 ? best : nil; }

- (void)setupOrRefresh {
    UIView *player = [self findBestPlayerView];
    if (!player || [self shouldSkipPlayerCandidateView:player]) return;
    NicoChatOverlayView *overlay = objc_getAssociatedObject(player, kOverlayKey);
    if (player == overlay) return;
    if ([player isKindOfClass:NicoChatOverlayView.class]) return;
    if ([player isKindOfClass:UIControl.class]) return;
    if (self.attachedPlayer && self.attachedPlayer != player) {
        NicoChatOverlayView *old = objc_getAssociatedObject(self.attachedPlayer, kOverlayKey);
        [old removeFromSuperview];
        objc_setAssociatedObject(self.attachedPlayer, kOverlayKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    self.attachedPlayer = player;
    player.clipsToBounds = YES;
    if (!overlay) {
        overlay = [[NicoChatOverlayView alloc] initWithFrame:player.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.clipsToBounds = YES; overlay.layer.masksToBounds = YES;
        if (player != overlay) [player addSubview:overlay];
        objc_setAssociatedObject(player, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    overlay.frame = player.bounds;

    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    if (!adapter) { adapter = [YouTubeChatAdapter new]; adapter.delegate = self; objc_setAssociatedObject(self, kAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [adapter startObservingInRootView:self.hostVC.view];
}
- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message { NicoChatOverlayView *overlay = self.attachedPlayer ? objc_getAssociatedObject(self.attachedPlayer, kOverlayKey) : nil; [overlay enqueueMessage:message]; }
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated { %orig; if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return; static const void *kCtlKey = "ytnico_controller"; YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey); if (!ctl) { ctl = [[YTNicoController alloc] initWithVC:self]; objc_setAssociatedObject(self, kCtlKey, ctl, OBJC_ASSOCIATION_RETAIN_NONATOMIC);} else {[ctl setupOrRefresh];} }
- (void)viewDidLayoutSubviews { %orig; if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return; static const void *kCtlKey = "ytnico_controller"; YTNicoController *ctl = objc_getAssociatedObject(self, kCtlKey); [ctl setupOrRefresh]; }
%end

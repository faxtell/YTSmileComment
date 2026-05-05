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
@end

@implementation YTNicoController
- (instancetype)initWithVC:(UIViewController *)vc {
    if ((self=[super init])) {
        _hostVC = vc;
        [self setup];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadSettings) name:kYTNicoSettingsChangedNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)reloadSettings { }
- (void)setup {
    UIView *player = [self findPlayerCandidateInView:self.hostVC.view];
    if (!player) return;
    NicoChatOverlayView *overlay = objc_getAssociatedObject(player, kOverlayKey);
    if (!overlay) {
        overlay = [[NicoChatOverlayView alloc] initWithFrame:player.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [player addSubview:overlay];
        objc_setAssociatedObject(player, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    YouTubeChatAdapter *adapter = objc_getAssociatedObject(self, kAdapterKey);
    if (!adapter) {
        adapter = [YouTubeChatAdapter new];
        adapter.delegate = self;
        objc_setAssociatedObject(self, kAdapterKey, adapter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [adapter startObservingInRootView:self.hostVC.view];
}
- (UIView *)findPlayerCandidateInView:(UIView *)root {
    if (!root) return nil;
    CGSize size = root.bounds.size;
    BOOL largeEnough = size.width > 240 && size.height > 140;
    CGFloat ratio = size.width / MAX(size.height, 1.0);
    BOOL ratioOK = (ratio > 1.3 && ratio < 2.1) || (size.width > UIScreen.mainScreen.bounds.size.width*0.9 && size.height > UIScreen.mainScreen.bounds.size.height*0.45);
    if (largeEnough && ratioOK && root.subviews.count > 0) return root;
    for (UIView *sub in root.subviews) {
        UIView *c = [self findPlayerCandidateInView:sub];
        if (c) return c;
    }
    return nil;
}
- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message {
    UIView *player = [self findPlayerCandidateInView:self.hostVC.view];
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
    }
}
%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
            [[DebugInspector shared] log:@"YTNico loaded"]; 
        }
    }
}

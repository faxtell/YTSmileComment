#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YTNicoSettingsViewController.h"
#import "DebugInspector.h"

@interface YTNicoTutorialViewController : UIViewController
+ (BOOL)shouldShowTutorial;
+ (void)markTutorialShown;
@end

@interface YTNicoCategoryViewController : UIViewController
@property (nonatomic, copy) NSString *categoryKind;
@end

static NSString * const kYTNicoTutorialGateDomain = @"com.example.yt-nico-chat-overlay";
static NSString * const kYTNicoTutorialLicenseReadyKey = @"ready.v1";
static NSString * const kYTNicoTutorialShownKey = @"tutorial.shown.v1";
static NSString * const kYTNicoSuppressTutorialUntilKey = @"tutorial.suppress.until";
static NSString * const kYTNicoTutorialClosedUntilKey = @"tutorial.closed.until";
static const NSInteger kYTNicoTutorialButtonTag = 950531;
static BOOL gYTNicoTutorialPresentedThisActiveSession = NO;
static BOOL gYTNicoTutorialObserverInstalled = NO;

static NSUserDefaults *YTNicoTutorialDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:kYTNicoTutorialGateDomain] ?: NSUserDefaults.standardUserDefaults;
}

static BOOL YTNicoTutorialLicenseReady(void) {
    return [YTNicoTutorialDefaults() boolForKey:kYTNicoTutorialLicenseReadyKey];
}

static BOOL YTNicoTutorialShown(void) {
    return [YTNicoTutorialDefaults() boolForKey:kYTNicoTutorialShownKey];
}

static BOOL YTNicoTutorialSuppressedNow(void) {
    NSUserDefaults *d = YTNicoTutorialDefaults();
    NSTimeInterval now = [NSDate.date timeIntervalSince1970];
    NSTimeInterval until = [d doubleForKey:kYTNicoSuppressTutorialUntilKey];
    NSTimeInterval closedUntil = [d doubleForKey:kYTNicoTutorialClosedUntilKey];
    return until > now || closedUntil > now;
}

static UIViewController *YTNicoTopViewControllerFrom(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController) return YTNicoTopViewControllerFrom(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return YTNicoTopViewControllerFrom(((UINavigationController *)vc).topViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return YTNicoTopViewControllerFrom(((UITabBarController *)vc).selectedViewController);
    return vc;
}

static UIWindow *YTNicoKeyWindow(void) {
    UIWindow *best = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) return w;
                if (!best && !w.hidden && w.alpha > 0.01) best = w;
            }
        }
    }
    if (!best) best = UIApplication.sharedApplication.keyWindow;
    if (!best) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w.hidden && w.alpha > 0.01) { best = w; break; }
        }
    }
    return best;
}

static BOOL YTNicoTopAlreadyTutorial(UIViewController *vc) {
    if (!vc) return NO;
    NSString *name = NSStringFromClass(vc.class);
    return [name rangeOfString:@"YTNicoTutorialViewController"].location != NSNotFound;
}

static BOOL YTNicoShouldBlockTutorialPresentation(BOOL forceBecauseUnlicensed) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return YES;
    if (YTNicoTutorialSuppressedNow()) return YES;
    BOOL licensed = YTNicoTutorialLicenseReady();
    BOOL shown = YTNicoTutorialShown();
    if (licensed && shown) return YES;
    if (licensed && ![YTNicoTutorialViewController shouldShowTutorial]) return YES;
    if (forceBecauseUnlicensed && licensed) return YES;
    if (!forceBecauseUnlicensed && ![YTNicoTutorialViewController shouldShowTutorial]) return YES;
    return NO;
}

static void YTNicoPresentTutorialIfNeeded(BOOL forceBecauseUnlicensed) {
    if (YTNicoShouldBlockTutorialPresentation(forceBecauseUnlicensed)) {
        [[DebugInspector shared] log:@"tutorial presentation blocked force=%d", forceBecauseUnlicensed];
        return;
    }
    if (gYTNicoTutorialPresentedThisActiveSession && forceBecauseUnlicensed) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (YTNicoShouldBlockTutorialPresentation(forceBecauseUnlicensed)) return;
        if (gYTNicoTutorialPresentedThisActiveSession && forceBecauseUnlicensed) return;

        UIWindow *window = YTNicoKeyWindow();
        UIViewController *top = YTNicoTopViewControllerFrom(window.rootViewController);
        if (!top || YTNicoTopAlreadyTutorial(top)) return;
        if (top.presentedViewController) return;

        YTNicoTutorialViewController *vc = [YTNicoTutorialViewController new];
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:vc animated:YES completion:nil];
        gYTNicoTutorialPresentedThisActiveSession = YES;
        [[DebugInspector shared] important:@"tutorial presented force=%d licensed=%d shown=%d", forceBecauseUnlicensed, YTNicoTutorialLicenseReady(), YTNicoTutorialShown()];
    });
}

static void YTNicoInstallTutorialObserver(void) {
    if (gYTNicoTutorialObserverInstalled) return;
    gYTNicoTutorialObserverInstalled = YES;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        if (!YTNicoTutorialSuppressedNow()) gYTNicoTutorialPresentedThisActiveSession = NO;
        if (!YTNicoTutorialLicenseReady()) YTNicoPresentTutorialIfNeeded(YES);
    }];
    [[DebugInspector shared] log:@"tutorial launch observer installed"];
}

static UIStackView *YTNicoFindFirstStack(UIView *view) {
    if ([view isKindOfClass:UIStackView.class]) return (UIStackView *)view;
    for (UIView *sub in view.subviews) {
        UIStackView *found = YTNicoFindFirstStack(sub);
        if (found) return found;
    }
    return nil;
}

static UIButton *YTNicoTutorialButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = kYTNicoTutorialButtonTag;
    button.backgroundColor = UIColor.secondarySystemBackgroundColor;
    button.layer.cornerRadius = 14.0;
    button.layer.masksToBounds = YES;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12);
    NSString *title = @"🧭 チュートリアルを見る\n使い方をもう一度表示";
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:title];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] range:NSMakeRange(0, @"🧭 チュートリアルを見る".length)];
    NSRange sub = [title rangeOfString:@"使い方をもう一度表示"];
    [attr addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular] range:sub];
    [attr addAttribute:NSForegroundColorAttributeName value:UIColor.secondaryLabelColor range:sub];
    button.titleLabel.numberOfLines = 2;
    [button setAttributedTitle:attr forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return button;
}

%hook UIApplication

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig(application, launchOptions);
    YTNicoInstallTutorialObserver();
    if (!YTNicoTutorialLicenseReady()) YTNicoPresentTutorialIfNeeded(YES);
    return result;
}

%end

%hook YTNicoSettingsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    YTNicoInstallTutorialObserver();
    if (!YTNicoTutorialLicenseReady()) {
        YTNicoPresentTutorialIfNeeded(YES);
        return;
    }
    if ([YTNicoTutorialViewController shouldShowTutorial]) YTNicoPresentTutorialIfNeeded(NO);
}

%end

%hook YTNicoCategoryViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![self.categoryKind isEqualToString:@"tools"]) return;
    UIStackView *stack = YTNicoFindFirstStack(self.view);
    if (!stack || [stack viewWithTag:kYTNicoTutorialButtonTag]) return;
    UIButton *button = YTNicoTutorialButton();
    [button addTarget:self action:@selector(ytnico_showTutorialAgain) forControlEvents:UIControlEventTouchUpInside];
    [stack insertArrangedSubview:button atIndex:MIN((NSUInteger)1, stack.arrangedSubviews.count)];
}

%new
- (void)ytnico_showTutorialAgain {
    YTNicoTutorialViewController *vc = [YTNicoTutorialViewController new];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTNicoInstallTutorialObserver();
            if (!YTNicoTutorialLicenseReady()) YTNicoPresentTutorialIfNeeded(YES);
        });
    }
}

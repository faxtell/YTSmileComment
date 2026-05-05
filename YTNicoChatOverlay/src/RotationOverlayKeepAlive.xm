#import <UIKit/UIKit.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static CFTimeInterval gYTNicoLastRotationRefresh = 0;
static CGSize gYTNicoLastScreenSize = {0, 0};

static void YTNicoRefreshOverlayAfterGeometryChange(NSString *reason) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!SettingsManager.shared.enabled) return;
        CGSize size = UIScreen.mainScreen.bounds.size;
        CFTimeInterval now = CACurrentMediaTime();
        if (fabs(size.width - gYTNicoLastScreenSize.width) < 1.0 && fabs(size.height - gYTNicoLastScreenSize.height) < 1.0 && now - gYTNicoLastRotationRefresh < 0.8) return;
        gYTNicoLastScreenSize = size;
        gYTNicoLastRotationRefresh = now;

        // Re-apply enabled and notify listeners. This acts like a very light internal
        // off/on refresh without visibly toggling the user's setting.
        [SettingsManager.shared setEnabled:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.example.ytnico.settings.changed" object:nil];
        [[DebugInspector shared] important:@"overlay keepalive after geometry change: %@ %.0fx%.0f", reason ?: @"unknown", size.width, size.height];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!SettingsManager.shared.enabled) return;
        [SettingsManager.shared setEnabled:YES];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"com.example.ytnico.settings.changed" object:nil];
    });
}

%hook UIViewController

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    %orig;
    if (SettingsManager.shared.enabled) {
        [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
            YTNicoRefreshOverlayAfterGeometryChange(@"viewWillTransitionToSize");
        }];
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!SettingsManager.shared.enabled) return;
    CGSize size = UIScreen.mainScreen.bounds.size;
    if (fabs(size.width - gYTNicoLastScreenSize.width) >= 12.0 || fabs(size.height - gYTNicoLastScreenSize.height) >= 12.0) {
        YTNicoRefreshOverlayAfterGeometryChange(@"layoutSizeChanged");
    }
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        gYTNicoLastScreenSize = UIScreen.mainScreen.bounds.size;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoRefreshOverlayAfterGeometryChange(@"appDidBecomeActive");
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoRefreshOverlayAfterGeometryChange(@"deviceOrientationDidChange");
        }];
    });
}

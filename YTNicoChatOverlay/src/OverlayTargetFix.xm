#import <UIKit/UIKit.h>
#import <math.h>
#import "DebugInspector.h"
#import "SettingsManager.h"

@interface YTNicoController : NSObject
- (CGFloat)scorePlayerCandidate:(UIView *)view;
@end

static CFTimeInterval gYTNicoLastOverlayCandidateLog = 0;

%hook YTNicoController

- (CGFloat)scorePlayerCandidate:(UIView *)view {
    if (!view) return -CGFLOAT_MAX;
    CGRect rect = [view convertRect:view.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat screenW = MAX(screen.width, 1.0);
    CGFloat screenH = MAX(screen.height, 1.0);
    CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
    CGFloat aspectDelta = fabs(ratio - (16.0 / 9.0));

    CGFloat safeTop = 20.0;
    UIWindow *window = view.window;
    if (@available(iOS 11.0, *)) safeTop = window.safeAreaInsets.top;

    BOOL landscape = screenW > screenH;
    BOOL nearlyFullWidth = rect.size.width >= screenW * 0.88;
    BOOL nearlyFullHeight = rect.size.height >= screenH * 0.62;
    BOOL largeTopPortraitPlayer = !landscape && rect.origin.y <= safeTop + 80.0 && rect.size.width >= screenW * 0.82 && rect.size.height >= 150.0;
    BOOL fullscreenLandscapePlayer = landscape && nearlyFullWidth && nearlyFullHeight;
    BOOL feedThumbnail = !largeTopPortraitPlayer && rect.size.width >= screenW * 0.32 && rect.size.height >= 90.0;

    CGFloat score = 0.0;
    score += MIN(rect.size.width / screenW, 1.15) * 45.0;
    score += MAX(0.0, 45.0 - aspectDelta * 70.0);

    if (fullscreenLandscapePlayer) score += 220.0;
    if (largeTopPortraitPlayer) score += 180.0;
    if (rect.origin.y <= safeTop + 16.0 && rect.size.height >= screenH * 0.35) score += 70.0;
    if (feedThumbnail) score += 22.0;

    if (rect.size.height < 100.0) score -= 40.0;
    if (!largeTopPortraitPlayer && !fullscreenLandscapePlayer && rect.origin.y > screenH * 0.55) score -= 28.0;
    if (view.subviews.count > 120) score -= 18.0;

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    if ([className containsString:@"player"] || [className containsString:@"watch"] || [className containsString:@"video"]) score += 28.0;
    if ([className containsString:@"cell"] && !largeTopPortraitPlayer && !fullscreenLandscapePlayer) score -= 8.0;

    // Candidate scoring runs very often during YouTube layout. Logging every candidate
    // makes the debug screen unusable and can slow UI work, so only log notable matches
    // at a low rate.
    CFTimeInterval now = CACurrentMediaTime();
    if (score >= 285.0 && now - gYTNicoLastOverlayCandidateLog > 2.0) {
        gYTNicoLastOverlayCandidateLog = now;
        [[DebugInspector shared] log:@"overlay candidate top %@ rect=%@ score=%.1f", NSStringFromClass(view.class), NSStringFromCGRect(rect), score];
    }
    return score;
}

%end

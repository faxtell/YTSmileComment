#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "SettingsManager.h"
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static NSTimer *gYTNicoStabilityTimer = nil;
static CFTimeInterval gYTNicoLastRefetchAttempt = 0;
static NSString *gYTNicoLastRefetchVideoId = nil;

static BOOL YTNicoStabilityIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoStabilityBestVideoId(void) {
    NSString *videoId = [YouTubeChatAdapter currentVideoId];
    if (videoId.length == 11) return videoId;
    videoId = [YouTubeChatAdapter recentDetectedVideoId];
    if (videoId.length == 11) return videoId;
    return @"";
}

static void YTNicoStabilityKick(NSString *reason) {
    if (!YTNicoStabilityIsYouTube()) return;
    if (!SettingsManager.shared.enabled) return;

    [YouTubeChatAdapter watchdogKick];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"com.example.ytnico.settings.changed" object:nil];

    NSTimeInterval idle = [YouTubeChatAdapter secondsSinceLastMessage];
    NSUInteger pending = [YouTubeChatAdapter pendingMessageCount];
    NSString *videoId = YTNicoStabilityBestVideoId();

    if (pending > 0) {
        [[DebugInspector shared] log:@"stability kick reason=%@ pending=%lu idle=%.1f", reason ?: @"unknown", (unsigned long)pending, idle];
        return;
    }

    if (videoId.length == 11 && idle > 35.0) {
        CFTimeInterval now = CACurrentMediaTime();
        BOOL sameVideoRecently = [gYTNicoLastRefetchVideoId isEqualToString:videoId] && now - gYTNicoLastRefetchAttempt < 45.0;
        if (!sameVideoRecently) {
            gYTNicoLastRefetchAttempt = now;
            gYTNicoLastRefetchVideoId = [videoId copy];
            [[DebugInspector shared] important:@"stability watchdog refetch videoId=%@ idle=%.1f reason=%@", videoId, idle, reason ?: @"timer"];
            [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
        }
    }
}

static void YTNicoStartStabilityWatchdog(void) {
    if (!YTNicoStabilityIsYouTube()) return;
    if (gYTNicoStabilityTimer && gYTNicoStabilityTimer.valid) return;
    gYTNicoStabilityTimer = [NSTimer scheduledTimerWithTimeInterval:15.0 repeats:YES block:^(__unused NSTimer *timer) {
        YTNicoStabilityKick(@"timer");
    }];
    [[NSRunLoop mainRunLoop] addTimer:gYTNicoStabilityTimer forMode:NSRunLoopCommonModes];
    YTNicoStabilityKick(@"start");
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    YTNicoStartStabilityWatchdog();
    YTNicoStabilityKick(@"applicationDidBecomeActive");
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        YTNicoStartStabilityWatchdog();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoStartStabilityWatchdog();
            YTNicoStabilityKick(@"didBecomeActiveNotification");
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            YTNicoStabilityKick(@"orientationChanged");
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:kYTNicoCurrentVideoChangedNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            gYTNicoLastRefetchAttempt = 0;
            gYTNicoLastRefetchVideoId = nil;
            YTNicoStabilityKick(@"videoChanged");
        }];
    });
}

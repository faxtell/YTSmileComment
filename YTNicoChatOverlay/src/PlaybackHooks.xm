#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoPlaybackFetch)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId;
@end

static __weak AVPlayer *YTNicoActivePlayer;
static NSTimer *YTNicoPlaybackPollTimer;
static NSString *YTNicoLastPlaybackFetchVideoId;
static NSDate *YTNicoLastPlaybackFetchDate;

static void YTNicoUpdatePlaybackFromPlayer(AVPlayer *player) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (![player isKindOfClass:AVPlayer.class]) return;
    CMTime t = player.currentTime;
    if (!CMTIME_IS_NUMERIC(t) || CMTIME_IS_INDEFINITE(t)) return;
    Float64 seconds = CMTimeGetSeconds(t);
    if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
}

static void YTNicoTryPlaybackAutoFetch(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    NSString *videoId = [YouTubeChatAdapter recentDetectedVideoId];
    if (videoId.length != 11) return;

    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        BOOL sameRecent = [YTNicoLastPlaybackFetchVideoId isEqualToString:videoId] && YTNicoLastPlaybackFetchDate && [now timeIntervalSinceDate:YTNicoLastPlaybackFetchDate] < 25.0;
        if (sameRecent) return;
        YTNicoLastPlaybackFetchVideoId = [videoId copy];
        YTNicoLastPlaybackFetchDate = now;
    }

    [[DebugInspector shared] important:@"playback auto fetch videoId=%@", videoId];
    [YouTubeChatAdapter forceResetForVideoId:videoId];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![[YouTubeChatAdapter currentVideoId] isEqualToString:videoId]) return;
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"再生開始からコメント取得: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        [YouTubeChatAdapter ytnico_fetchCommentsForVideoIdIgnoringThrottle:videoId];
    });
}

static void YTNicoStartPlaybackPolling(AVPlayer *player) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    YTNicoActivePlayer = player;
    if (YTNicoPlaybackPollTimer && YTNicoPlaybackPollTimer.valid) return;
    YTNicoPlaybackPollTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        AVPlayer *p = YTNicoActivePlayer;
        if (!p) return;
        YTNicoUpdatePlaybackFromPlayer(p);
    }];
    [NSRunLoop.mainRunLoop addTimer:YTNicoPlaybackPollTimer forMode:NSRunLoopCommonModes];
}

%hook AVPlayer
- (CMTime)currentTime {
    CMTime t = %orig;
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"] && CMTIME_IS_NUMERIC(t) && !CMTIME_IS_INDEFINITE(t)) {
        YTNicoActivePlayer = self;
        Float64 seconds = CMTimeGetSeconds(t);
        if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
        YTNicoStartPlaybackPolling(self);
    }
    return t;
}

- (void)play {
    YTNicoStartPlaybackPolling(self);
    YTNicoUpdatePlaybackFromPlayer(self);
    YTNicoTryPlaybackAutoFetch();
    %orig;
}

- (void)pause {
    YTNicoUpdatePlaybackFromPlayer(self);
    %orig;
}

- (void)seekToTime:(CMTime)time {
    if (CMTIME_IS_NUMERIC(time) && !CMTIME_IS_INDEFINITE(time)) {
        Float64 seconds = CMTimeGetSeconds(time);
        if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
    }
    %orig(time);
}

- (void)seekToTime:(CMTime)time toleranceBefore:(CMTime)toleranceBefore toleranceAfter:(CMTime)toleranceAfter {
    if (CMTIME_IS_NUMERIC(time) && !CMTIME_IS_INDEFINITE(time)) {
        Float64 seconds = CMTimeGetSeconds(time);
        if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
    }
    %orig(time, toleranceBefore, toleranceAfter);
}
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) [[DebugInspector shared] log:@"YTNico playback hooks loaded"];
}

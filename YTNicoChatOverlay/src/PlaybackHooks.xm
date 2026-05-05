#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static __weak AVPlayer *YTNicoActivePlayer;
static NSTimer *YTNicoPlaybackPollTimer;

static void YTNicoUpdatePlaybackFromPlayer(AVPlayer *player) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (![player isKindOfClass:AVPlayer.class]) return;
    CMTime t = player.currentTime;
    if (!CMTIME_IS_NUMERIC(t) || CMTIME_IS_INDEFINITE(t)) return;
    Float64 seconds = CMTimeGetSeconds(t);
    if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
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

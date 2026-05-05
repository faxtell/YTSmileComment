#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static void YTNicoUpdatePlaybackFromPlayer(AVPlayer *player) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (![player isKindOfClass:AVPlayer.class]) return;
    CMTime t = player.currentTime;
    if (!CMTIME_IS_NUMERIC(t) || CMTIME_IS_INDEFINITE(t)) return;
    Float64 seconds = CMTimeGetSeconds(t);
    if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
}

%hook AVPlayer
- (CMTime)currentTime {
    CMTime t = %orig;
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"] && CMTIME_IS_NUMERIC(t) && !CMTIME_IS_INDEFINITE(t)) {
        Float64 seconds = CMTimeGetSeconds(t);
        if (isfinite(seconds) && seconds >= 0) [YouTubeChatAdapter updateCurrentPlaybackSeconds:seconds];
    }
    return t;
}

- (void)play {
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

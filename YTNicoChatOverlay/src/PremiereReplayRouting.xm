#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static BOOL YTNicoTextHasStrictLiveFlag(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return NO;
    return [s rangeOfString:@"\"isLiveNow\":true"].location != NSNotFound ||
           [s rangeOfString:@"\\\"isLiveNow\\\":true"].location != NSNotFound ||
           [s rangeOfString:@"\"isLive\":true"].location != NSNotFound ||
           [s rangeOfString:@"\\\"isLive\\\":true"].location != NSNotFound;
}

static BOOL YTNicoTextHasReplaySignal(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return NO;
    return [s rangeOfString:@"videoOffsetTimeMsec"].location != NSNotFound ||
           [s rangeOfString:@"replayChatItemAction"].location != NSNotFound ||
           [s rangeOfString:@"get_live_chat_replay"].location != NSNotFound ||
           [s rangeOfString:@"liveChatReplayContinuationData"].location != NSNotFound ||
           [s rangeOfString:@"replayContinuationData"].location != NSNotFound;
}

static BOOL YTNicoTextLooksLikeArchivedChat(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return NO;
    if (YTNicoTextHasStrictLiveFlag(s)) return NO;
    if (YTNicoTextHasReplaySignal(s)) return YES;
    return [s rangeOfString:@"liveChatRenderer"].location != NSNotFound ||
           [s rangeOfString:@"liveChatItemListRenderer"].location != NSNotFound ||
           [s rangeOfString:@"liveChatContinuation"].location != NSNotFound;
}

%hook YouTubeChatAdapter

+ (BOOL)ytv2_isExplicitLiveNow:(NSString *)s {
    BOOL strictLive = YTNicoTextHasStrictLiveFlag(s);
    if (!strictLive) [[DebugInspector shared] log:@"premiere routing: not strict live"];
    return strictLive;
}

+ (BOOL)ytv2_hasLiveEndpoint:(NSString *)s {
    if (!YTNicoTextHasStrictLiveFlag(s)) return NO;
    if ([s rangeOfString:@"get_live_chat_replay"].location != NSNotFound) return NO;
    return [s rangeOfString:@"live_chat/get_live_chat"].location != NSNotFound ||
           [s rangeOfString:@"get_live_chat\""].location != NSNotFound ||
           [s rangeOfString:@"get_live_chat?"].location != NSNotFound;
}

+ (BOOL)ytv2_hasReplaySignal:(NSString *)s {
    BOOL result = YTNicoTextLooksLikeArchivedChat(s);
    if (result) [[DebugInspector shared] log:@"premiere routing: replay/archive signal detected"];
    return result;
}

%end

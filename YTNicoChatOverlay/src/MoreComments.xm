#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoMoreCommentsPrivate)
+ (BOOL)ytv2_gen:(NSUInteger)generation;
+ (NSDictionary *)ytv2_context:(NSString *)version;
+ (void)ytv2_post:(NSURL *)url body:(NSDictionary *)body completion:(void (^)(NSString *text))completion;
+ (NSInteger)ytv2_parseNormal:(NSString *)text max:(NSInteger)max live:(BOOL)live generation:(NSUInteger)generation;
+ (NSInteger)ytv2_parseReplay:(NSString *)text max:(NSInteger)max generation:(NSUInteger)generation;
+ (NSString *)ytv2_commentToken:(NSString *)text;
+ (NSString *)ytv2_replayToken:(NSString *)text;
+ (NSString *)ytv2_liveToken:(NSString *)text;
+ (void)ytv2_fetchComments:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation;
+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation;
@end

static NSInteger YTNicoDesiredCount(void) {
    NSInteger v = SettingsManager.shared.maxFetchComments;
    if (v <= 0) v = 500;
    return MAX(100, MIN(3000, v));
}

static NSInteger YTNicoCommentPageCap(NSInteger target, NSInteger perPage) {
    return MAX(12, MIN(80, (target / MAX(1, perPage)) + 10));
}

static NSInteger YTNicoReplayPageCap(NSInteger target, NSInteger perPage) {
    // Replay continuations often need several pages before replayChatItemAction appears.
    return MAX(24, MIN(120, (target / MAX(1, perPage)) + 22));
}

%hook YouTubeChatAdapter

+ (void)ytv2_fetchComments:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    NSInteger target = YTNicoDesiredCount();
    NSInteger perPage = 120;
    NSInteger cap = YTNicoCommentPageCap(target, perPage);
    if (![self ytv2_gen:generation] || token.length == 0 || total >= target || page > cap) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", key]];
    [self ytv2_post:url body:@{@"context":[self ytv2_context:version], @"continuation":token} completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger remaining = MAX(0, target - total);
        NSInteger emitted = text.length ? [self ytv2_parseNormal:text max:MIN(perPage, remaining) live:NO generation:generation] : 0;
        NSInteger newTotal = total + emitted;
        NSString *next = text.length ? [self ytv2_commentToken:text] : @"";
        [[DebugInspector shared] log:@"more comments page=%ld emitted=%ld total=%ld target=%ld cap=%ld", (long)page, (long)emitted, (long)newTotal, (long)target, (long)cap];
        if (next.length > 0 && newTotal < target && page < cap) {
            [self ytv2_fetchComments:key version:version token:next page:page+1 emitted:newTotal generation:generation];
        }
    }];
}

+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    NSInteger target = YTNicoDesiredCount();
    NSInteger perPage = 220;
    NSInteger cap = YTNicoReplayPageCap(target, perPage);
    if (![self ytv2_gen:generation] || token.length == 0 || total >= target || page > cap) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?key=%@", key]];
    [self ytv2_post:url body:@{@"context":[self ytv2_context:version], @"continuation":token} completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger remaining = MAX(0, target - total);
        NSInteger emitted = text.length ? [self ytv2_parseReplay:text max:MIN(perPage, remaining) generation:generation] : 0;
        NSInteger newTotal = total + emitted;
        NSString *r = text.length ? [self ytv2_replayToken:text] : @"";
        NSString *l = text.length ? [self ytv2_liveToken:text] : @"";
        NSString *next = r.length ? r : l;
        [[DebugInspector shared] log:@"more replay page=%ld emitted=%ld total=%ld target=%ld cap=%ld hasNext=%d", (long)page, (long)emitted, (long)newTotal, (long)target, (long)cap, next.length > 0];
        if (next.length > 0 && newTotal < target && page < cap) {
            [self ytv2_fetchReplay:key version:version token:next page:page+1 emitted:newTotal generation:generation];
        } else if (newTotal == 0 && page >= cap) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: チャットリプレイを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
        }
    }];
}

%end

#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoFetchLimitPrivate)
+ (BOOL)ytv2_gen:(NSUInteger)generation;
+ (NSDictionary *)ytv2_context:(NSString *)version;
+ (void)ytv2_post:(NSURL *)url body:(NSDictionary *)body completion:(void (^)(NSString *text))completion;
+ (NSInteger)ytv2_parseNormal:(NSString *)text max:(NSInteger)max live:(BOOL)live generation:(NSUInteger)generation;
+ (NSInteger)ytv2_parseReplay:(NSString *)text max:(NSInteger)max generation:(NSUInteger)generation;
+ (NSString *)ytv2_commentToken:(NSString *)text;
+ (NSString *)ytv2_replayToken:(NSString *)text;
+ (NSString *)ytv2_liveToken:(NSString *)text;
@end

static NSInteger YTNicoTargetFetchCount(void) {
    NSInteger value = SettingsManager.shared.maxFetchComments;
    if (value <= 0) value = 500;
    return MAX(100, MIN(3000, value));
}

static NSInteger YTNicoPageLimitForTarget(NSInteger target, NSInteger perPage) {
    NSInteger pages = (target / MAX(1, perPage)) + 6;
    return MAX(8, MIN(80, pages));
}

%hook YouTubeChatAdapter

+ (void)ytv2_fetchComments:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    NSInteger target = YTNicoTargetFetchCount();
    NSInteger perPage = 120;
    NSInteger maxPages = YTNicoPageLimitForTarget(target, perPage);
    if (![self ytv2_gen:generation] || token.length == 0 || total >= target || page > maxPages) return;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", key]];
    NSDictionary *body = @{@"context":[self ytv2_context:version], @"continuation":token};
    [self ytv2_post:url body:body completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger remaining = MAX(0, target - total);
        NSInteger emitted = text.length ? [self ytv2_parseNormal:text max:MIN(perPage, remaining) live:NO generation:generation] : 0;
        NSInteger newTotal = total + emitted;
        NSString *next = text.length ? [self ytv2_commentToken:text] : @"";
        [[DebugInspector shared] log:@"fetch comments page=%ld emitted=%ld total=%ld target=%ld", (long)page, (long)emitted, (long)newTotal, (long)target];
        if (next.length > 0 && newTotal < target && page < maxPages) {
            [self ytv2_fetchComments:key version:version token:next page:page + 1 emitted:newTotal generation:generation];
        }
    }];
}

+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    NSInteger target = YTNicoTargetFetchCount();
    NSInteger perPage = 220;
    NSInteger maxPages = YTNicoPageLimitForTarget(target, perPage);
    if (![self ytv2_gen:generation] || token.length == 0 || total >= target || page > maxPages) return;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?key=%@", key]];
    NSDictionary *body = @{@"context":[self ytv2_context:version], @"continuation":token};
    [self ytv2_post:url body:body completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger remaining = MAX(0, target - total);
        NSInteger emitted = text.length ? [self ytv2_parseReplay:text max:MIN(perPage, remaining) generation:generation] : 0;
        NSInteger newTotal = total + emitted;
        NSString *replayNext = text.length ? [self ytv2_replayToken:text] : @"";
        NSString *liveNext = text.length ? [self ytv2_liveToken:text] : @"";
        NSString *next = replayNext.length ? replayNext : liveNext;
        [[DebugInspector shared] log:@"fetch replay page=%ld emitted=%ld total=%ld target=%ld", (long)page, (long)emitted, (long)newTotal, (long)target];
        if (next.length > 0 && newTotal < target && page < maxPages) {
            [self ytv2_fetchReplay:key version:version token:next page:page + 1 emitted:newTotal generation:generation];
        } else if (newTotal == 0) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: チャットリプレイを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
        }
    }];
}

%end

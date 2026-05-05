#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoMoreCommentsPrivate)
+ (BOOL)ytv2_gen:(NSUInteger)generation;
@end

static CFTimeInterval gYTNicoLiveBurstWindow = 0;
static NSUInteger gYTNicoLiveBurstIndex = 0;

static NSTimeInterval YTNicoLiveSpreadDelay(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLiveBurstWindow > 1.25) {
        gYTNicoLiveBurstWindow = now;
        gYTNicoLiveBurstIndex = 0;
    }
    NSUInteger index = gYTNicoLiveBurstIndex++;
    double lane = (double)(index % 10) * 0.16;
    double wave = (double)(index / 10) * 0.28;
    double jitter = ((double)arc4random_uniform(120)) / 1000.0;
    return MIN(2.8, lane + wave + jitter);
}

%hook YouTubeChatAdapter

+ (void)ytv2_fetchComments:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    [[DebugInspector shared] important:@"live-only mode: extra normal comment pagination skipped"];
}

+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)version token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    [[DebugInspector shared] important:@"live-only mode: replay pagination skipped"];
}

+ (NSString *)ytv2_commentToken:(NSString *)text {
    [[DebugInspector shared] important:@"live-only mode: comment token suppressed"];
    return @"";
}

+ (NSString *)ytv2_replayToken:(NSString *)text {
    [[DebugInspector shared] important:@"live-only mode: replay token suppressed"];
    return @"";
}

+ (NSString *)ytv2_strictReplayToken:(NSString *)text {
    [[DebugInspector shared] important:@"live-only mode: strict replay token suppressed"];
    return @"";
}

+ (void)queueTimedReplayAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId offsetMilliseconds:(unsigned long long)offsetMilliseconds generation:(NSUInteger)generation {
    [[DebugInspector shared] log:@"live-only mode: timed replay output suppressed"];
}

+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    if ([author isEqualToString:@"YTNico"] || text.length == 0) {
        %orig(author, text, messageId);
        return;
    }
    NSTimeInterval delay = YTNicoLiveSpreadDelay();
    NSString *a = [author copy] ?: @"";
    NSString *t = [text copy] ?: @"";
    NSString *m = [messageId copy] ?: NSUUID.UUID.UUIDString;
    [[DebugInspector shared] log:@"live spread delay=%.2f text=%@", delay, t];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        %orig(a, t, m);
    });
}

%end

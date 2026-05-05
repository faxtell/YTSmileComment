#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoMoreCommentsPrivate)
+ (BOOL)ytv2_gen:(NSUInteger)generation;
@end

static CFTimeInterval gYTNicoLiveBurstWindow = 0;
static NSUInteger gYTNicoLiveBurstIndex = 0;

static NSTimeInterval YTNicoLiveSpreadDelay(NSString *text) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLiveBurstWindow > 1.85) {
        gYTNicoLiveBurstWindow = now;
        gYTNicoLiveBurstIndex = 0;
    }

    NSUInteger index = gYTNicoLiveBurstIndex++;

    // YouTube live chat often arrives in small bursts. Spread each burst more loosely so
    // messages do not launch in a perfectly aligned wall.
    double rowOffset = (double)(index % 14) * 0.21;          // 0.00 - 2.73
    double waveOffset = (double)(index / 14) * 0.48;        // extra waves for larger bursts
    double jitter = ((double)arc4random_uniform(420)) / 1000.0; // 0.00 - 0.419
    double micro = ((double)arc4random_uniform(90)) / 1000.0;   // tiny human-like variance

    // Long comments visually occupy more space, so delay them very slightly more.
    NSUInteger len = text.length;
    double lengthOffset = 0.0;
    if (len >= 70) lengthOffset = 0.48;
    else if (len >= 38) lengthOffset = 0.24;

    // Every few comments, add an extra small gap. This gives a more organic rhythm.
    double pocketGap = 0.0;
    if (index > 0 && index % 7 == 0) pocketGap = ((double)arc4random_uniform(520)) / 1000.0;

    return MIN(5.5, rowOffset + waveOffset + jitter + micro + lengthOffset + pocketGap);
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
    NSTimeInterval delay = YTNicoLiveSpreadDelay(text ?: @"");
    NSString *a = [author copy] ?: @"";
    NSString *t = [text copy] ?: @"";
    NSString *m = [messageId copy] ?: NSUUID.UUID.UUIDString;
    [[DebugInspector shared] log:@"live spread delay=%.2f text=%@", delay, t];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        %orig(a, t, m);
    });
}

%end

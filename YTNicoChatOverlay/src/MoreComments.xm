#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoMoreCommentsPrivate)
+ (BOOL)ytv2_gen:(NSUInteger)generation;
@end

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

%end

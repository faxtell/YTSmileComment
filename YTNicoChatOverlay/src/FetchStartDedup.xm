#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static NSString *YTNicoLastFetchStartVideoId;
static NSDate *YTNicoLastFetchStartDate;
static BOOL YTNicoForceFetchInProgress;

@implementation YouTubeChatAdapter (YTNicoForceFetch)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId {
    YTNicoForceFetchInProgress = YES;
    [self fetchCommentsForVideoId:videoId];
    YTNicoForceFetchInProgress = NO;
}
@end

%hook YouTubeChatAdapter

+ (void)fetchCommentsForVideoId:(NSString *)videoId {
    if (![videoId isKindOfClass:NSString.class] || videoId.length != 11) {
        %orig(videoId);
        return;
    }

    if (YTNicoForceFetchInProgress) {
        [[DebugInspector shared] important:@"force fetch bypass throttle videoId=%@", videoId];
        YTNicoLastFetchStartVideoId = [videoId copy];
        YTNicoLastFetchStartDate = NSDate.date;
        %orig(videoId);
        return;
    }

    NSDate *now = NSDate.date;
    @synchronized (self) {
        if ([YTNicoLastFetchStartVideoId isEqualToString:videoId] && YTNicoLastFetchStartDate && [now timeIntervalSinceDate:YTNicoLastFetchStartDate] < 12.0) {
            [[DebugInspector shared] log:@"skip duplicate fetch start videoId=%@", videoId];
            return;
        }
        YTNicoLastFetchStartVideoId = [videoId copy];
        YTNicoLastFetchStartDate = now;
    }
    %orig(videoId);
}

%end

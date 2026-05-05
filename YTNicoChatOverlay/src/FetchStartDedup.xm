#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static NSString *YTNicoLastFetchStartVideoId;
static NSDate *YTNicoLastFetchStartDate;

%hook YouTubeChatAdapter

+ (void)fetchCommentsForVideoId:(NSString *)videoId {
    if (![videoId isKindOfClass:NSString.class] || videoId.length != 11) {
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

#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static NSMutableDictionary<NSString *, NSDate *> *YTNicoReplayHistory;

@implementation YouTubeChatAdapter (Replay)

+ (void)load {
    YTNicoReplayHistory = [NSMutableDictionary dictionary];
}

+ (void)observePotentialRequest:(NSURLRequest *)request bodyData:(NSData *)bodyData {
    if (![request isKindOfClass:NSURLRequest.class]) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-Replay"].length > 0) return;

    NSURL *url = request.URL;
    NSString *urlString = url.absoluteString ?: @"";
    NSString *lower = urlString.lowercaseString;
    if (![lower containsString:@"youtubei"] && ![lower containsString:@"/youtubei/"]) return;

    NSString *method = (request.HTTPMethod ?: @"GET").uppercaseString;
    NSData *body = bodyData ?: request.HTTPBody;
    if ([method isEqualToString:@"POST"] && body.length == 0) return;

    NSString *key = [NSString stringWithFormat:@"%@|%@|%lu", method, urlString, (unsigned long)body.hash];
    NSDate *now = NSDate.date;
    @synchronized (YTNicoReplayHistory) {
        NSDate *last = YTNicoReplayHistory[key];
        if (last && [now timeIntervalSinceDate:last] < 5.0) return;
        YTNicoReplayHistory[key] = now;
        if (YTNicoReplayHistory.count > 200) [YTNicoReplayHistory removeAllObjects];
    }

    NSMutableURLRequest *clone = [request mutableCopy];
    [clone setValue:@"1" forHTTPHeaderField:@"X-YTNico-Replay"];
    if (body.length > 0) clone.HTTPBody = body;
    clone.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    clone.timeoutInterval = 15.0;

    [[DebugInspector shared] log:@"Replay InnerTube %@", urlString];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:clone completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [[DebugInspector shared] log:@"Replay failed: %@", error.localizedDescription];
            return;
        }
        if (data.length > 0) {
            [YouTubeChatAdapter ingestPotentialInnertubeData:data request:clone];
        }
    }];
    [task resume];
}

@end

#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoForceFetchResponse)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId;
@end

static NSString *YTNicoWatchResponseLastVideoId;
static NSDate *YTNicoWatchResponseLastDate;

static NSString *YTNicoWRString(NSData *data) {
    if (data.length == 0 || data.length > 8 * 1024 * 1024) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *YTNicoWRFirstMatch(NSString *s, NSArray<NSString *> *patterns) {
    if (s.length == 0) return @"";
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static NSString *YTNicoWRVideoIdFromResponse(NSString *s) {
    NSString *v = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (v.length == 11) return v;
    return YTNicoWRFirstMatch(s, @[
        @"\"currentVideoEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"currentVideoEndpoint\\\".*?\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"watchEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"watchEndpoint\\\".*?\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"playerResponse\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\"videoDetails\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\""
    ]);
}

static BOOL YTNicoWRLooksLikeWatchResponse(NSString *url, NSString *s) {
    NSString *lower = url.lowercaseString ?: @"";
    if ([lower containsString:@"/youtubei/v1/next"]) return YES;
    if ([lower containsString:@"/youtubei/v1/player"] && ([s containsString:@"watchEndpoint"] || [s containsString:@"currentVideoEndpoint"] || [s containsString:@"videoDetails"])) return YES;
    if ([lower containsString:@"watch"]) return YES;
    if ([s containsString:@"currentVideoEndpoint"] || [s containsString:@"watchEndpoint"]) return YES;
    return NO;
}

static void YTNicoWRHandle(NSURLRequest *request, NSData *data) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return;
    NSString *url = request.URL.absoluteString ?: @"";
    if (![url.lowercaseString containsString:@"youtube"] && ![url.lowercaseString containsString:@"youtubei"]) return;
    NSString *s = YTNicoWRString(data);
    if (!YTNicoWRLooksLikeWatchResponse(url, s)) return;
    NSString *videoId = YTNicoWRVideoIdFromResponse(s);
    if (videoId.length != 11) return;

    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        BOOL sameRecent = [YTNicoWatchResponseLastVideoId isEqualToString:videoId] && YTNicoWatchResponseLastDate && [now timeIntervalSinceDate:YTNicoWatchResponseLastDate] < 10.0;
        if (sameRecent) return;
        YTNicoWatchResponseLastVideoId = [videoId copy];
        YTNicoWatchResponseLastDate = now;
    }

    [[DebugInspector shared] important:@"watch response auto fetch videoId=%@ url=%@", videoId, url.lowercaseString];
    dispatch_async(dispatch_get_main_queue(), ^{
        [YouTubeChatAdapter forceResetForVideoId:videoId];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![[YouTubeChatAdapter currentVideoId] isEqualToString:videoId]) return;
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"自動コメント取得開始: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        [YouTubeChatAdapter ytnico_fetchCommentsForVideoIdIgnoringThrottle:videoId];
    });
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoWRHandle(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoWRHandle(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, bodyData, wrapped);
}

%end

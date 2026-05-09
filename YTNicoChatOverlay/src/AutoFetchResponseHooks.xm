#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSString *YTNicoResponseLastVideoId;
static NSDate *YTNicoResponseLastDate;

static NSString *YTNicoResponseExtractVideoId(NSData *data) {
    if (data.length == 0 || data.length > 6 * 1024 * 1024) return @"";
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) return @"";
    NSString *v = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (v.length == 11) return v;
    NSArray<NSString *> *patterns = @[
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"currentVideoEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\"watchEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\"playerResponse\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\""
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static void YTNicoMaybeFetchFromResponse(NSURLRequest *request, NSData *data) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return;
    NSString *url = request.URL.absoluteString.lowercaseString ?: @"";
    if (![url containsString:@"youtube"] && ![url containsString:@"youtubei"]) return;
    if (![url containsString:@"/player"] && ![url containsString:@"/next"] && ![url containsString:@"/browse"] && ![url containsString:@"watch"]) return;
    NSString *videoId = YTNicoResponseExtractVideoId(data);
    if (videoId.length != 11) return;

    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        if ([YTNicoResponseLastVideoId isEqualToString:videoId] && YTNicoResponseLastDate && [now timeIntervalSinceDate:YTNicoResponseLastDate] < 35.0) return;
        if ([[YouTubeChatAdapter currentVideoId] isEqualToString:videoId] && YTNicoResponseLastDate && [now timeIntervalSinceDate:YTNicoResponseLastDate] < 35.0) return;
        YTNicoResponseLastVideoId = [videoId copy];
        YTNicoResponseLastDate = now;
    }

    [[DebugInspector shared] log:@"auto response fetch videoId=%@ url=%@", videoId, url];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"自動コメント取得開始: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
    });
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoMaybeFetchFromResponse(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoMaybeFetchFromResponse(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, bodyData, wrapped);
}

%end

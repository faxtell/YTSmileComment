#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoLiveReplayRescuePrivate)
+ (void)ingestPotentialInnertubeData:(NSData *)data request:(NSURLRequest *)request;
+ (NSString *)currentVideoId;
+ (void)fetchCommentsForVideoId:(NSString *)videoId;
+ (NSString *)extractVideoIdFromString:(NSString *)input;
@end

static NSString *YTNicoLRExtractVideoId(NSData *data, NSURLRequest *request) {
    NSString *fromURL = [YouTubeChatAdapter extractVideoIdFromString:request.URL.absoluteString ?: @""];
    if (fromURL.length == 11) return fromURL;
    if (data.length == 0 || data.length > 8 * 1024 * 1024) return @"";
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) return @"";
    NSArray<NSString *> *patterns = @[
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"videoId=([A-Za-z0-9_-]{11})"
    ];
    for (NSString *p in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:p options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static BOOL YTNicoLRLooksLikeChatResponse(NSURLRequest *request, NSData *data) {
    NSString *url = request.URL.absoluteString.lowercaseString ?: @"";
    if ([url containsString:@"live_chat"] || [url containsString:@"get_live_chat"]) return YES;
    if (data.length == 0 || data.length > 8 * 1024 * 1024) return NO;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) return NO;
    return [s rangeOfString:@"liveChatTextMessageRenderer"].location != NSNotFound ||
           [s rangeOfString:@"replayChatItemAction"].location != NSNotFound ||
           [s rangeOfString:@"videoOffsetTimeMsec"].location != NSNotFound ||
           [s rangeOfString:@"liveChatPaidMessageRenderer"].location != NSNotFound;
}

static void YTNicoLRHandleResponse(NSURLRequest *request, NSData *data) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return;
    if (!YTNicoLRLooksLikeChatResponse(request, data)) return;
    NSString *videoId = YTNicoLRExtractVideoId(data, request);
    if (videoId.length == 11 && ![[YouTubeChatAdapter currentVideoId] isEqualToString:videoId]) {
        [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
    }
    [[DebugInspector shared] log:@"rescue ingest chat response url=%@", request.URL.absoluteString];
    [YouTubeChatAdapter ingestPotentialInnertubeData:data request:request];
}

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoLRHandleResponse(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data.length > 0) YTNicoLRHandleResponse(request, data);
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, bodyData, wrapped);
}

%end

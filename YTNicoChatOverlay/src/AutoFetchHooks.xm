#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoForceFetch)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId;
@end

static NSString *YTNicoLastAutoVideoId;
static NSDate *YTNicoLastAutoDate;
static NSString *YTNicoLastWatchVideoId;
static NSDate *YTNicoLastWatchDate;
static NSDate *YTNicoLastClearDate;

static NSString *YTNicoStringFromData(NSData *data) {
    if (data.length == 0 || data.length > 2 * 1024 * 1024) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *YTNicoExtractVideoIdFromString(NSString *s) {
    if (s.length == 0) return @"";
    NSString *v = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (v.length == 11) return v;
    NSArray<NSString *> *patterns = @[
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"videoId=([A-Za-z0-9_-]{11})",
        @"\\\"watchEndpoint\\\".*?\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"watchEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"currentVideoEndpoint\\\".*?\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"currentVideoEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\""
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static NSString *YTNicoExtractVideoIdFromData(NSData *data) {
    return YTNicoExtractVideoIdFromString(YTNicoStringFromData(data));
}

static BOOL YTNicoLooksLikeWatchOpen(NSString *lowerURL, NSString *payload) {
    if ([lowerURL containsString:@"/watch?"] || [lowerURL containsString:@"youtube.com/watch"]) return YES;
    if ([lowerURL containsString:@"/youtubei/v1/next"]) return YES;
    if ([payload rangeOfString:@"watchEndpoint"].location != NSNotFound) return YES;
    if ([payload rangeOfString:@"currentVideoEndpoint"].location != NSNotFound) return YES;
    if ([payload rangeOfString:@"playerResponse"].location != NSNotFound && [payload rangeOfString:@"watchEndpoint"].location != NSNotFound) return YES;
    return NO;
}

static BOOL YTNicoLooksLikeHomeOrClose(NSString *lowerURL, NSString *payload) {
    if (![lowerURL containsString:@"/youtubei/v1/browse"] && ![lowerURL containsString:@"/browse"]) return NO;
    if (YTNicoExtractVideoIdFromString(payload).length == 11) return NO;
    NSArray<NSString *> *homeSignals = @[@"FEwhat_to_watch", @"FEsubscriptions", @"FEtrending", @"FElibrary", @"FEhistory", @"FEshorts", @"browseId"];
    for (NSString *sig in homeSignals) if ([payload rangeOfString:sig].location != NSNotFound) return YES;
    return [lowerURL containsString:@"/youtubei/v1/browse"];
}

static void YTNicoMaybeClearOnClose(NSURLRequest *request, NSData *body) {
    NSString *urlString = request.URL.absoluteString ?: @"";
    NSString *lower = urlString.lowercaseString;
    NSString *payload = YTNicoStringFromData(body ?: request.HTTPBody);
    if (!YTNicoLooksLikeHomeOrClose(lower, payload)) return;
    if ([YouTubeChatAdapter currentVideoId].length == 0) return;

    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        if (YTNicoLastClearDate && [now timeIntervalSinceDate:YTNicoLastClearDate] < 2.5) return;
        YTNicoLastClearDate = now;
    }

    [[DebugInspector shared] important:@"auto clear on close/home url=%@", lower];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YouTubeChatAdapter clearCurrentVideoAndComments];
    });
}

static void YTNicoMaybeAutoFetch(NSURLRequest *request, NSData *body) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    if (![request isKindOfClass:NSURLRequest.class]) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return;

    NSString *urlString = request.URL.absoluteString ?: @"";
    NSString *lower = urlString.lowercaseString;
    if (lower.length == 0) return;
    if (![lower containsString:@"youtube"] && ![lower containsString:@"youtubei"]) return;

    NSString *payload = YTNicoStringFromData(body ?: request.HTTPBody);
    NSString *videoId = [YouTubeChatAdapter extractVideoIdFromString:urlString];
    if (videoId.length != 11) videoId = YTNicoExtractVideoIdFromString(payload);

    if (videoId.length != 11) {
        YTNicoMaybeClearOnClose(request, body);
        return;
    }

    BOOL watchOpen = YTNicoLooksLikeWatchOpen(lower, payload);
    BOOL playerOnly = [lower containsString:@"/youtubei/v1/player"] && !watchOpen;
    NSDate *now = NSDate.date;
    BOOL shouldFetch = NO;
    BOOL forceFetch = NO;
    BOOL changedVideo = NO;

    @synchronized ([YouTubeChatAdapter class]) {
        changedVideo = ![YTNicoLastAutoVideoId isEqualToString:videoId];
        if (watchOpen) {
            BOOL recentSameWatch = [YTNicoLastWatchVideoId isEqualToString:videoId] && YTNicoLastWatchDate && [now timeIntervalSinceDate:YTNicoLastWatchDate] < 8.0;
            if (recentSameWatch) return;
            YTNicoLastWatchVideoId = [videoId copy];
            YTNicoLastWatchDate = now;
            YTNicoLastAutoVideoId = [videoId copy];
            YTNicoLastAutoDate = now;
            shouldFetch = YES;
            forceFetch = YES;
        } else {
            if (!changedVideo && YTNicoLastAutoDate && [now timeIntervalSinceDate:YTNicoLastAutoDate] < 45.0) return;
            YTNicoLastAutoVideoId = [videoId copy];
            YTNicoLastAutoDate = now;
            shouldFetch = YES;
            forceFetch = NO;
        }
    }
    if (!shouldFetch) return;

    [[DebugInspector shared] important:@"auto fetch videoId=%@ changed=%d watchOpen=%d playerOnly=%d force=%d url=%@", videoId, changedVideo, watchOpen, playerOnly, forceFetch, lower];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (forceFetch) [YouTubeChatAdapter forceResetForVideoId:videoId];
        else [YouTubeChatAdapter resetForVideoId:videoId];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((forceFetch ? 0.35 : 0.8) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![[YouTubeChatAdapter currentVideoId] isEqualToString:videoId]) return;
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"自動コメント取得開始: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        if (forceFetch) [YouTubeChatAdapter ytnico_fetchCommentsForVideoIdIgnoringThrottle:videoId];
        else [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
    });
}

%hook NSURLSessionTask
- (void)resume {
    NSURLRequest *req = self.currentRequest ?: self.originalRequest;
    YTNicoMaybeAutoFetch(req, req.HTTPBody);
    %orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    YTNicoMaybeAutoFetch(request, request.HTTPBody);
    return %orig(request);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    YTNicoMaybeAutoFetch(request, request.HTTPBody);
    return %orig(request, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    YTNicoMaybeAutoFetch(request, bodyData ?: request.HTTPBody);
    return %orig(request, bodyData);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    YTNicoMaybeAutoFetch(request, bodyData ?: request.HTTPBody);
    return %orig(request, bodyData, completionHandler);
}
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
        [[DebugInspector shared] important:@"YTNico auto fetch hooks loaded"];
    }
}

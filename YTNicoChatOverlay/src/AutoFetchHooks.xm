#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSString *YTNicoLastAutoVideoId;
static NSDate *YTNicoLastAutoDate;

static NSString *YTNicoExtractVideoIdFromData(NSData *data) {
    if (data.length == 0 || data.length > 1024 * 1024) return @"";
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length == 0) return @"";
    NSString *v = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (v.length == 11) return v;
    NSArray<NSString *> *patterns = @[
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"videoId=([A-Za-z0-9_-]{11})"
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
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

    NSString *videoId = [YouTubeChatAdapter extractVideoIdFromString:urlString];
    if (videoId.length != 11) videoId = YTNicoExtractVideoIdFromData(body ?: request.HTTPBody);
    if (videoId.length != 11) return;

    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        if ([YTNicoLastAutoVideoId isEqualToString:videoId] && YTNicoLastAutoDate && [now timeIntervalSinceDate:YTNicoLastAutoDate] < 45.0) return;
        YTNicoLastAutoVideoId = [videoId copy];
        YTNicoLastAutoDate = now;
    }

    [[DebugInspector shared] log:@"auto fetch videoId=%@", videoId];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"自動コメント取得開始: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        [YouTubeChatAdapter fetchCommentsForVideoId:videoId];
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
        [[DebugInspector shared] log:@"YTNico auto fetch hooks loaded"];
    }
}

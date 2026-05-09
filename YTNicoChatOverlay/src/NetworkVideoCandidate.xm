#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSString *YTNicoCandidateStringFromData(NSData *data) {
    if (data.length == 0 || data.length > 1024 * 1024) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *YTNicoCandidateVideoIdFromString(NSString *s) {
    if (s.length == 0) return @"";
    NSString *videoId = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (videoId.length == 11) return videoId;
    NSArray *patterns = @[
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"videoId=([A-Za-z0-9_-]{11})",
        @"\"watchEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\"",
        @"\"currentVideoEndpoint\".*?\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\""
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static void YTNicoRecordCandidateFromRequest(NSURLRequest *request, NSData *body) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return;
    NSString *url = request.URL.absoluteString ?: @"";
    NSString *lower = url.lowercaseString;
    if (![lower containsString:@"youtube"] && ![lower containsString:@"youtubei"]) return;
    NSString *videoId = YTNicoCandidateVideoIdFromString(url);
    if (videoId.length != 11) videoId = YTNicoCandidateVideoIdFromString(YTNicoCandidateStringFromData(body ?: request.HTTPBody));
    if (videoId.length == 11) [YouTubeChatAdapter noteDetectedVideoId:videoId source:@"network-candidate"];
}

%hook NSURLSessionTask
- (void)resume {
    NSURLRequest *req = self.currentRequest ?: self.originalRequest;
    YTNicoRecordCandidateFromRequest(req, req.HTTPBody);
    %orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    YTNicoRecordCandidateFromRequest(request, request.HTTPBody);
    return %orig(request);
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    YTNicoRecordCandidateFromRequest(request, request.HTTPBody);
    return %orig(request, completionHandler);
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    YTNicoRecordCandidateFromRequest(request, bodyData ?: request.HTTPBody);
    return %orig(request, bodyData);
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    YTNicoRecordCandidateFromRequest(request, bodyData ?: request.HTTPBody);
    return %orig(request, bodyData, completionHandler);
}
%end

#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static BOOL YTNicoDirectFetchActive = NO;

@implementation YouTubeChatAdapter (DirectFetch)

+ (NSString *)extractVideoIdFromString:(NSString *)input {
    if (![input isKindOfClass:NSString.class] || input.length == 0) return @"";
    NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *patterns = @[@"[?&]v=([A-Za-z0-9_-]{11})", @"youtu\\.be/([A-Za-z0-9_-]{11})", @"/shorts/([A-Za-z0-9_-]{11})", @"/live/([A-Za-z0-9_-]{11})", @"/embed/([A-Za-z0-9_-]{11})", @"^([A-Za-z0-9_-]{11})$"];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

+ (void)fetchCommentsForVideoId:(NSString *)videoId {
    videoId = [self ytdf_norm:videoId];
    if (videoId.length != 11) return;
    @synchronized (self) { if (YTNicoDirectFetchActive) return; YTNicoDirectFetchActive = YES; }
    [[DebugInspector shared] log:@"direct fetch start videoId=%@", videoId];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { [self ytdf_finish]; return; }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) { [self ytdf_finish]; return; }
        [self ytdf_processWatchHTML:html videoId:videoId];
    }];
    [task resume];
}

+ (void)ytdf_processWatchHTML:(NSString *)html videoId:(NSString *)videoId {
    NSString *apiKey = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    NSString *clientVersion = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    if (clientVersion.length == 0) clientVersion = @"2.20250101.01.00";
    if (apiKey.length == 0) { [self ytdf_finish]; return; }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    NSDictionary *body = @{@"context":@{@"client":@{@"clientName":@"WEB", @"clientVersion":clientVersion, @"hl":@"ja", @"gl":@"JP"}}, @"videoId":videoId};
    [self ytdf_postURL:url body:body completion:^(NSString *text) {
        if (text.length > 0) [self ytdf_parseResponseString:text maxCount:30];
        [self ytdf_finish];
    }];
}

+ (void)ytdf_postURL:(NSURL *)url body:(NSDictionary *)body completion:(void (^)(NSString *text))completion {
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!url || json.length == 0) { if (completion) completion(@""); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = json;
    req.timeoutInterval = 20.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { if (completion) completion(@""); return; }
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (completion) completion(s ?: @"");
    }];
    [task resume];
}

+ (void)ytdf_parseResponseString:(NSString *)s maxCount:(NSInteger)maxCount {
    if (s.length == 0) return;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\\"authorText\\\"\\s*:\\s*\\{\\s*\\\"simpleText\\\"\\s*:\\s*\\\"([^\\\"]+)\\\".*?\\\"contentText\\\"\\s*:\\s*\\{\\s*\\\"runs\\\"\\s*:\\s*\\[(.*?)\\]" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    NSInteger count = 0;
    for (NSTextCheckingResult *m in matches) {
        if (count >= maxCount) break;
        if (m.numberOfRanges < 3) continue;
        NSString *author = [self ytdf_unescape:[s substringWithRange:[m rangeAtIndex:1]]];
        NSString *runs = [s substringWithRange:[m rangeAtIndex:2]];
        NSString *text = [self ytdf_textFromRunsString:runs];
        if (text.length == 0) continue;
        NSString *mid = [NSString stringWithFormat:@"direct-%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@", author, text] hash]];
        [YouTubeChatAdapter broadcastAuthor:author text:text messageId:mid];
        count++;
    }
    [[DebugInspector shared] log:@"direct string parser emitted %ld", (long)count];
}

+ (NSString *)ytdf_textFromRunsString:(NSString *)runs {
    NSMutableString *out = [NSMutableString string];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\\"text\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:runs options:0 range:NSMakeRange(0, runs.length)];
    for (NSTextCheckingResult *m in matches) if (m.numberOfRanges >= 2) [out appendString:[self ytdf_unescape:[runs substringWithRange:[m rangeAtIndex:1]]]];
    return [self ytdf_norm:out];
}

+ (NSString *)ytdf_matchFirst:(NSString *)text pattern:(NSString *)pattern {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return @"";
    return [text substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)ytdf_unescape:(NSString *)s {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
    return s;
}

+ (NSString *)ytdf_norm:(id)obj {
    if (![obj isKindOfClass:NSString.class]) return @"";
    NSString *s = [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s;
}

+ (void)ytdf_finish { @synchronized (self) { YTNicoDirectFetchActive = NO; } }

@end

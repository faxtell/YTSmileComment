#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static BOOL YTNicoDirectFetchActive = NO;

@implementation YouTubeChatAdapter (DirectFetch)

+ (NSString *)extractVideoIdFromString:(NSString *)input {
    if (![input isKindOfClass:NSString.class] || input.length == 0) return @"";
    NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *patterns = @[
        @"[?&]v=([A-Za-z0-9_-]{11})",
        @"youtu\\.be/([A-Za-z0-9_-]{11})",
        @"/shorts/([A-Za-z0-9_-]{11})",
        @"/live/([A-Za-z0-9_-]{11})",
        @"/embed/([A-Za-z0-9_-]{11})",
        @"^([A-Za-z0-9_-]{11})$"
    ];
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
    @synchronized (self) {
        if (YTNicoDirectFetchActive) return;
        YTNicoDirectFetchActive = YES;
    }
    [[DebugInspector shared] log:@"direct fetch start videoId=%@", videoId];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            [[DebugInspector shared] log:@"direct watch fetch failed: %@", error.localizedDescription ?: @"empty"];
            @synchronized (self) { YTNicoDirectFetchActive = NO; }
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) {
            @synchronized (self) { YTNicoDirectFetchActive = NO; }
            return;
        }
        [self ytdf_processWatchHTML:html videoId:videoId];
    }];
    [task resume];
}

+ (void)ytdf_processWatchHTML:(NSString *)html videoId:(NSString *)videoId {
    NSString *apiKey = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    NSString *clientVersion = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    if (clientVersion.length == 0) clientVersion = @"2.20250101.01.00";
    if (apiKey.length == 0) {
        [[DebugInspector shared] log:@"direct fetch missing api key"];
        @synchronized (self) { YTNicoDirectFetchActive = NO; }
        return;
    }

    // Safety: avoid parsing the full huge ytInitialData here. It can be very large
    // and can trigger duplicate parser paths. Use the lightweight /next request first.
    NSDictionary *body = @{@"context":[self ytdf_context:clientVersion], @"videoId":videoId};
    [self ytdf_postNextWithKey:apiKey version:clientVersion body:body round:0];
}

+ (NSDictionary *)ytdf_context:(NSString *)version {
    return @{@"client":@{@"clientName":@"WEB", @"clientVersion":version ?: @"2.20250101.01.00", @"hl":@"ja", @"gl":@"JP"}};
}

+ (void)ytdf_postNextWithKey:(NSString *)apiKey version:(NSString *)version body:(NSDictionary *)body round:(NSInteger)round {
    if (round > 1) {
        @synchronized (self) { YTNicoDirectFetchActive = NO; }
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    [self ytdf_postURL:url body:body completion:^(id obj) {
        if (!obj) {
            @synchronized (self) { YTNicoDirectFetchActive = NO; }
            return;
        }
        [YouTubeChatAdapter ingestPotentialJSONObject:obj];

        // Safety: follow only one likely comment continuation, not every token.
        NSString *token = [self ytdf_findFirstContinuationToken:obj depth:0];
        if (token.length > 0 && round == 0) {
            NSDictionary *nextBody = @{@"context":[self ytdf_context:version], @"continuation":token};
            [self ytdf_postNextWithKey:apiKey version:version body:nextBody round:1];
        } else {
            @synchronized (self) { YTNicoDirectFetchActive = NO; }
        }
    }];
}

+ (void)ytdf_postURL:(NSURL *)url body:(NSDictionary *)body completion:(void (^)(id obj))completion {
    if (!url || !body) { if (completion) completion(nil); return; }
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (json.length == 0) { if (completion) completion(nil); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = json;
    req.timeoutInterval = 20.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-Replay"];
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { if (completion) completion(nil); return; }
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (completion) completion(obj);
    }];
    [task resume];
}

+ (NSString *)ytdf_findFirstContinuationToken:(id)obj depth:(NSInteger)depth {
    if (!obj || depth > 60) return @"";
    if ([obj isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)obj) {
            NSString *t = [self ytdf_findFirstContinuationToken:x depth:depth + 1];
            if (t.length > 0) return t;
        }
        return @"";
    }
    if (![obj isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = obj;
    NSDictionary *cmd = [d[@"continuationCommand"] isKindOfClass:NSDictionary.class] ? d[@"continuationCommand"] : nil;
    NSString *token = [self ytdf_norm:cmd[@"token"]];
    if (token.length > 0) return token;
    for (id v in d.allValues) {
        NSString *t = [self ytdf_findFirstContinuationToken:v depth:depth + 1];
        if (t.length > 0) return t;
    }
    return @"";
}

+ (NSString *)ytdf_matchFirst:(NSString *)text pattern:(NSString *)pattern {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return @"";
    return [text substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)ytdf_norm:(id)obj {
    if (![obj isKindOfClass:NSString.class]) return @"";
    return [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end

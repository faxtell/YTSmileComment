#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

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
    [[DebugInspector shared] log:@"direct fetch start videoId=%@", videoId];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) {
            [[DebugInspector shared] log:@"direct watch fetch failed: %@", error.localizedDescription ?: @"empty"];
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) return;
        [self ytdf_processWatchHTML:html videoId:videoId];
    }];
    [task resume];
}

+ (void)ytdf_processWatchHTML:(NSString *)html videoId:(NSString *)videoId {
    NSString *apiKey = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    NSString *clientVersion = [self ytdf_matchFirst:html pattern:@"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""];
    if (clientVersion.length == 0) clientVersion = @"2.20250101.01.00";

    NSString *initial = [self ytdf_extractJSONAfterMarker:html marker:@"var ytInitialData = "];
    if (initial.length == 0) initial = [self ytdf_extractJSONAfterMarker:html marker:@"ytInitialData = "];
    if (initial.length > 0) {
        NSData *jsonData = [initial dataUsingEncoding:NSUTF8StringEncoding];
        id obj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (obj) {
            [YouTubeChatAdapter ingestPotentialJSONObject:obj];
            NSMutableSet<NSString *> *nextTokens = [NSMutableSet set];
            NSMutableSet<NSString *> *liveTokens = [NSMutableSet set];
            [self ytdf_collectTokens:obj next:nextTokens live:liveTokens depth:0];
            [self ytdf_fetchTokensWithKey:apiKey version:clientVersion nextTokens:nextTokens liveTokens:liveTokens round:0];
        }
    }

    if (apiKey.length == 0) {
        [[DebugInspector shared] log:@"direct fetch missing api key"];
        return;
    }
    [self ytdf_postNextWithKey:apiKey version:clientVersion body:@{@"context":[self ytdf_context:clientVersion], @"videoId":videoId} round:0];
}

+ (NSDictionary *)ytdf_context:(NSString *)version {
    return @{@"client":@{@"clientName":@"WEB", @"clientVersion":version ?: @"2.20250101.01.00", @"hl":@"ja", @"gl":@"JP"}};
}

+ (void)ytdf_fetchTokensWithKey:(NSString *)apiKey version:(NSString *)version nextTokens:(NSSet<NSString *> *)nextTokens liveTokens:(NSSet<NSString *> *)liveTokens round:(NSInteger)round {
    if (apiKey.length == 0 || round > 2) return;
    NSInteger count = 0;
    for (NSString *token in nextTokens) {
        if (count++ >= 8) break;
        [self ytdf_postNextWithKey:apiKey version:version body:@{@"context":[self ytdf_context:version], @"continuation":token} round:round + 1];
    }
    count = 0;
    for (NSString *token in liveTokens) {
        if (count++ >= 4) break;
        [self ytdf_postLiveWithKey:apiKey version:version token:token round:round + 1];
    }
}

+ (void)ytdf_postNextWithKey:(NSString *)apiKey version:(NSString *)version body:(NSDictionary *)body round:(NSInteger)round {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    [self ytdf_postURL:url body:body completion:^(id obj) {
        if (!obj) return;
        [YouTubeChatAdapter ingestPotentialJSONObject:obj];
        NSMutableSet<NSString *> *nextTokens = [NSMutableSet set];
        NSMutableSet<NSString *> *liveTokens = [NSMutableSet set];
        [self ytdf_collectTokens:obj next:nextTokens live:liveTokens depth:0];
        [self ytdf_fetchTokensWithKey:apiKey version:version nextTokens:nextTokens liveTokens:liveTokens round:round];
    }];
}

+ (void)ytdf_postLiveWithKey:(NSString *)apiKey version:(NSString *)version token:(NSString *)token round:(NSInteger)round {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytdf_context:version], @"continuation":token};
    [self ytdf_postURL:url body:body completion:^(id obj) {
        if (!obj) return;
        [YouTubeChatAdapter ingestPotentialJSONObject:obj];
        if (round > 2) return;
        NSMutableSet<NSString *> *nextTokens = [NSMutableSet set];
        NSMutableSet<NSString *> *liveTokens = [NSMutableSet set];
        [self ytdf_collectTokens:obj next:nextTokens live:liveTokens depth:0];
        [self ytdf_fetchTokensWithKey:apiKey version:version nextTokens:nextTokens liveTokens:liveTokens round:round];
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
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { if (completion) completion(nil); return; }
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (completion) completion(obj);
    }];
    [task resume];
}

+ (void)ytdf_collectTokens:(id)obj next:(NSMutableSet<NSString *> *)nextTokens live:(NSMutableSet<NSString *> *)liveTokens depth:(NSInteger)depth {
    if (!obj || depth > 80) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)obj) [self ytdf_collectTokens:x next:nextTokens live:liveTokens depth:depth + 1];
        return;
    }
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = obj;
    NSArray *liveKeys = @[@"timedContinuationData", @"invalidationContinuationData", @"reloadContinuationData"];
    for (NSString *k in liveKeys) {
        NSDictionary *v = [d[k] isKindOfClass:NSDictionary.class] ? d[k] : nil;
        NSString *token = [self ytdf_norm:v[@"continuation"]];
        if (token.length > 0) [liveTokens addObject:token];
    }
    NSDictionary *cmd = [d[@"continuationCommand"] isKindOfClass:NSDictionary.class] ? d[@"continuationCommand"] : nil;
    NSString *token = [self ytdf_norm:cmd[@"token"]];
    if (token.length > 0) [nextTokens addObject:token];
    for (id v in d.allValues) [self ytdf_collectTokens:v next:nextTokens live:liveTokens depth:depth + 1];
}

+ (NSString *)ytdf_matchFirst:(NSString *)text pattern:(NSString *)pattern {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return @"";
    return [text substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)ytdf_extractJSONAfterMarker:(NSString *)text marker:(NSString *)marker {
    NSRange r = [text rangeOfString:marker];
    if (r.location == NSNotFound) return @"";
    NSUInteger i = r.location + r.length;
    while (i < text.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text characterAtIndex:i]]) i++;
    if (i >= text.length || [text characterAtIndex:i] != '{') return @"";
    NSUInteger start = i;
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL escape = NO;
    for (; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (inString) {
            if (escape) escape = NO;
            else if (c == '\\') escape = YES;
            else if (c == '"') inString = NO;
        } else {
            if (c == '"') inString = YES;
            else if (c == '{') depth++;
            else if (c == '}') {
                depth--;
                if (depth == 0) return [text substringWithRange:NSMakeRange(start, i - start + 1)];
            }
        }
    }
    return @"";
}

+ (NSString *)ytdf_norm:(id)obj {
    if (![obj isKindOfClass:NSString.class]) return @"";
    return [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@end

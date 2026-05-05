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
    NSString *apiKey = [self ytdf_firstMatchIn:html patterns:@[
        @"\"INNERTUBE_API_KEY\"\\s*:\\s*\"([^\"]+)\"",
        @"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
    ]];
    NSString *clientVersion = [self ytdf_firstMatchIn:html patterns:@[
        @"\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\"",
        @"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
    ]];
    if (clientVersion.length == 0) clientVersion = @"2.20250101.01.00";
    if (apiKey.length == 0) { [self ytdf_finish]; return; }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    NSDictionary *body = @{@"context":@{@"client":@{@"clientName":@"WEB", @"clientVersion":clientVersion, @"hl":@"ja", @"gl":@"JP"}}, @"videoId":videoId};
    [self ytdf_postURL:url body:body completion:^(NSString *text) {
        NSInteger emitted = 0;
        if (text.length > 0) emitted = [self ytdf_parseResponseString:text maxCount:40];
        if (emitted == 0) {
            NSString *token = [self ytdf_firstContinuationTokenInString:text];
            if (token.length > 0) {
                NSDictionary *nextBody = @{@"context":@{@"client":@{@"clientName":@"WEB", @"clientVersion":clientVersion, @"hl":@"ja", @"gl":@"JP"}}, @"continuation":token};
                [self ytdf_postURL:url body:nextBody completion:^(NSString *text2) {
                    NSInteger emitted2 = text2.length > 0 ? [self ytdf_parseResponseString:text2 maxCount:40] : 0;
                    if (emitted2 == 0) [YouTubeChatAdapter broadcastAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
                    [self ytdf_finish];
                }];
            } else {
                [YouTubeChatAdapter broadcastAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
                [self ytdf_finish];
            }
        } else {
            [self ytdf_finish];
        }
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

+ (NSInteger)ytdf_parseResponseString:(NSString *)s maxCount:(NSInteger)maxCount {
    if (s.length == 0) return 0;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    __block NSInteger count = 0;

    void (^emit)(NSString *, NSString *) = ^(NSString *author, NSString *text) {
        if (count >= maxCount) return;
        author = [self ytdf_norm:[self ytdf_unescape:author]];
        text = [self ytdf_norm:[self ytdf_unescape:text]];
        if (text.length == 0) return;
        if (author.length == 0) author = @"comment";
        NSString *key = [NSString stringWithFormat:@"%@|%@", author, text];
        if ([seen containsObject:key]) return;
        [seen addObject:key];
        NSString *mid = [NSString stringWithFormat:@"direct-%lu", (unsigned long)key.hash];
        [YouTubeChatAdapter broadcastAuthor:author text:text messageId:mid];
        count++;
    };

    NSRegularExpression *classic = [NSRegularExpression regularExpressionWithPattern:@"\"authorText\"\\s*:\\s*\\{\\s*\"simpleText\"\\s*:\\s*\"([^\"]+)\".*?\"contentText\"\\s*:\\s*\\{\\s*\"runs\"\\s*:\\s*\\[(.*?)\\]" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    for (NSTextCheckingResult *m in [classic matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        if (count >= maxCount) break;
        if (m.numberOfRanges < 3) continue;
        NSString *author = [s substringWithRange:[m rangeAtIndex:1]];
        NSString *text = [self ytdf_textFromRunsString:[s substringWithRange:[m rangeAtIndex:2]]];
        emit(author, text);
    }

    NSArray<NSString *> *rendererKeys = @[@"commentRenderer", @"commentViewModel", @"commentEntityPayload", @"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer"];
    for (NSString *key in rendererKeys) {
        if (count >= maxCount) break;
        for (NSString *block in [self ytdf_blocksForKey:key inString:s limit:80]) {
            if (count >= maxCount) break;
            NSString *author = [self ytdf_firstMatchIn:block patterns:@[
                @"\"authorText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
                @"\"authorName\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
                @"\"authorName\".*?\"text\"\\s*:\\s*\"([^\"]+)\"",
                @"\"displayName\"\\s*:\\s*\"([^\"]+)\"",
                @"\"name\"\\s*:\\s*\"([^\"]+)\""
            ]];
            NSString *text = @"";
            NSString *runs = [self ytdf_firstMatchIn:block patterns:@[
                @"\"contentText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]",
                @"\"message\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]",
                @"\"bodyText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]"
            ]];
            if (runs.length > 0) text = [self ytdf_textFromRunsString:runs];
            if (text.length == 0) {
                text = [self ytdf_firstMatchIn:block patterns:@[
                    @"\"contentText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
                    @"\"commentText\"\\s*:\\s*\"([^\"]+)\"",
                    @"\"bodyText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
                    @"\"content\"\\s*:\\s*\"([^\"]+)\"",
                    @"\"message\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\""
                ]];
            }
            emit(author, text);
        }
    }

    [[DebugInspector shared] log:@"direct string parser emitted %ld", (long)count];
    return count;
}

+ (NSArray<NSString *> *)ytdf_blocksForKey:(NSString *)key inString:(NSString *)s limit:(NSInteger)limit {
    NSMutableArray<NSString *> *blocks = [NSMutableArray array];
    NSString *marker = [NSString stringWithFormat:@"\"%@\"", key];
    NSRange search = NSMakeRange(0, s.length);
    while (blocks.count < limit) {
        NSRange r = [s rangeOfString:marker options:0 range:search];
        if (r.location == NSNotFound) break;
        NSRange braceSearch = NSMakeRange(NSMaxRange(r), s.length - NSMaxRange(r));
        NSRange br = [s rangeOfString:@"{" options:0 range:braceSearch];
        if (br.location == NSNotFound) break;
        NSString *block = [self ytdf_balancedObjectFromString:s start:br.location maxLength:22000];
        if (block.length > 0) [blocks addObject:block];
        NSUInteger next = br.location + MAX((NSUInteger)1, block.length);
        if (next >= s.length) break;
        search = NSMakeRange(next, s.length - next);
    }
    return blocks;
}

+ (NSString *)ytdf_firstContinuationTokenInString:(NSString *)s {
    if (s.length == 0) return @"";
    NSArray<NSString *> *patterns = @[
        @"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"",
        @"\"nextContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\"",
        @"\"reloadContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\""
    ];
    return [self ytdf_firstMatchIn:s patterns:patterns];
}

+ (NSString *)ytdf_balancedObjectFromString:(NSString *)s start:(NSUInteger)start maxLength:(NSUInteger)maxLength {
    if (start >= s.length || [s characterAtIndex:start] != '{') return @"";
    NSUInteger endLimit = MIN(s.length, start + maxLength);
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL escape = NO;
    for (NSUInteger i = start; i < endLimit; i++) {
        unichar c = [s characterAtIndex:i];
        if (inString) {
            if (escape) escape = NO;
            else if (c == '\\') escape = YES;
            else if (c == '"') inString = NO;
        } else {
            if (c == '"') inString = YES;
            else if (c == '{') depth++;
            else if (c == '}') {
                depth--;
                if (depth == 0) return [s substringWithRange:NSMakeRange(start, i - start + 1)];
            }
        }
    }
    return @"";
}

+ (NSString *)ytdf_firstMatchIn:(NSString *)s patterns:(NSArray<NSString *> *)patterns {
    for (NSString *pattern in patterns) {
        NSString *m = [self ytdf_matchFirst:s pattern:pattern];
        if (m.length > 0) return m;
    }
    return @"";
}

+ (NSString *)ytdf_textFromRunsString:(NSString *)runs {
    NSMutableString *out = [NSMutableString string];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\"text\"\\s*:\\s*\"([^\"]*)\"" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [re matchesInString:runs options:0 range:NSMakeRange(0, runs.length)];
    for (NSTextCheckingResult *m in matches) if (m.numberOfRanges >= 2) [out appendString:[self ytdf_unescape:[runs substringWithRange:[m rangeAtIndex:1]]]];
    return [self ytdf_norm:out];
}

+ (NSString *)ytdf_matchFirst:(NSString *)text pattern:(NSString *)pattern {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || m.numberOfRanges < 2) return @"";
    return [text substringWithRange:[m rangeAtIndex:1]];
}

+ (NSString *)ytdf_unescape:(NSString *)s {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003c" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003e" withString:@">"];
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

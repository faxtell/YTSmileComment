#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"
#import <QuartzCore/QuartzCore.h>
#import <stdlib.h>

static BOOL YTNicoDirectFetchActive = NO;
static const NSInteger YTNicoMaxCommentPages = 8;
static const NSInteger YTNicoMaxChatPages = 10;
static const NSInteger YTNicoMaxLivePolls = 180;
static unsigned long long YTNicoReplayBaseUsec = 0;
static CFTimeInterval YTNicoReplayStartTime = 0;

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
    [YouTubeChatAdapter resetForVideoId:videoId];
    NSUInteger generation = [YouTubeChatAdapter currentGeneration];
    @synchronized (self) { if (YTNicoDirectFetchActive) return; YTNicoDirectFetchActive = YES; }
    YTNicoReplayBaseUsec = 0;
    YTNicoReplayStartTime = CACurrentMediaTime();
    [[DebugInspector shared] log:@"direct fetch start videoId=%@ generation=%lu", videoId, (unsigned long)generation];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
        if (error || data.length == 0) { [self ytdf_finish]; return; }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) { [self ytdf_finish]; return; }
        [self ytdf_processWatchHTML:html videoId:videoId generation:generation];
    }];
    [task resume];
}

+ (void)ytdf_processWatchHTML:(NSString *)html videoId:(NSString *)videoId generation:(NSUInteger)generation {
    if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
    NSString *apiKey = [self ytdf_firstMatchIn:html patterns:@[@"\"INNERTUBE_API_KEY\"\\s*:\\s*\"([^\"]+)\"", @"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""]];
    NSString *clientVersion = [self ytdf_firstMatchIn:html patterns:@[@"\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\"", @"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""]];
    if (clientVersion.length == 0) clientVersion = @"2.20250101.01.00";
    if (apiKey.length == 0) { [self ytdf_finish]; return; }

    NSURL *nextURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytdf_context:clientVersion], @"videoId":videoId};
    [self ytdf_postURL:nextURL body:body completion:^(NSString *text) {
        if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
        if (text.length == 0) { [self ytdf_finish]; return; }

        NSString *liveToken = [self ytdf_firstLiveContinuationTokenInString:text];
        NSString *replayToken = [self ytdf_firstReplayContinuationTokenInString:text];
        BOOL hasReplaySignal = [self ytdf_hasReplaySignal:text] || replayToken.length > 0;
        BOOL liveNow = [self ytdf_isProbablyLiveNow:text];
        BOOL preferChat = SettingsManager.shared.preferLiveChat;
        if (preferChat && (liveToken.length > 0 || replayToken.length > 0)) {
            if (hasReplaySignal || !liveNow) {
                NSString *token = replayToken.length ? replayToken : liveToken;
                [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"チャットリプレイを時刻同期で取得します" messageId:NSUUID.UUID.UUIDString];
                [self ytdf_fetchLiveReplayWithKey:apiKey version:clientVersion token:token page:0 totalEmitted:0 generation:generation];
            } else {
                [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"ライブチャットをリアルタイム取得します" messageId:NSUUID.UUID.UUIDString];
                [self ytdf_pollLiveChatWithKey:apiKey version:clientVersion token:liveToken poll:0 generation:generation];
            }
            return;
        }

        NSInteger emitted = [self ytdf_parseResponseString:text maxCount:50 mode:0 generation:generation];
        NSString *token = [self ytdf_firstCommentContinuationTokenInString:text];
        if (token.length > 0) [self ytdf_fetchCommentContinuationWithKey:apiKey version:clientVersion token:token page:1 totalEmitted:emitted generation:generation];
        else {
            if (emitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
            [self ytdf_finish];
        }
    }];
}

+ (NSDictionary *)ytdf_context:(NSString *)clientVersion {
    return @{@"client":@{@"clientName":@"WEB", @"clientVersion":clientVersion ?: @"2.20250101.01.00", @"hl":@"ja", @"gl":@"JP"}};
}

+ (BOOL)ytdf_isProbablyLiveNow:(NSString *)s {
    if ([self ytdf_hasReplaySignal:s]) return NO;
    if ([s rangeOfString:@"\"isLiveNow\":true"].location != NSNotFound) return YES;
    if ([s rangeOfString:@"\"isLive\":true"].location != NSNotFound && [s rangeOfString:@"get_live_chat_replay"].location == NSNotFound) return YES;
    if ([s rangeOfString:@"LIVE_STREAM_OFFLINE"].location != NSNotFound) return NO;
    if ([s rangeOfString:@"liveChatRenderer"].location != NSNotFound && [s rangeOfString:@"get_live_chat_replay"].location == NSNotFound) return YES;
    return NO;
}

+ (BOOL)ytdf_hasReplaySignal:(NSString *)s {
    if (s.length == 0) return NO;
    NSArray<NSString *> *signals = @[@"get_live_chat_replay", @"liveChatReplayContinuationData", @"replayContinuationData", @"\"isLiveContent\":false", @"\"isUpcoming\":false"];
    for (NSString *sig in signals) if ([s rangeOfString:sig].location != NSNotFound) return YES;
    if ([s rangeOfString:@"\"isLiveNow\":true"].location == NSNotFound && [s rangeOfString:@"liveChatRenderer"].location != NSNotFound) return YES;
    return NO;
}

+ (void)ytdf_fetchCommentContinuationWithKey:(NSString *)apiKey version:(NSString *)version token:(NSString *)token page:(NSInteger)page totalEmitted:(NSInteger)totalEmitted generation:(NSUInteger)generation {
    if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
    if (page > YTNicoMaxCommentPages || token.length == 0) {
        if (totalEmitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
        [self ytdf_finish];
        return;
    }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytdf_context:version], @"continuation":token};
    [self ytdf_postURL:url body:body completion:^(NSString *text) {
        if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
        NSInteger emitted = text.length > 0 ? [self ytdf_parseResponseString:text maxCount:70 mode:0 generation:generation] : 0;
        NSString *nextToken = text.length > 0 ? [self ytdf_firstCommentContinuationTokenInString:text] : @"";
        if (nextToken.length > 0 && page < YTNicoMaxCommentPages) [self ytdf_fetchCommentContinuationWithKey:apiKey version:version token:nextToken page:page + 1 totalEmitted:totalEmitted + emitted generation:generation];
        else {
            if (totalEmitted + emitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
            [self ytdf_finish];
        }
    }];
}

+ (void)ytdf_pollLiveChatWithKey:(NSString *)apiKey version:(NSString *)version token:(NSString *)token poll:(NSInteger)poll generation:(NSUInteger)generation {
    if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
    if (poll > YTNicoMaxLivePolls || token.length == 0) { [self ytdf_finish]; return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytdf_context:version], @"continuation":token};
    [self ytdf_postURL:url body:body completion:^(NSString *text) {
        if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
        NSInteger emitted = text.length > 0 ? [self ytdf_parseResponseString:text maxCount:80 mode:1 generation:generation] : 0;
        NSString *nextToken = text.length > 0 ? [self ytdf_firstLiveContinuationTokenInString:text] : @"";
        NSTimeInterval delay = emitted > 0 ? 2.2 : 3.5;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
            [self ytdf_pollLiveChatWithKey:apiKey version:version token:(nextToken.length ? nextToken : token) poll:poll + 1 generation:generation];
        });
    }];
}

+ (void)ytdf_fetchLiveReplayWithKey:(NSString *)apiKey version:(NSString *)version token:(NSString *)token page:(NSInteger)page totalEmitted:(NSInteger)totalEmitted generation:(NSUInteger)generation {
    if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
    if (page > YTNicoMaxChatPages || token.length == 0) {
        if (totalEmitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: チャットリプレイを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
        [self ytdf_finish];
        return;
    }

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytdf_context:version], @"continuation":token};
    [self ytdf_postURL:url body:body completion:^(NSString *text) {
        if (![self ytdf_isGenerationCurrent:generation]) { [self ytdf_finish]; return; }
        NSInteger emitted = text.length > 0 ? [self ytdf_parseResponseString:text maxCount:90 mode:2 generation:generation] : 0;
        NSString *nextToken = text.length > 0 ? ([self ytdf_firstReplayContinuationTokenInString:text].length ? [self ytdf_firstReplayContinuationTokenInString:text] : [self ytdf_firstLiveContinuationTokenInString:text]) : @"";
        if (nextToken.length > 0 && page < YTNicoMaxChatPages) [self ytdf_fetchLiveReplayWithKey:apiKey version:version token:nextToken page:page + 1 totalEmitted:totalEmitted + emitted generation:generation];
        else {
            if (totalEmitted + emitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: チャットリプレイを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
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

+ (NSInteger)ytdf_parseResponseString:(NSString *)s maxCount:(NSInteger)maxCount mode:(NSInteger)mode generation:(NSUInteger)generation {
    if (s.length == 0 || ![self ytdf_isGenerationCurrent:generation]) return 0;
    __block NSInteger count = 0;
    BOOL liveNow = (mode == 1);
    BOOL replay = (mode == 2);

    void (^emit)(NSString *, NSString *, unsigned long long) = ^(NSString *author, NSString *text, unsigned long long timestampUsec) {
        if (count >= maxCount || ![self ytdf_isGenerationCurrent:generation]) return;
        author = [self ytdf_norm:[self ytdf_unescape:author]];
        text = [self ytdf_norm:[self ytdf_unescape:text]];
        if (text.length == 0) return;
        if (author.length == 0) author = (mode == 0) ? @"comment" : @"chat";
        NSString *key = [NSString stringWithFormat:@"%@|%@|%llu|%lu", author, text, timestampUsec, (unsigned long)generation];
        NSString *mid = [NSString stringWithFormat:@"direct-%lu", (unsigned long)key.hash];
        if (replay && SettingsManager.shared.syncReplayToTimestamp && timestampUsec > 0) [self ytdf_emitReplayAuthor:author text:text messageId:mid timestampUsec:timestampUsec generation:generation];
        else if (liveNow) [YouTubeChatAdapter emitNowAuthor:author text:text messageId:mid];
        else [YouTubeChatAdapter broadcastAuthor:author text:text messageId:mid];
        count++;
    };

    NSArray<NSString *> *rendererKeys = (mode == 0) ?
        @[@"commentRenderer", @"commentViewModel", @"commentEntityPayload", @"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer"] :
        @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer", @"liveChatPaidStickerRenderer"];

    for (NSString *key in rendererKeys) {
        if (count >= maxCount) break;
        for (NSString *block in [self ytdf_blocksForKey:key inString:s limit:180]) {
            if (count >= maxCount) break;
            NSString *author = [self ytdf_firstMatchIn:block patterns:@[@"\"authorText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"authorName\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"authorName\".*?\"text\"\\s*:\\s*\"([^\"]+)\"", @"\"displayName\"\\s*:\\s*\"([^\"]+)\"", @"\"name\"\\s*:\\s*\"([^\"]+)\""]];
            NSString *text = @"";
            NSString *runs = [self ytdf_firstMatchIn:block patterns:@[@"\"contentText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]", @"\"message\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]", @"\"bodyText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]"]];
            if (runs.length > 0) text = [self ytdf_textFromRunsString:runs];
            if (text.length == 0) text = [self ytdf_firstMatchIn:block patterns:@[@"\"contentText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"commentText\"\\s*:\\s*\"([^\"]+)\"", @"\"bodyText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"content\"\\s*:\\s*\"([^\"]+)\"", @"\"message\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\""]];
            NSString *tsString = [self ytdf_firstMatchIn:block patterns:@[@"\"timestampUsec\"\\s*:\\s*\"?([0-9]+)\"?", @"\"timestamp\"\\s*:\\s*\"?([0-9]{6,})\"?"]];
            unsigned long long ts = [self ytdf_unsignedLongLongFromString:tsString];
            emit(author, text, ts);
        }
    }
    [[DebugInspector shared] log:@"direct parser emitted %ld mode=%ld generation=%lu", (long)count, (long)mode, (unsigned long)generation];
    return count;
}

+ (void)ytdf_emitReplayAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId timestampUsec:(unsigned long long)timestampUsec generation:(NSUInteger)generation {
    @synchronized (self) {
        if (YTNicoReplayBaseUsec == 0 || timestampUsec < YTNicoReplayBaseUsec) {
            YTNicoReplayBaseUsec = timestampUsec;
            YTNicoReplayStartTime = CACurrentMediaTime();
        }
    }
    NSTimeInterval delay = (NSTimeInterval)((timestampUsec - YTNicoReplayBaseUsec) / 1000000.0);
    delay = MAX(0.0, MIN(delay, 1800.0));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![self ytdf_isGenerationCurrent:generation]) return;
        [YouTubeChatAdapter emitNowAuthor:author text:text messageId:messageId];
    });
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
        NSString *block = [self ytdf_balancedObjectFromString:s start:br.location maxLength:30000];
        if (block.length > 0) [blocks addObject:block];
        NSUInteger next = br.location + MAX((NSUInteger)1, block.length);
        if (next >= s.length) break;
        search = NSMakeRange(next, s.length - next);
    }
    return blocks;
}

+ (NSString *)ytdf_firstLiveContinuationTokenInString:(NSString *)s {
    if (s.length == 0) return @"";
    for (NSString *key in @[@"liveChatRenderer", @"liveChatItemListRenderer", @"liveChatContinuation", @"liveChatHeaderRenderer"]) {
        for (NSString *block in [self ytdf_blocksForKey:key inString:s limit:8]) {
            NSString *token = [self ytdf_firstMatchIn:block patterns:@[@"\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"token\"\\s*:\\s*\"([^\"]+)\""]];
            if (token.length > 0) return token;
        }
    }
    return [self ytdf_firstMatchIn:s patterns:@[@"\"liveChat.*?\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"timedContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"reloadContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\""]];
}

+ (NSString *)ytdf_firstReplayContinuationTokenInString:(NSString *)s {
    if (s.length == 0) return @"";
    for (NSString *key in @[@"liveChatReplayContinuationData", @"replayContinuationData", @"liveChatContinuation"]) {
        for (NSString *block in [self ytdf_blocksForKey:key inString:s limit:12]) {
            NSString *token = [self ytdf_firstMatchIn:block patterns:@[@"\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"token\"\\s*:\\s*\"([^\"]+)\""]];
            if (token.length > 0) return token;
        }
    }
    return @"";
}

+ (NSString *)ytdf_firstCommentContinuationTokenInString:(NSString *)s {
    if (s.length == 0) return @"";
    for (NSString *key in @[@"commentSectionRenderer", @"itemSectionRenderer", @"continuationItemRenderer"]) {
        for (NSString *block in [self ytdf_blocksForKey:key inString:s limit:16]) {
            NSString *token = [self ytdf_firstMatchIn:block patterns:@[@"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"continuation\"\\s*:\\s*\"([^\"]+)\""]];
            if (token.length > 0) return token;
        }
    }
    return [self ytdf_firstMatchIn:s patterns:@[@"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"nextContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\""]];
}

+ (BOOL)ytdf_isGenerationCurrent:(NSUInteger)generation { return generation == [YouTubeChatAdapter currentGeneration]; }

+ (NSString *)ytdf_balancedObjectFromString:(NSString *)s start:(NSUInteger)start maxLength:(NSUInteger)maxLength {
    if (start >= s.length || [s characterAtIndex:start] != '{') return @"";
    NSUInteger endLimit = MIN(s.length, start + maxLength);
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL escape = NO;
    for (NSUInteger i = start; i < endLimit; i++) {
        unichar c = [s characterAtIndex:i];
        if (inString) { if (escape) escape = NO; else if (c == '\\') escape = YES; else if (c == '"') inString = NO; }
        else { if (c == '"') inString = YES; else if (c == '{') depth++; else if (c == '}') { depth--; if (depth == 0) return [s substringWithRange:NSMakeRange(start, i - start + 1)]; } }
    }
    return @"";
}

+ (NSString *)ytdf_firstMatchIn:(NSString *)s patterns:(NSArray<NSString *> *)patterns { for (NSString *pattern in patterns) { NSString *m = [self ytdf_matchFirst:s pattern:pattern]; if (m.length > 0) return m; } return @""; }
+ (NSString *)ytdf_textFromRunsString:(NSString *)runs { NSMutableString *out = [NSMutableString string]; NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\"text\"\\s*:\\s*\"([^\"]*)\"" options:0 error:nil]; for (NSTextCheckingResult *m in [re matchesInString:runs options:0 range:NSMakeRange(0, runs.length)]) if (m.numberOfRanges >= 2) [out appendString:[self ytdf_unescape:[runs substringWithRange:[m rangeAtIndex:1]]]]; return [self ytdf_norm:out]; }
+ (NSString *)ytdf_matchFirst:(NSString *)text pattern:(NSString *)pattern { NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil]; NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]; if (!m || m.numberOfRanges < 2) return @""; return [text substringWithRange:[m rangeAtIndex:1]]; }
+ (unsigned long long)ytdf_unsignedLongLongFromString:(NSString *)s { if (![s isKindOfClass:NSString.class] || s.length == 0) return 0; return strtoull(s.UTF8String, NULL, 10); }
+ (NSString *)ytdf_unescape:(NSString *)s { if (![s isKindOfClass:NSString.class]) return @""; s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "]; s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""]; s = [s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]; s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"]; s = [s stringByReplacingOccurrencesOfString:@"\\u003c" withString:@"<"]; s = [s stringByReplacingOccurrencesOfString:@"\\u003e" withString:@">"]; return s; }
+ (NSString *)ytdf_norm:(id)obj { if (![obj isKindOfClass:NSString.class]) return @""; NSString *s = [(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "]; return s; }
+ (void)ytdf_finish { @synchronized (self) { YTNicoDirectFetchActive = NO; } }

@end

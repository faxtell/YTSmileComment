#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoReplayHTMLFallbackPrivate)
+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)ver token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation;
+ (NSInteger)ytv2_parseReplay:(NSString *)s max:(NSInteger)max generation:(NSUInteger)generation;
+ (BOOL)ytv2_gen:(NSUInteger)generation;
@end

static NSString *YTNicoHTMLFallbackUnescape(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003d" withString:@"="];
    s = [s stringByReplacingOccurrencesOfString:@"\\u002f" withString:@"/"];
    s = [s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    return s;
}

static NSString *YTNicoNormalizeToken(NSString *token) {
    token = YTNicoHTMLFallbackUnescape(token ?: @"");
    NSString *decoded = token.stringByRemovingPercentEncoding;
    return decoded.length ? decoded : token;
}

static NSString *YTNicoFirstMatch(NSString *s, NSArray<NSString *> *patterns) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static NSArray<NSString *> *YTNicoAllMatches(NSString *s, NSString *pattern) {
    if (![s isKindOfClass:NSString.class] || s.length == 0 || pattern.length == 0) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:s options:0 range:NSMakeRange(0, s.length)]) {
        if (m.numberOfRanges >= 2) {
            NSString *v = [s substringWithRange:[m rangeAtIndex:1]];
            if (v.length) [out addObject:v];
        }
    }
    return out;
}

static NSString *YTNicoExtractBalancedObjectAfter(NSString *s, NSString *needle, NSUInteger maxLen) {
    if (s.length == 0 || needle.length == 0) return @"";
    NSRange r = [s rangeOfString:needle];
    if (r.location == NSNotFound) return @"";
    NSRange search = NSMakeRange(NSMaxRange(r), s.length - NSMaxRange(r));
    NSRange br = [s rangeOfString:@"{" options:0 range:search];
    if (br.location == NSNotFound) return @"";
    NSUInteger start = br.location;
    NSUInteger end = MIN(s.length, start + MAX((NSUInteger)1024, maxLen));
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL esc = NO;
    for (NSUInteger i = start; i < end; i++) {
        unichar c = [s characterAtIndex:i];
        if (inString) {
            if (esc) esc = NO;
            else if (c == '\\') esc = YES;
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

static NSString *YTNicoWindowAround(NSString *s, NSString *needle, NSUInteger before, NSUInteger after) {
    if (s.length == 0 || needle.length == 0) return @"";
    NSRange r = [s rangeOfString:needle];
    if (r.location == NSNotFound) return @"";
    NSUInteger start = r.location > before ? r.location - before : 0;
    NSUInteger end = MIN(s.length, NSMaxRange(r) + after);
    return [s substringWithRange:NSMakeRange(start, end - start)];
}

static NSString *YTNicoExtractInitialDataBlob(NSString *html) {
    NSString *blob = YTNicoExtractBalancedObjectAfter(html, @"var ytInitialData", 3000000);
    if (blob.length) return blob;
    blob = YTNicoExtractBalancedObjectAfter(html, @"window[\"ytInitialData\"]", 3000000);
    if (blob.length) return blob;
    blob = YTNicoExtractBalancedObjectAfter(html, @"ytInitialData =", 3000000);
    return blob ?: @"";
}

static NSArray<NSString *> *YTNicoReloadContinuationTokens(NSString *text) {
    NSString *s = YTNicoHTMLFallbackUnescape(text ?: @"");
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSArray *patterns = @[
        @"reloadContinuationData[^{}]{0,4000}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
        @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"[^{}]{0,1400}reloadContinuationData",
        @"\\\"token\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"[^{}]{0,1400}reloadContinuationData"
    ];
    for (NSString *pattern in patterns) {
        for (NSString *raw in YTNicoAllMatches(s, pattern)) {
            NSString *token = YTNicoNormalizeToken(raw);
            if (token.length && ![tokens containsObject:token]) [tokens addObject:token];
        }
    }
    return tokens;
}

static NSString *YTNicoYCSNewAPIToken(NSString *joined) {
    for (NSString *needle in @[@"conversationBar", @"liveChatRenderer", @"twoColumnWatchNextResults"]) {
        NSString *window = YTNicoWindowAround(joined, needle, 3000, 90000);
        NSArray *tokens = YTNicoReloadContinuationTokens(window);
        if (tokens.count) return tokens.firstObject;
    }
    return @"";
}

static NSString *YTNicoYCSOldAPIToken(NSString *joined) {
    for (NSString *needle in @[@"sortFilterSubMenuRenderer", @"viewSelector", @"subMenuItems"]) {
        NSString *window = YTNicoWindowAround(joined, needle, 12000, 90000);
        NSArray *tokens = YTNicoReloadContinuationTokens(window);
        if (tokens.count >= 2) return tokens[1];
        if (tokens.count == 1) return tokens.lastObject;
    }
    return @"";
}

static NSString *YTNicoYCSDeepSearchToken(NSString *joined) {
    NSArray *tokens = YTNicoReloadContinuationTokens(joined);
    return tokens.count ? tokens.lastObject : @"";
}

static NSString *YTNicoTokenForContinuationType(NSString *text, NSString *type) {
    NSString *s = YTNicoHTMLFallbackUnescape(text ?: @"");
    for (NSString *needle in @[type]) {
        NSRange nr = [s rangeOfString:needle];
        if (nr.location == NSNotFound) continue;
        NSUInteger start = nr.location > 1800 ? nr.location - 1800 : 0;
        NSUInteger len = MIN((NSUInteger)7000, s.length - start);
        NSString *window = [s substringWithRange:NSMakeRange(start, len)];
        NSString *token = YTNicoFirstMatch(window, @[
            @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"\\\"token\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"continuation=([^\\\"'&]+)"
        ]);
        if (token.length) return YTNicoNormalizeToken(token);
    }
    return @"";
}

static NSString *YTNicoExtractReplayTokenFromText(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableArray<NSString *> *variants = [NSMutableArray arrayWithObject:text];
    NSString *unescaped = YTNicoHTMLFallbackUnescape(text);
    if (unescaped.length && ![unescaped isEqualToString:text]) [variants addObject:unescaped];

    for (NSString *s in variants) {
        NSArray *directPatterns = @[
            @"live_chat/get_live_chat_replay[^\\\"']*[?&]continuation=([^\\\"'&]+)",
            @"get_live_chat_replay[^\\\"']*continuation=([^\\\"'&]+)",
            @"liveChatReplayContinuationData[^{}]{0,1600}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"replayContinuationData[^{}]{0,1600}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"playerSeekContinuationData[^{}]{0,1600}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"\\\"liveChatReplayEndpoint\\\".*?\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\".*?get_live_chat_replay"
        ];
        NSString *token = YTNicoFirstMatch(s, directPatterns);
        if (token.length > 0) return YTNicoNormalizeToken(token);
    }
    return @"";
}

static unsigned long long YTNicoLastReplayOffset(NSString *text) {
    NSArray<NSString *> *offsets = YTNicoAllMatches(text ?: @"", @"\\\"videoOffsetTimeMsec\\\"\\s*:\\s*\\\"?([0-9]+)\\\"?");
    NSString *last = offsets.lastObject;
    return last.length ? strtoull(last.UTF8String, NULL, 10) : 0;
}

static NSDictionary *YTNicoYCSContext(NSString *version) {
    return @{@"client":@{@"clientName":@"WEB", @"clientVersion": version.length ? version : @"2.20250101.01.00", @"hl":@"ja", @"gl":@"JP"}};
}

static void YTNicoYCSPostReplay(NSString *apiKey, NSString *version, NSString *token, NSNumber *offsetMs, NSUInteger generation, void (^completion)(NSString *text, NSInteger status)) {
    if (token.length == 0) { if (completion) completion(@"", 0); return; }
    NSString *urlString = apiKey.length ? [NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?key=%@&prettyPrint=false", apiKey] : @"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?prettyPrint=false";
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableDictionary *body = [@{@"context": YTNicoYCSContext(version), @"continuation": token} mutableCopy];
    if (offsetMs) body[@"currentPlayerState"] = @{@"playerOffsetMs": offsetMs.stringValue};
    NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    if (!url || json.length == 0) { if (completion) completion(@"", 0); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = json;
    req.timeoutInterval = 18.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
    [req setValue:@"https://www.youtube.com/" forHTTPHeaderField:@"Referer"];
    [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (![YouTubeChatAdapter ytv2_gen:generation]) return;
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        if (completion) completion(text ?: @"", http ? http.statusCode : (error ? -1 : 0));
    }] resume];
}

static void YTNicoYCSPlayerSeekLoop(NSString *apiKey, NSString *version, NSString *token, unsigned long long offset, NSInteger page, NSInteger total, NSUInteger generation, void (^done)(BOOL ok));

static void YTNicoYCSPlayerSeekLoop(NSString *apiKey, NSString *version, NSString *token, unsigned long long offset, NSInteger page, NSInteger total, NSUInteger generation, void (^done)(BOOL ok)) {
    if (![YouTubeChatAdapter ytv2_gen:generation] || token.length == 0 || page > 16) { if (done) done(total > 0); return; }
    YTNicoYCSPostReplay(apiKey, version, token, @(offset), generation, ^(NSString *text, NSInteger status) {
        NSInteger emitted = text.length ? [YouTubeChatAdapter ytv2_parseReplay:text max:260 generation:generation] : 0;
        unsigned long long lastOffset = YTNicoLastReplayOffset(text);
        NSString *next = YTNicoTokenForContinuationType(text, @"playerSeekContinuationData");
        [[DebugInspector shared] important:@"YCS new/playerSeek page=%ld status=%ld emitted=%ld offset=%llu next=%d", (long)page, (long)status, (long)emitted, lastOffset, next.length > 0);
        if (emitted <= 0 || next.length == 0 || lastOffset == offset) { if (done) done(total + emitted > 0); return; }
        YTNicoYCSPlayerSeekLoop(apiKey, version, next, lastOffset, page + 1, total + emitted, generation, done);
    });
}

static void YTNicoYCSLiveReplayLoop(NSString *apiKey, NSString *version, NSString *token, NSInteger page, NSInteger total, NSUInteger generation, void (^done)(BOOL ok)) {
    if (![YouTubeChatAdapter ytv2_gen:generation] || token.length == 0 || page > 16) { if (done) done(total > 0); return; }
    YTNicoYCSPostReplay(apiKey, version, token, nil, generation, ^(NSString *text, NSInteger status) {
        NSInteger emitted = text.length ? [YouTubeChatAdapter ytv2_parseReplay:text max:260 generation:generation] : 0;
        NSString *next = YTNicoTokenForContinuationType(text, @"liveChatReplayContinuationData");
        if (next.length == 0) next = YTNicoExtractReplayTokenFromText(text);
        [[DebugInspector shared] important:@"YCS replayContinuation page=%ld status=%ld emitted=%ld next=%d", (long)page, (long)status, (long)emitted, next.length > 0);
        if (emitted <= 0 || next.length == 0) { if (done) done(total + emitted > 0); return; }
        YTNicoYCSLiveReplayLoop(apiKey, version, next, page + 1, total + emitted, generation, done);
    });
}

static void YTNicoYCSOldLoop(NSString *apiKey, NSString *version, NSString *token, unsigned long long offset, NSInteger page, NSInteger total, NSUInteger generation, void (^done)(BOOL ok)) {
    if (![YouTubeChatAdapter ytv2_gen:generation] || token.length == 0 || page > 16) { if (done) done(total > 0); return; }
    YTNicoYCSPostReplay(apiKey, version, token, @(offset), generation, ^(NSString *text, NSInteger status) {
        NSInteger emitted = text.length ? [YouTubeChatAdapter ytv2_parseReplay:text max:260 generation:generation] : 0;
        unsigned long long lastOffset = YTNicoLastReplayOffset(text);
        [[DebugInspector shared] important:@"YCS old page=%ld status=%ld emitted=%ld offset=%llu", (long)page, (long)status, (long)emitted, lastOffset);
        if (emitted <= 0 || lastOffset == offset) { if (done) done(total + emitted > 0); return; }
        YTNicoYCSOldLoop(apiKey, version, token, lastOffset, page + 1, total + emitted, generation, done);
    });
}

static void YTNicoYCSNewStage(NSString *apiKey, NSString *version, NSString *token, NSUInteger generation, void (^done)(BOOL ok)) {
    if (token.length == 0) { if (done) done(NO); return; }
    [[DebugInspector shared] important:@"YCS stage1 new API start token=%d", token.length > 0];
    YTNicoYCSPostReplay(apiKey, version, token, nil, generation, ^(NSString *text, NSInteger status) {
        NSInteger first = text.length ? [YouTubeChatAdapter ytv2_parseReplay:text max:260 generation:generation] : 0;
        NSString *playerSeek = YTNicoTokenForContinuationType(text, @"playerSeekContinuationData");
        NSString *liveReplay = YTNicoTokenForContinuationType(text, @"liveChatReplayContinuationData");
        [[DebugInspector shared] important:@"YCS new initial status=%ld first=%ld playerSeek=%d liveReplay=%d", (long)status, (long)first, playerSeek.length > 0, liveReplay.length > 0];
        if (playerSeek.length > 0) {
            YTNicoYCSPlayerSeekLoop(apiKey, version, playerSeek, 0, 0, first, generation, done);
            return;
        }
        if (liveReplay.length > 0) {
            YTNicoYCSLiveReplayLoop(apiKey, version, liveReplay, 0, first, generation, done);
            return;
        }
        if (done) done(first > 0);
    });
}

static void YTNicoYCSRunStages(NSString *joined, NSString *apiKey, NSString *version, NSUInteger generation) {
    NSString *newToken = YTNicoYCSNewAPIToken(joined);
    NSString *oldToken = YTNicoYCSOldAPIToken(joined);
    NSString *deepToken = YTNicoYCSDeepSearchToken(joined);
    [[DebugInspector shared] important:@"YCS fallback tokens new=%d old=%d deep=%d", newToken.length > 0, oldToken.length > 0, deepToken.length > 0];
    [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"YCS方式: 新API → 旧API → deep searchで試します" messageId:[[NSUUID UUID] UUIDString]];

    YTNicoYCSNewStage(apiKey, version, newToken, generation, ^(BOOL okNew) {
        if (okNew) return;
        [[DebugInspector shared] important:@"YCS stage1 failed, trying old API"];
        if (oldToken.length == 0) {
            [[DebugInspector shared] important:@"YCS old token missing, trying deep search"];
            YTNicoYCSNewStage(apiKey, version, deepToken, generation, ^(BOOL okDeep) {
                if (!okDeep) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"YCS方式でもチャットリプレイを取得できませんでした" messageId:[[NSUUID UUID] UUIDString]];
            });
            return;
        }
        YTNicoYCSOldLoop(apiKey, version, oldToken, 0, 0, 0, generation, ^(BOOL okOld) {
            if (okOld) return;
            [[DebugInspector shared] important:@"YCS stage2 failed, trying deep search"];
            YTNicoYCSNewStage(apiKey, version, deepToken, generation, ^(BOOL okDeep) {
                if (!okDeep) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"YCS方式でもチャットリプレイを取得できませんでした" messageId:[[NSUUID UUID] UUIDString]];
            });
        });
    });
}

static void YTNicoReplayHTMLFetch(NSString *videoId, NSString *apiKey, NSString *version, NSUInteger generation, NSString *reason) {
    if (videoId.length != 11) return;
    version = version.length ? version : @"2.20250101.01.00";
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]]];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://m.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]]];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/live/%@?hl=ja&persist_hl=1", videoId]]];

    [[DebugInspector shared] important:@"HTML/YCS replay fallback start videoId=%@ reason=%@", videoId, reason ?: @"unknown"];

    __block void (^tryIndex)(NSUInteger) = nil;
    __block __weak void (^weakTryIndex)(NSUInteger) = nil;
    tryIndex = ^(NSUInteger index) {
        if (![YouTubeChatAdapter ytv2_gen:generation]) return;
        if (index >= urls.count) {
            [[DebugInspector shared] important:@"HTML/YCS replay fallback failed: no usable watch html videoId=%@", videoId];
            return;
        }
        NSURL *url = urls[index];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
        req.timeoutInterval = 18.0;
        [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
        [req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
        [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];
        [req setValue:@"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" forHTTPHeaderField:@"Accept"];

        [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (![YouTubeChatAdapter ytv2_gen:generation]) return;
            NSString *html = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            NSString *key = apiKey.length ? apiKey : YTNicoFirstMatch(html, @[@"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"", @"\"INNERTUBE_API_KEY\"\\s*:\\s*\"([^\"]+)\"", @"INNERTUBE_API_KEY[^\n]+?\"([^\"]+)\""]);
            NSString *ver = version.length ? version : YTNicoFirstMatch(html, @[@"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"", @"\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\"", @"INNERTUBE_CLIENT_VERSION[^\n]+?\"([^\"]+)\""]);
            if (ver.length == 0) ver = @"2.20250101.01.00";

            NSString *initialData = YTNicoExtractInitialDataBlob(html);
            NSString *joined = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", html ?: @"", YTNicoHTMLFallbackUnescape(html ?: @""), initialData ?: @"", YTNicoHTMLFallbackUnescape(initialData ?: @"")];
            NSInteger inlineQueued = initialData.length ? [YouTubeChatAdapter ytv2_parseReplay:initialData max:240 generation:generation] : 0;
            NSString *directToken = YTNicoExtractReplayTokenFromText(joined);

            [[DebugInspector shared] important:@"HTML/YCS fallback url=%lu len=%lu key=%d directToken=%d inline=%ld err=%@", (unsigned long)index, (unsigned long)html.length, key.length > 0, directToken.length > 0, (long)inlineQueued, error.localizedDescription ?: @""];

            if (directToken.length > 0 && key.length > 0) {
                [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"HTMLからチャットリプレイ継続IDを検出しました" messageId:[[NSUUID UUID] UUIDString]];
                [YouTubeChatAdapter ytv2_fetchReplay:key version:ver token:directToken page:0 emitted:inlineQueued generation:generation];
            }

            if (key.length > 0 && (joined.length > 0)) {
                YTNicoYCSRunStages(joined, key, ver, generation);
                return;
            }
            if (inlineQueued > 0) {
                [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"HTML内JSONから%ld件キューしました", (long)inlineQueued] messageId:[[NSUUID UUID] UUIDString]];
                return;
            }
            if (weakTryIndex) weakTryIndex(index + 1);
        }] resume];
    };
    weakTryIndex = tryIndex;
    tryIndex(0);
}

%hook YouTubeChatAdapter

+ (void)ytv2_fetchJSONFallbackForVideoId:(NSString *)videoId apiKey:(NSString *)apiKey version:(NSString *)ver generation:(NSUInteger)generation reason:(NSString *)reason {
    YTNicoReplayHTMLFetch(videoId, apiKey, ver, generation, reason);
    %orig(videoId, apiKey, ver, generation, reason);
}

%end

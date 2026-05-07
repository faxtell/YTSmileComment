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

static NSString *YTNicoFirstMatch(NSString *s, NSArray<NSString *> *patterns) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
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

static NSString *YTNicoExtractReplayTokenFromText(NSString *text) {
    if (text.length == 0) return @"";
    NSMutableArray<NSString *> *variants = [NSMutableArray arrayWithObject:text];
    NSString *unescaped = YTNicoHTMLFallbackUnescape(text);
    if (unescaped.length && ![unescaped isEqualToString:text]) [variants addObject:unescaped];

    for (NSString *s in variants) {
        NSArray *directPatterns = @[
            @"live_chat/get_live_chat_replay[^\\\"']*[?&]continuation=([^\\\"'&]+)",
            @"get_live_chat_replay[^\\\"']*continuation=([^\\\"'&]+)",
            @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"\\s*,\\s*\\\"clickTrackingParams\\\"[^{}]{0,600}liveChatReplayContinuationData",
            @"liveChatReplayContinuationData[^{}]{0,1200}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"replayContinuationData[^{}]{0,1200}\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"\\\"liveChatReplayEndpoint\\\".*?\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
            @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\".*?get_live_chat_replay"
        ];
        NSString *token = YTNicoFirstMatch(s, directPatterns);
        if (token.length > 0) return YTNicoHTMLFallbackUnescape(token);

        for (NSString *needle in @[@"liveChatReplayContinuationData", @"replayContinuationData", @"liveChatReplayEndpoint", @"get_live_chat_replay"]) {
            NSRange nr = [s rangeOfString:needle];
            if (nr.location == NSNotFound) continue;
            NSUInteger start = nr.location > 2500 ? nr.location - 2500 : 0;
            NSUInteger len = MIN((NSUInteger)8000, s.length - start);
            NSString *window = [s substringWithRange:NSMakeRange(start, len)];
            token = YTNicoFirstMatch(window, @[
                @"\\\"continuation\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"",
                @"continuation=([^\\\"'&]+)",
                @"\\\"token\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
            ]);
            if (token.length > 0) return YTNicoHTMLFallbackUnescape(token);
        }
    }
    return @"";
}

static NSString *YTNicoExtractInitialDataBlob(NSString *html) {
    NSString *blob = YTNicoExtractBalancedObjectAfter(html, @"var ytInitialData", 3000000);
    if (blob.length) return blob;
    blob = YTNicoExtractBalancedObjectAfter(html, @"window[\"ytInitialData\"]", 3000000);
    if (blob.length) return blob;
    blob = YTNicoExtractBalancedObjectAfter(html, @"ytInitialData =", 3000000);
    return blob ?: @"";
}

static void YTNicoReplayHTMLFetch(NSString *videoId, NSString *apiKey, NSString *version, NSUInteger generation, NSString *reason) {
    if (videoId.length != 11) return;
    version = version.length ? version : @"2.20250101.01.00";
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]]];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://m.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]]];
    [urls addObject:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/live/%@?hl=ja&persist_hl=1", videoId]]];

    [[DebugInspector shared] important:@"HTML replay fallback start videoId=%@ reason=%@", videoId, reason ?: @"unknown"];

    __block void (^tryIndex)(NSUInteger) = nil;
    __weak __block void (^weakTryIndex)(NSUInteger) = nil;
    tryIndex = ^(NSUInteger index) {
        if (![YouTubeChatAdapter ytv2_gen:generation]) return;
        if (index >= urls.count) {
            [[DebugInspector shared] important:@"HTML replay fallback failed: no replay continuation videoId=%@", videoId];
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
            NSString *key = apiKey.length ? apiKey : YTNicoFirstMatch(html, @[@"\"INNERTUBE_API_KEY\"\\s*:\\s*\"([^\"]+)\"", @"INNERTUBE_API_KEY[^\n]+?\"([^\"]+)\""]);
            NSString *ver = version.length ? version : YTNicoFirstMatch(html, @[@"\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\"", @"INNERTUBE_CLIENT_VERSION[^\n]+?\"([^\"]+)\""]);
            if (ver.length == 0) ver = @"2.20250101.01.00";

            NSString *initialData = YTNicoExtractInitialDataBlob(html);
            NSString *joined = [NSString stringWithFormat:@"%@\n%@\n%@", html ?: @"", YTNicoHTMLFallbackUnescape(html ?: @""), initialData ?: @""];
            NSString *token = YTNicoExtractReplayTokenFromText(joined);
            NSInteger inlineQueued = 0;
            if (initialData.length) inlineQueued = [YouTubeChatAdapter ytv2_parseReplay:initialData max:240 generation:generation];

            [[DebugInspector shared] important:@"HTML replay fallback url=%lu len=%lu key=%d token=%d inline=%ld err=%@", (unsigned long)index, (unsigned long)html.length, key.length > 0, token.length > 0, (long)inlineQueued, error.localizedDescription ?: @""];

            if (token.length > 0 && key.length > 0) {
                [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"HTMLからチャットリプレイ継続IDを検出しました" messageId:[[NSUUID UUID] UUIDString]];
                [YouTubeChatAdapter ytv2_fetchReplay:key version:ver token:token page:0 emitted:inlineQueued generation:generation];
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

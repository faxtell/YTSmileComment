#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"
#import <stdlib.h>

static const NSInteger YTV2MaxCommentPages = 8;
static const NSInteger YTV2MaxReplayPages = 14;
static const NSInteger YTV2MaxLivePolls = 180;

@implementation YouTubeChatAdapter (DirectFetchV2)

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
    videoId = [self ytv2_norm:videoId];
    if (videoId.length != 11) return;
    [YouTubeChatAdapter resetForVideoId:videoId];
    NSUInteger generation = [YouTubeChatAdapter currentGeneration];
    [[DebugInspector shared] log:@"direct v2 start videoId=%@ gen=%lu", videoId, (unsigned long)generation];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&hl=ja&persist_hl=1", videoId]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    [req setValue:@"1" forHTTPHeaderField:@"X-YTNico-DirectFetch"];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"ja,en-US;q=0.9,en;q=0.8" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (![self ytv2_gen:generation]) return;
        if (error || data.length == 0) return;
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) return;
        [self ytv2_processHTML:html videoId:videoId generation:generation];
    }];
    [task resume];
}

+ (void)ytv2_processHTML:(NSString *)html videoId:(NSString *)videoId generation:(NSUInteger)generation {
    NSString *apiKey = [self ytv2_first:html patterns:@[@"\"INNERTUBE_API_KEY\"\\s*:\\s*\"([^\"]+)\"", @"\\\"INNERTUBE_API_KEY\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""]];
    NSString *ver = [self ytv2_first:html patterns:@[@"\"INNERTUBE_CLIENT_VERSION\"\\s*:\\s*\"([^\"]+)\"", @"\\\"INNERTUBE_CLIENT_VERSION\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""]];
    if (ver.length == 0) ver = @"2.20250101.01.00";
    if (apiKey.length == 0) return;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", apiKey]];
    NSDictionary *body = @{@"context":[self ytv2_context:ver], @"videoId":videoId ?: @""};
    [self ytv2_post:url body:body completion:^(NSString *text) {
        if (![self ytv2_gen:generation] || text.length == 0) return;

        NSString *combined = [NSString stringWithFormat:@"%@\n%@", html ?: @"", text ?: @""];
        BOOL explicitLive = [self ytv2_isExplicitLiveNow:combined];
        BOOL replay = [self ytv2_hasReplaySignal:combined];
        BOOL liveCandidate = explicitLive || [self ytv2_hasLiveEndpoint:combined];
        NSString *liveToken = liveCandidate ? [self ytv2_strictLiveToken:text] : @"";
        NSString *replayToken = replay ? [self ytv2_strictReplayToken:text] : @"";
        [[DebugInspector shared] log:@"route explicitLive=%d liveCandidate=%d liveToken=%d replay=%d replayToken=%d", explicitLive, liveCandidate, liveToken.length > 0, replay, replayToken.length > 0];

        if (SettingsManager.shared.preferLiveChat && liveCandidate && liveToken.length > 0 && !replay) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"ライブチャットをリアルタイム取得します" messageId:NSUUID.UUID.UUIDString];
            [self ytv2_pollLive:apiKey version:ver token:liveToken poll:0 generation:generation];
            return;
        }

        if (SettingsManager.shared.preferLiveChat && replay && replayToken.length > 0) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"チャットリプレイを再生時間同期で取得します" messageId:NSUUID.UUID.UUIDString];
            [self ytv2_fetchReplay:apiKey version:ver token:replayToken page:0 emitted:0 generation:generation];
            return;
        }

        if (SettingsManager.shared.preferLiveChat && liveCandidate && liveToken.length > 0) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"ライブチャットをリアルタイム取得します" messageId:NSUUID.UUID.UUIDString];
            [self ytv2_pollLive:apiKey version:ver token:liveToken poll:0 generation:generation];
            return;
        }

        NSInteger emitted = [self ytv2_parseNormal:text max:60 live:NO generation:generation];
        NSString *token = [self ytv2_commentToken:text];
        if (token.length > 0) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"通常コメントを取得します" messageId:NSUUID.UUID.UUIDString];
            [self ytv2_fetchComments:apiKey version:ver token:token page:1 emitted:emitted generation:generation];
        } else if (emitted == 0) {
            [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: コメントを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
        }
    }];
}

+ (NSDictionary *)ytv2_context:(NSString *)ver { return @{@"client":@{@"clientName":@"WEB", @"clientVersion":ver ?: @"2.20250101.01.00", @"hl":@"ja", @"gl":@"JP"}}; }
+ (BOOL)ytv2_gen:(NSUInteger)g { return g == [YouTubeChatAdapter currentGeneration]; }
+ (BOOL)ytv2_hasReplaySignal:(NSString *)s { return [s rangeOfString:@"videoOffsetTimeMsec"].location != NSNotFound || [s rangeOfString:@"replayChatItemAction"].location != NSNotFound || [s rangeOfString:@"get_live_chat_replay"].location != NSNotFound || [s rangeOfString:@"liveChatReplayContinuationData"].location != NSNotFound || [s rangeOfString:@"replayContinuationData"].location != NSNotFound || [s rangeOfString:@"live_chat/get_live_chat_replay"].location != NSNotFound; }
+ (BOOL)ytv2_hasLiveEndpoint:(NSString *)s { return ([s rangeOfString:@"live_chat/get_live_chat"].location != NSNotFound || [s rangeOfString:@"get_live_chat\""].location != NSNotFound || [s rangeOfString:@"get_live_chat?"].location != NSNotFound) && [s rangeOfString:@"get_live_chat_replay"].location == NSNotFound; }
+ (BOOL)ytv2_isExplicitLiveNow:(NSString *)s { if ([self ytv2_hasReplaySignal:s]) return NO; return [s rangeOfString:@"\"isLiveNow\":true"].location != NSNotFound || [s rangeOfString:@"\\\"isLiveNow\\\":true"].location != NSNotFound || [s rangeOfString:@"\"isLive\":true"].location != NSNotFound || [s rangeOfString:@"\\\"isLive\\\":true"].location != NSNotFound || [s rangeOfString:@"LIVE_STREAM_OFFLINE"].location == NSNotFound && [s rangeOfString:@"\"liveBroadcastDetails\""].location != NSNotFound; }
+ (BOOL)ytv2_isLiveNow:(NSString *)s { return [self ytv2_isExplicitLiveNow:s] || [self ytv2_hasLiveEndpoint:s]; }
+ (BOOL)ytv2_hasArchivedChatSignal:(NSString *)s { return [self ytv2_hasReplaySignal:s]; }

+ (NSString *)ytv2_strictTokenForKeys:(NSArray<NSString *> *)keys inText:(NSString *)s {
    for (NSString *key in keys) {
        for (NSString *block in [self ytv2_blocks:key in:s limit:24]) {
            NSString *token = [self ytv2_first:block patterns:@[@"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"token\"\\s*:\\s*\"([^\"]+)\""]];
            if (token.length > 0) return token;
        }
    }
    return @"";
}
+ (NSString *)ytv2_strictLiveToken:(NSString *)s { return [self ytv2_strictTokenForKeys:@[@"liveChatRenderer", @"liveChatItemListRenderer", @"liveChatContinuation", @"liveChatHeaderRenderer"] inText:s]; }
+ (NSString *)ytv2_strictReplayToken:(NSString *)s { NSString *t = [self ytv2_strictTokenForKeys:@[@"liveChatReplayContinuationData", @"replayContinuationData"] inText:s]; if (t.length > 0) return t; if (![self ytv2_hasReplaySignal:s]) return @""; return [self ytv2_strictTokenForKeys:@[@"liveChatContinuation", @"liveChatItemListRenderer", @"liveChatRenderer"] inText:s]; }

+ (void)ytv2_fetchComments:(NSString *)key version:(NSString *)ver token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    if (![self ytv2_gen:generation] || page > YTV2MaxCommentPages || token.length == 0) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/next?key=%@", key]];
    [self ytv2_post:url body:@{@"context":[self ytv2_context:ver], @"continuation":token} completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger emitted = text.length ? [self ytv2_parseNormal:text max:80 live:NO generation:generation] : 0;
        NSString *next = text.length ? [self ytv2_commentToken:text] : @"";
        if (next.length > 0 && page < YTV2MaxCommentPages) [self ytv2_fetchComments:key version:ver token:next page:page+1 emitted:total+emitted generation:generation];
    }];
}

+ (void)ytv2_pollLive:(NSString *)key version:(NSString *)ver token:(NSString *)token poll:(NSInteger)poll generation:(NSUInteger)generation {
    if (![self ytv2_gen:generation] || poll > YTV2MaxLivePolls || token.length == 0) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=%@", key]];
    [self ytv2_post:url body:@{@"context":[self ytv2_context:ver], @"continuation":token} completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger emitted = text.length ? [self ytv2_parseNormal:text max:100 live:YES generation:generation] : 0;
        NSString *next = text.length ? [self ytv2_liveToken:text] : @"";
        NSTimeInterval delay = emitted > 0 ? 2.0 : 3.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self ytv2_gen:generation]) [self ytv2_pollLive:key version:ver token:(next.length ? next : token) poll:poll+1 generation:generation];
        });
    }];
}

+ (void)ytv2_fetchReplay:(NSString *)key version:(NSString *)ver token:(NSString *)token page:(NSInteger)page emitted:(NSInteger)total generation:(NSUInteger)generation {
    if (![self ytv2_gen:generation] || page > YTV2MaxReplayPages || token.length == 0) return;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/live_chat/get_live_chat_replay?key=%@", key]];
    [self ytv2_post:url body:@{@"context":[self ytv2_context:ver], @"continuation":token} completion:^(NSString *text) {
        if (![self ytv2_gen:generation]) return;
        NSInteger emitted = text.length ? [self ytv2_parseReplay:text max:220 generation:generation] : 0;
        NSString *next = text.length ? ([self ytv2_replayToken:text].length ? [self ytv2_replayToken:text] : [self ytv2_liveToken:text]) : @"";
        if (next.length > 0 && page < YTV2MaxReplayPages) [self ytv2_fetchReplay:key version:ver token:next page:page+1 emitted:total+emitted generation:generation];
        else if (total + emitted == 0) [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:@"取得結果: チャットリプレイを検出できませんでした" messageId:NSUUID.UUID.UUIDString];
    }];
}

+ (void)ytv2_post:(NSURL *)url body:(NSDictionary *)body completion:(void (^)(NSString *text))completion {
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
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || data.length == 0) { if (completion) completion(@""); return; }
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (completion) completion(s ?: @"");
    }] resume];
}

+ (NSInteger)ytv2_parseNormal:(NSString *)s max:(NSInteger)max live:(BOOL)live generation:(NSUInteger)generation {
    NSInteger count = 0;
    NSArray *keys = live ? @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer", @"liveChatPaidStickerRenderer"] : @[@"commentRenderer", @"commentViewModel", @"commentEntityPayload"];
    for (NSString *key in keys) {
        for (NSString *block in [self ytv2_blocks:key in:s limit:180]) {
            if (count >= max || ![self ytv2_gen:generation]) return count;
            NSDictionary *p = [self ytv2_authorText:block];
            NSString *author = [self ytv2_norm:[self ytv2_unescape:p[@"a"]]];
            NSString *text = [self ytv2_norm:[self ytv2_unescape:p[@"t"]]];
            if (text.length == 0) continue;
            NSString *mid = [NSString stringWithFormat:@"%@-%lu-%lu", live ? @"live" : @"comment", (unsigned long)[[NSString stringWithFormat:@"%@|%@", author, text] hash], (unsigned long)generation];
            if (live) [YouTubeChatAdapter emitNowAuthor:author.length ? author : @"chat" text:text messageId:mid];
            else [YouTubeChatAdapter broadcastAuthor:author.length ? author : @"comment" text:text messageId:mid];
            count++;
        }
    }
    return count;
}

+ (NSInteger)ytv2_parseReplay:(NSString *)s max:(NSInteger)max generation:(NSUInteger)generation {
    NSInteger count = 0;
    for (NSString *action in [self ytv2_blocks:@"replayChatItemAction" in:s limit:320]) {
        if (count >= max || ![self ytv2_gen:generation]) break;
        NSString *off = [self ytv2_first:action patterns:@[@"\"videoOffsetTimeMsec\"\\s*:\\s*\"?([0-9]+)\"?"]];
        unsigned long long offsetMs = [self ytv2_ull:off];
        if (off.length == 0) continue;
        for (NSString *rendererKey in @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer", @"liveChatPaidStickerRenderer"]) {
            for (NSString *block in [self ytv2_blocks:rendererKey in:action limit:16]) {
                if (count >= max) break;
                NSDictionary *p = [self ytv2_authorText:block];
                NSString *author = [self ytv2_norm:[self ytv2_unescape:p[@"a"]]];
                NSString *text = [self ytv2_norm:[self ytv2_unescape:p[@"t"]]];
                if (text.length == 0) continue;
                NSString *mid = [NSString stringWithFormat:@"replay-%llu-%lu-%lu", offsetMs, (unsigned long)[[NSString stringWithFormat:@"%@|%@", author, text] hash], (unsigned long)generation];
                [YouTubeChatAdapter queueTimedReplayAuthor:author.length ? author : @"chat" text:text messageId:mid offsetMilliseconds:offsetMs generation:generation];
                count++;
            }
        }
    }
    [[DebugInspector shared] log:@"v2 replay queued %ld", (long)count];
    return count;
}

+ (NSDictionary *)ytv2_authorText:(NSString *)block {
    NSString *author = [self ytv2_first:block patterns:@[@"\"authorText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"authorName\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"authorName\".*?\"text\"\\s*:\\s*\"([^\"]+)\"", @"\"displayName\"\\s*:\\s*\"([^\"]+)\"", @"\"name\"\\s*:\\s*\"([^\"]+)\""]];
    NSString *text = @"";
    NSString *runs = [self ytv2_first:block patterns:@[@"\"contentText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]", @"\"message\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]", @"\"bodyText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]"]];
    if (runs.length) text = [self ytv2_textFromRuns:runs];
    if (text.length == 0) text = [self ytv2_first:block patterns:@[@"\"contentText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"commentText\"\\s*:\\s*\"([^\"]+)\"", @"\"bodyText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"", @"\"content\"\\s*:\\s*\"([^\"]+)\"", @"\"message\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\""]];
    return @{@"a":author ?: @"", @"t":text ?: @""};
}

+ (NSString *)ytv2_liveToken:(NSString *)s { return [self ytv2_token:s keys:@[@"liveChatRenderer", @"liveChatItemListRenderer", @"liveChatContinuation", @"liveChatHeaderRenderer"]]; }
+ (NSString *)ytv2_replayToken:(NSString *)s { return [self ytv2_token:s keys:@[@"liveChatReplayContinuationData", @"replayContinuationData", @"liveChatContinuation"]]; }
+ (NSString *)ytv2_commentToken:(NSString *)s { return [self ytv2_token:s keys:@[@"commentSectionRenderer", @"itemSectionRenderer", @"continuationItemRenderer"]]; }
+ (NSString *)ytv2_token:(NSString *)s keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) for (NSString *block in [self ytv2_blocks:key in:s limit:16]) { NSString *t = [self ytv2_first:block patterns:@[@"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"token\"\\s*:\\s*\"([^\"]+)\""]]; if (t.length) return t; }
    return [self ytv2_first:s patterns:@[@"\"continuationCommand\".*?\"token\"\\s*:\\s*\"([^\"]+)\"", @"\"timedContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\"", @"\"reloadContinuationData\".*?\"continuation\"\\s*:\\s*\"([^\"]+)\""]];
}

+ (NSArray<NSString *> *)ytv2_blocks:(NSString *)key in:(NSString *)s limit:(NSInteger)limit {
    NSMutableArray *arr = [NSMutableArray array];
    NSString *marker = [NSString stringWithFormat:@"\"%@\"", key];
    NSRange search = NSMakeRange(0, s.length);
    while (arr.count < limit) {
        NSRange r = [s rangeOfString:marker options:0 range:search];
        if (r.location == NSNotFound) break;
        NSRange bs = NSMakeRange(NSMaxRange(r), s.length - NSMaxRange(r));
        NSRange br = [s rangeOfString:@"{" options:0 range:bs];
        if (br.location == NSNotFound) break;
        NSString *block = [self ytv2_balanced:s start:br.location max:60000];
        if (block.length) [arr addObject:block];
        NSUInteger next = br.location + MAX((NSUInteger)1, block.length);
        if (next >= s.length) break;
        search = NSMakeRange(next, s.length - next);
    }
    return arr;
}

+ (NSString *)ytv2_balanced:(NSString *)s start:(NSUInteger)start max:(NSUInteger)maxLen {
    if (start >= s.length || [s characterAtIndex:start] != '{') return @"";
    NSUInteger end = MIN(s.length, start + maxLen);
    NSInteger depth = 0; BOOL str = NO; BOOL esc = NO;
    for (NSUInteger i=start; i<end; i++) { unichar c=[s characterAtIndex:i]; if (str) { if (esc) esc=NO; else if (c=='\\') esc=YES; else if (c=='"') str=NO; } else { if (c=='"') str=YES; else if (c=='{') depth++; else if (c=='}') { depth--; if (depth==0) return [s substringWithRange:NSMakeRange(start, i-start+1)]; } } }
    return @"";
}

+ (NSString *)ytv2_first:(NSString *)s patterns:(NSArray<NSString *> *)patterns { for (NSString *p in patterns) { NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:p options:NSRegularExpressionDotMatchesLineSeparators error:nil]; NSTextCheckingResult *m=[re firstMatchInString:s options:0 range:NSMakeRange(0,s.length)]; if (m && m.numberOfRanges>=2) return [s substringWithRange:[m rangeAtIndex:1]]; } return @""; }
+ (NSString *)ytv2_textFromRuns:(NSString *)runs { NSMutableString *out=[NSMutableString string]; NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"\"text\"\\s*:\\s*\"([^\"]*)\"" options:0 error:nil]; for (NSTextCheckingResult *m in [re matchesInString:runs options:0 range:NSMakeRange(0,runs.length)]) if (m.numberOfRanges>=2) [out appendString:[self ytv2_unescape:[runs substringWithRange:[m rangeAtIndex:1]]]]; return [self ytv2_norm:out]; }
+ (unsigned long long)ytv2_ull:(NSString *)s { if (![s isKindOfClass:NSString.class] || s.length==0) return 0; return strtoull(s.UTF8String, NULL, 10); }
+ (NSString *)ytv2_unescape:(NSString *)s { if (![s isKindOfClass:NSString.class]) return @""; s=[s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "]; s=[s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""]; s=[s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]; s=[s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"]; s=[s stringByReplacingOccurrencesOfString:@"\\u003c" withString:@"<"]; s=[s stringByReplacingOccurrencesOfString:@"\\u003e" withString:@">"]; return s; }
+ (NSString *)ytv2_norm:(id)obj { if (![obj isKindOfClass:NSString.class]) return @""; NSString *s=[(NSString *)obj stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; while ([s rangeOfString:@"  "].location != NSNotFound) s=[s stringByReplacingOccurrencesOfString:@"  " withString:@" "]; return s; }

@end

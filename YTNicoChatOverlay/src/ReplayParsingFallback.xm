#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static NSMutableDictionary<NSNumber *, NSNumber *> *YTNicoRPBaseTimestampUsecByGeneration;
static NSMutableDictionary<NSNumber *, NSNumber *> *YTNicoRPSyntheticOffsetByGeneration;

static NSString *YTNicoRPFirst(NSString *s, NSArray<NSString *> *patterns) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static NSString *YTNicoRPBalanced(NSString *s, NSUInteger start, NSUInteger maxLen) {
    if (start >= s.length || [s characterAtIndex:start] != '{') return @"";
    NSUInteger end = MIN(s.length, start + maxLen);
    NSInteger depth = 0;
    BOOL inString = NO;
    BOOL escape = NO;
    for (NSUInteger i = start; i < end; i++) {
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

static NSArray<NSString *> *YTNicoRPBlocks(NSString *key, NSString *s, NSInteger limit) {
    NSMutableArray *arr = [NSMutableArray array];
    if (key.length == 0 || s.length == 0) return arr;
    NSString *marker = [NSString stringWithFormat:@"\"%@\"", key];
    NSRange search = NSMakeRange(0, s.length);
    while (arr.count < limit) {
        NSRange r = [s rangeOfString:marker options:0 range:search];
        if (r.location == NSNotFound) break;
        NSRange remain = NSMakeRange(NSMaxRange(r), s.length - NSMaxRange(r));
        NSRange br = [s rangeOfString:@"{" options:0 range:remain];
        if (br.location == NSNotFound) break;
        NSString *block = YTNicoRPBalanced(s, br.location, 90000);
        if (block.length > 0) [arr addObject:block];
        NSUInteger next = br.location + MAX((NSUInteger)1, block.length);
        if (next >= s.length) break;
        search = NSMakeRange(next, s.length - next);
    }
    return arr;
}

static NSString *YTNicoRPUnescape(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\r" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003c" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003e" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"\\u003d" withString:@"="];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s;
}

static NSString *YTNicoRPTextFromRuns(NSString *runs) {
    if (runs.length == 0) return @"";
    NSMutableString *out = [NSMutableString string];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\"text\"\\s*:\\s*\"([^\"]*)\"" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:runs options:0 range:NSMakeRange(0, runs.length)]) {
        if (m.numberOfRanges >= 2) [out appendString:YTNicoRPUnescape([runs substringWithRange:[m rangeAtIndex:1]])];
    }
    return YTNicoRPUnescape(out);
}

static NSDictionary *YTNicoRPAuthorText(NSString *block) {
    NSString *author = YTNicoRPFirst(block, @[
        @"\"authorName\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
        @"\"authorName\".*?\"text\"\\s*:\\s*\"([^\"]+)\"",
        @"\"authorText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
        @"\"displayName\"\\s*:\\s*\"([^\"]+)\""
    ]);
    NSString *runs = YTNicoRPFirst(block, @[
        @"\"message\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]",
        @"\"contentText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]",
        @"\"bodyText\".*?\"runs\"\\s*:\\s*\\[(.*?)\\]"
    ]);
    NSString *text = YTNicoRPTextFromRuns(runs);
    if (text.length == 0) {
        text = YTNicoRPFirst(block, @[
            @"\"message\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
            @"\"contentText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
            @"\"bodyText\".*?\"simpleText\"\\s*:\\s*\"([^\"]+)\"",
            @"\"text\"\\s*:\\s*\"([^\"]+)\""
        ]);
    }
    return @{@"a":YTNicoRPUnescape(author ?: @""), @"t":YTNicoRPUnescape(text ?: @"")};
}

static unsigned long long YTNicoRPTimestampUsecFromBlock(NSString *block) {
    NSString *ts = YTNicoRPFirst(block, @[
        @"\"timestampUsec\"\\s*:\\s*\"?([0-9]+)\"?",
        @"\"timestamp_usec\"\\s*:\\s*\"?([0-9]+)\"?",
        @"\"timestamp\"\\s*:\\s*\"?([0-9]{13,})\"?"
    ]);
    if (ts.length == 0) return 0;
    return strtoull(ts.UTF8String, NULL, 10);
}

static unsigned long long YTNicoRPNextSyntheticOffset(NSUInteger generation) {
    if (!YTNicoRPSyntheticOffsetByGeneration) YTNicoRPSyntheticOffsetByGeneration = [NSMutableDictionary dictionary];
    NSNumber *key = @(generation);
    unsigned long long current = [YTNicoRPSyntheticOffsetByGeneration[key] unsignedLongLongValue];
    YTNicoRPSyntheticOffsetByGeneration[key] = @(current + 900);
    return current;
}

static unsigned long long YTNicoRPOffsetFromBlock(NSString *block, NSUInteger generation) {
    NSString *off = YTNicoRPFirst(block, @[
        @"\"videoOffsetTimeMsec\"\\s*:\\s*\"?([0-9]+)\"?",
        @"\"videoOffsetTimeMs\"\\s*:\\s*\"?([0-9]+)\"?",
        @"\"offsetTimeMsec\"\\s*:\\s*\"?([0-9]+)\"?",
        @"\"offsetMs\"\\s*:\\s*\"?([0-9]+)\"?"
    ]);
    if (off.length > 0) return strtoull(off.UTF8String, NULL, 10);

    unsigned long long ts = YTNicoRPTimestampUsecFromBlock(block);
    if (ts > 0) {
        if (!YTNicoRPBaseTimestampUsecByGeneration) YTNicoRPBaseTimestampUsecByGeneration = [NSMutableDictionary dictionary];
        NSNumber *key = @(generation);
        unsigned long long base = [YTNicoRPBaseTimestampUsecByGeneration[key] unsignedLongLongValue];
        if (base == 0 || ts < base) {
            base = ts;
            YTNicoRPBaseTimestampUsecByGeneration[key] = @(base);
        }
        if (ts >= base) return (ts - base) / 1000ULL;
    }

    return YTNicoRPNextSyntheticOffset(generation);
}

static NSInteger YTNicoRPEmitRenderersFromBlock(NSString *container, unsigned long long inheritedOffsetMs, NSUInteger generation, NSInteger max, NSMutableSet<NSString *> *seen) {
    NSInteger count = 0;
    NSArray *rendererKeys = @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer", @"liveChatPaidStickerRenderer", @"liveChatPlaceholderItemRenderer"];
    for (NSString *rendererKey in rendererKeys) {
        for (NSString *block in YTNicoRPBlocks(rendererKey, container, 100)) {
            if (count >= max) return count;
            NSDictionary *p = YTNicoRPAuthorText(block);
            NSString *author = p[@"a"] ?: @"";
            NSString *text = p[@"t"] ?: @"";
            if (text.length == 0) continue;
            unsigned long long offsetMs = YTNicoRPOffsetFromBlock(block, generation);
            if (offsetMs == 0 && inheritedOffsetMs > 0) offsetMs = inheritedOffsetMs;
            NSString *dedup = [NSString stringWithFormat:@"%llu|%@|%@", offsetMs, author, text];
            if ([seen containsObject:dedup]) continue;
            [seen addObject:dedup];
            NSString *mid = [NSString stringWithFormat:@"replayts-%llu-%lu-%lu", offsetMs, (unsigned long)[dedup hash], (unsigned long)generation];
            [YouTubeChatAdapter queueTimedReplayAuthor:author.length ? author : @"chat" text:text messageId:mid offsetMilliseconds:offsetMs generation:generation];
            count++;
        }
    }
    return count;
}

%hook YouTubeChatAdapter

+ (NSInteger)ytv2_parseReplay:(NSString *)s max:(NSInteger)max generation:(NSUInteger)generation {
    NSInteger total = 0;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    // Parse replay actions first. This keeps true videoOffsetTimeMsec sync when YouTube provides it.
    NSArray *actionKeys = @[@"replayChatItemAction", @"addChatItemAction", @"replaceChatItemAction"];
    for (NSString *actionKey in actionKeys) {
        for (NSString *action in YTNicoRPBlocks(actionKey, s, 520)) {
            if (total >= max) break;
            unsigned long long offsetMs = YTNicoRPOffsetFromBlock(action, generation);
            total += YTNicoRPEmitRenderersFromBlock(action, offsetMs, generation, max - total, seen);
        }
    }

    // Premiere archives sometimes expose renderers without replayChatItemAction.
    if (total == 0) {
        for (NSString *rendererKey in @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatMembershipItemRenderer", @"liveChatPaidStickerRenderer"]) {
            for (NSString *block in YTNicoRPBlocks(rendererKey, s, MIN(max, 360))) {
                if (total >= max) break;
                NSDictionary *p = YTNicoRPAuthorText(block);
                NSString *author = p[@"a"] ?: @"";
                NSString *text = p[@"t"] ?: @"";
                if (text.length == 0) continue;
                unsigned long long offsetMs = YTNicoRPOffsetFromBlock(block, generation);
                NSString *dedup = [NSString stringWithFormat:@"%llu|%@|%@", offsetMs, author, text];
                if ([seen containsObject:dedup]) continue;
                [seen addObject:dedup];
                NSString *mid = [NSString stringWithFormat:@"replayts-direct-%llu-%lu-%lu", offsetMs, (unsigned long)[dedup hash], (unsigned long)generation];
                [YouTubeChatAdapter queueTimedReplayAuthor:author.length ? author : @"chat" text:text messageId:mid offsetMilliseconds:offsetMs generation:generation];
                total++;
            }
        }
    }

    [[DebugInspector shared] important:@"replay timestamp parser queued=%ld playback=%.2f base=%@ synthetic=%@", (long)total, [YouTubeChatAdapter currentPlaybackSeconds], YTNicoRPBaseTimestampUsecByGeneration[@(generation)], YTNicoRPSyntheticOffsetByGeneration[@(generation)]];
    return total;
}

%end

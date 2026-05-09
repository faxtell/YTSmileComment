#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSTimer *gYTNicoDelayedChatScanTimer = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoDelayedSeen = nil;
static CFTimeInterval gYTNicoDelayedLastLog = 0;
static CGFloat gYTNicoDelayedHeaderBottomY = 0;
static CFTimeInterval gYTNicoDelayedHeaderSeenAt = 0;

static BOOL YTNicoDelayedIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoDelayedTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static CGRect YTNicoDelayedWindowRect(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoDelayedContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *n in needles) if ([lower rangeOfString:n.lowercaseString].location != NSNotFound) return YES;
    return NO;
}

static BOOL YTNicoDelayedIsHeaderText(NSString *text) {
    text = YTNicoDelayedTrim(text);
    return [text isEqualToString:@"チャットのリプレイ"] ||
           [text isEqualToString:@"ライブチャット"] ||
           [text isEqualToString:@"上位のメッセージ"] ||
           [text isEqualToString:@"上位チャット"] ||
           [text isEqualToString:@"すべてのチャット"];
}

static BOOL YTNicoDelayedIsShortReaction(NSString *text) {
    text = YTNicoDelayedTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w{1,}|ｗ{1,}|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoDelayedLooksLikeMetadata(NSString *text) {
    text = YTNicoDelayedTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoDelayedIsShortReaction(text)) return NO;
    if ([text rangeOfString:@"回視聴"].location != NSNotFound) return YES;
    if ([text rangeOfString:@"人が視聴中"].location != NSNotFound) return YES;
    NSArray *exact = @[@"返信", @"共有", @"保存", @"チャンネル登録", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定"];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;
    NSArray *contains = @[@"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium"];
    if (YTNicoDelayedContainsAny(text, contains)) return YES;
    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

static BOOL YTNicoDelayedLooksLikeHandle(NSString *text) {
    text = YTNicoDelayedTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return NO;
    if (text.length > 84) return NO;
    if ([text rangeOfString:@"。"].location != NSNotFound || [text rangeOfString:@"！"].location != NSNotFound || [text rangeOfString:@"？"].location != NSNotFound) return NO;
    return YES;
}

static NSString *YTNicoDelayedStripSeparatedHandle(NSString *text) {
    text = YTNicoDelayedTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *withSep = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：]+[\\s　:：-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [withSep firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoDelayedTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return text;
}

static void YTNicoDelayedCollectLabels(UIView *view, NSMutableArray<NSDictionary *> *out, BOOL includeHeader) {
    if (!view || view.hidden || view.alpha < 0.02 || !view.window) return;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = YTNicoDelayedTrim(label.text ?: label.attributedText.string ?: @"");
        if (text.length > 0) {
            CGRect r = YTNicoDelayedWindowRect(label);
            if (!CGRectIsEmpty(r)) {
                if (includeHeader || !YTNicoDelayedIsHeaderText(text)) {
                    [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(r)), @"y": @(CGRectGetMidY(r)), @"h": @(CGRectGetHeight(r)), @"w": @(CGRectGetWidth(r)), @"view": label}];
                }
            }
        }
    }
    for (UIView *sub in view.subviews) YTNicoDelayedCollectLabels(sub, out, includeHeader);
}

static CGFloat YTNicoDelayedFindChatHeader(UIWindow *win) {
    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoDelayedCollectLabels(win, labels, YES);
    CGRect wb = win.bounds;
    CGFloat best = 0;
    for (NSDictionary *item in labels) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoDelayedIsHeaderText(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y < wb.size.height * 0.22) continue;
        best = MAX(best, y + h / 2.0);
    }
    if (best > 0) {
        gYTNicoDelayedHeaderBottomY = best;
        gYTNicoDelayedHeaderSeenAt = CACurrentMediaTime();
    }
    return best;
}

static NSString *YTNicoDelayedBodyFromItems(NSArray<NSDictionary *> *items) {
    NSArray<NSDictionary *> *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 10.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue];
        CGFloat bx = [b[@"x"] doubleValue];
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *item in sorted) {
        NSString *t = YTNicoDelayedTrim(item[@"text"] ?: @"");
        if (t.length == 0 || [seen containsObject:t]) continue;
        [seen addObject:t];
        if (YTNicoDelayedLooksLikeMetadata(t)) continue;
        if (YTNicoDelayedLooksLikeHandle(t) && sorted.count > 1) continue;
        NSString *body = YTNicoDelayedStripSeparatedHandle(t);
        if (body.length > 0) [parts addObject:body];
    }
    return YTNicoDelayedTrim([parts componentsJoinedByString:@" "]);
}

static void YTNicoDelayedEmit(NSString *body, NSString *key) {
    body = YTNicoDelayedTrim(body);
    if (body.length == 0 || YTNicoDelayedLooksLikeMetadata(body)) return;
    if (!gYTNicoDelayedSeen) gYTNicoDelayedSeen = [NSMutableDictionary dictionary];
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *k in gYTNicoDelayedSeen) if (now - gYTNicoDelayedSeen[k].doubleValue > 8.0) [remove addObject:k];
    [gYTNicoDelayedSeen removeObjectsForKeys:remove];
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"late", body];
    if (gYTNicoDelayedSeen[seenKey]) return;
    gYTNicoDelayedSeen[seenKey] = @(now);
    NSString *mid = [NSString stringWithFormat:@"lateui-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(now * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
    if (SettingsManager.shared.debugLogging && now - gYTNicoDelayedLastLog > 1.0) {
        gYTNicoDelayedLastLog = now;
        [[DebugInspector shared] important:@"late chat panel emitted %@", body];
    }
}

static void YTNicoDelayedScanWindow(UIWindow *win) {
    if (!win || win.hidden || win.alpha < 0.02) return;
    CGFloat headerBottom = YTNicoDelayedFindChatHeader(win);
    if (headerBottom <= 0 && gYTNicoDelayedHeaderBottomY > 0 && CACurrentMediaTime() - gYTNicoDelayedHeaderSeenAt < 20.0) headerBottom = gYTNicoDelayedHeaderBottomY;
    if (headerBottom <= 0) return;

    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoDelayedCollectLabels(win, labels, NO);
    if (labels.count == 0) return;

    NSMutableDictionary<NSNumber *, NSMutableArray<NSDictionary *> *> *rows = [NSMutableDictionary dictionary];
    CGRect wb = win.bounds;
    for (NSDictionary *item in labels) {
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat x = [item[@"x"] doubleValue];
        if (y <= headerBottom + 18.0) continue;
        if (y > wb.size.height - 8.0) continue;
        if (x < -20.0 || x > wb.size.width + 20.0) continue;
        NSString *text = item[@"text"] ?: @"";
        if (YTNicoDelayedLooksLikeMetadata(text)) continue;
        NSNumber *bucket = @((NSInteger)round(y / 28.0));
        NSMutableArray *arr = rows[bucket];
        if (!arr) { arr = [NSMutableArray array]; rows[bucket] = arr; }
        [arr addObject:item];
    }

    for (NSNumber *bucket in rows) {
        NSArray *items = rows[bucket];
        NSString *body = YTNicoDelayedBodyFromItems(items);
        if (body.length == 0) continue;
        NSString *key = [NSString stringWithFormat:@"late-%ld", (long)bucket.integerValue];
        YTNicoDelayedEmit(body, key);
    }
}

static void YTNicoDelayedPeriodicScan(void) {
    if (!YTNicoDelayedIsYouTube()) return;
    SettingsManager *settings = SettingsManager.shared;
    if (!settings.enabled) return;
    if ([settings respondsToSelector:@selector(uiScrapeFallback)] && !settings.uiScrapeFallback) return;
    for (UIWindow *win in UIApplication.sharedApplication.windows) YTNicoDelayedScanWindow(win);
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoDelayedIsYouTube()) return;
        gYTNicoDelayedSeen = [NSMutableDictionary dictionary];
        if (!gYTNicoDelayedChatScanTimer) {
            gYTNicoDelayedChatScanTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:YES block:^(__unused NSTimer *timer) {
                YTNicoDelayedPeriodicScan();
            }];
            [[NSRunLoop mainRunLoop] addTimer:gYTNicoDelayedChatScanTimer forMode:NSRunLoopCommonModes];
        }
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"delayed chat panel scanner loaded"];
    });
}

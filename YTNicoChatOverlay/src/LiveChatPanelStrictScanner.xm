#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static dispatch_source_t gYTNicoStrictScanTimer = nil;
static NSString *gYTNicoStrictScanVideoId = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoStrictSeen = nil;
static BOOL gYTNicoStrictScanning = NO;

typedef NSDictionary<NSString *, id> YTNicoStrictTextItem;

static BOOL YTNicoStrictIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoStrictTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static CGRect YTNicoStrictRectInWindow(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoStrictContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([lower rangeOfString:needle.lowercaseString].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL YTNicoStrictIsHeader(NSString *text) {
    text = YTNicoStrictTrim(text);
    return [text isEqualToString:@"チャットのリプレイ"] ||
           [text isEqualToString:@"ライブチャット"] ||
           [text isEqualToString:@"上位のメッセージ"] ||
           [text isEqualToString:@"上位チャット"] ||
           [text isEqualToString:@"すべてのチャット"] ||
           [text hasPrefix:@"チャットのリプレイ "] ||
           [text hasPrefix:@"ライブチャット "];
}

static BOOL YTNicoStrictHasHandle(NSString *text) {
    text = YTNicoStrictTrim(text);
    if (text.length == 0) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(^|[\\s　])[@＠][A-Za-z0-9_\\-.一-龯ぁ-んァ-ヶー]{2,84}" options:0 error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoStrictIsHandleOnly(NSString *text) {
    text = YTNicoStrictTrim(text);
    if (text.length == 0 || text.length > 96) return NO;
    if (!YTNicoStrictHasHandle(text)) return NO;
    if ([text rangeOfString:@" "].location != NSNotFound || [text rangeOfString:@"　"].location != NSNotFound) return NO;
    if ([text rangeOfString:@"。"].location != NSNotFound || [text rangeOfString:@"！"].location != NSNotFound || [text rangeOfString:@"？"].location != NSNotFound) return NO;
    return YES;
}

static BOOL YTNicoStrictIsShortReaction(NSString *text) {
    text = YTNicoStrictTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(0|w+|ｗ+|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|ドキドキ|ワクワク|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoStrictLooksLikeMetadata(NSString *text) {
    text = YTNicoStrictTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoStrictIsShortReaction(text)) return NO;
    if (YTNicoStrictIsHeader(text)) return YES;

    NSArray *exact = @[@"返信", @"共有", @"保存", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定", @"閉じる", @"フィルタ", @"その他", @"新着", @"メンバーになる"];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;

    NSArray *blocked = @[
        @"回視聴", @"人が視聴中", @"チャンネル登録", @"操作メニュー", @"概要欄",
        @"動画を再生", @"コメントを見る", @"この動画のライブ配信時", @"メッセージを入力",
        @"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium",
        @"CUTIE STREET", @"FRUITS ZIPPER", @"関連動画", @"次の動画", @"ショート", @"ホーム"
    ];
    if (YTNicoStrictContainsAny(text, blocked)) return YES;

    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    return NO;
}

static NSString *YTNicoStrictStripHandle(NSString *text) {
    text = YTNicoStrictTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：,，、]+[\\s　:：,，、-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoStrictTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return @"";
}

static BOOL YTNicoStrictBodyLooksSafe(NSString *body) {
    body = YTNicoStrictTrim(body);
    if (body.length == 0 || body.length > 140) return NO;
    if (YTNicoStrictLooksLikeMetadata(body)) return NO;
    if (YTNicoStrictHasHandle(body)) body = YTNicoStrictStripHandle(body);
    if (body.length == 0 || YTNicoStrictLooksLikeMetadata(body)) return NO;

    // A very long mixed Japanese/Korean/ASCII string is usually a title, accessibility dump, or related-video text, not one chat row.
    NSUInteger spaces = [[body componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count] - 1;
    if (body.length > 70 && spaces >= 5) return NO;
    if ([body rangeOfString:@"\n"].location != NSNotFound && body.length > 60) return NO;
    return YES;
}

static void YTNicoStrictAddItem(NSMutableArray<YTNicoStrictTextItem *> *out, NSString *rawText, CGRect rect) {
    NSString *text = YTNicoStrictTrim(rawText);
    if (text.length == 0 || CGRectIsEmpty(rect)) return;
    [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(rect)), @"y": @(CGRectGetMidY(rect)), @"h": @(CGRectGetHeight(rect)), @"w": @(CGRectGetWidth(rect))}];
}

static void YTNicoStrictCollectAccessibility(id object, UIView *fallbackView, NSMutableArray<YTNicoStrictTextItem *> *out) {
    if (!object || out.count > 420) return;
    CGRect fallback = YTNicoStrictRectInWindow(fallbackView);
    if ([object isKindOfClass:NSString.class]) { YTNicoStrictAddItem(out, object, fallback); return; }
    if ([object isKindOfClass:NSAttributedString.class]) { YTNicoStrictAddItem(out, [(NSAttributedString *)object string], fallback); return; }
    CGRect rect = fallback;
    if ([object isKindOfClass:UIView.class]) rect = YTNicoStrictRectInWindow((UIView *)object);
    else if ([object respondsToSelector:@selector(accessibilityFrame)]) {
        CGRect ax = [object accessibilityFrame];
        if (!CGRectIsEmpty(ax)) rect = ax;
    }
    if ([object respondsToSelector:@selector(accessibilityLabel)]) YTNicoStrictAddItem(out, [object accessibilityLabel] ?: @"", rect);
    if ([object respondsToSelector:@selector(accessibilityValue)]) YTNicoStrictAddItem(out, [object accessibilityValue] ?: @"", rect);
}

static void YTNicoStrictCollectText(UIView *view, NSMutableArray<YTNicoStrictTextItem *> *out) {
    if (!view || view.hidden || view.alpha < 0.02 || out.count > 420) return;
    CGRect rect = YTNicoStrictRectInWindow(view);
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        YTNicoStrictAddItem(out, label.text ?: label.attributedText.string ?: @"", rect);
    } else if ([view isKindOfClass:UITextView.class]) {
        YTNicoStrictAddItem(out, [(UITextView *)view text] ?: @"", rect);
    }
    YTNicoStrictAddItem(out, view.accessibilityLabel ?: @"", rect);
    NSArray *elements = view.accessibilityElements;
    if ([elements isKindOfClass:NSArray.class]) {
        for (id e in elements) YTNicoStrictCollectAccessibility(e, view, out);
    }
    for (UIView *sub in view.subviews) YTNicoStrictCollectText(sub, out);
}

static CGFloat YTNicoStrictChatPanelTop(UIWindow *win, NSArray<YTNicoStrictTextItem *> *items) {
    CGRect wb = win.bounds;
    CGFloat top = 0.0;
    for (YTNicoStrictTextItem *item in items) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoStrictIsHeader(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y < wb.size.height * 0.20) continue;
        top = MAX(top, y + h / 2.0 + 10.0);
    }
    return top;
}

static NSString *YTNicoStrictBodyFromRow(NSArray<YTNicoStrictTextItem *> *row) {
    if (row.count == 0) return @"";
    NSArray *sorted = [row sortedArrayUsingComparator:^NSComparisonResult(YTNicoStrictTextItem *a, YTNicoStrictTextItem *b) {
        CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 9.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue], bx = [b[@"x"] doubleValue];
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];

    BOOL hasAuthor = NO;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seenParts = [NSMutableSet set];
    for (YTNicoStrictTextItem *item in sorted) {
        NSString *t = YTNicoStrictTrim(item[@"text"] ?: @"");
        if (t.length == 0 || [seenParts containsObject:t]) continue;
        [seenParts addObject:t];
        if (YTNicoStrictLooksLikeMetadata(t)) continue;

        if (YTNicoStrictHasHandle(t)) {
            hasAuthor = YES;
            NSString *stripped = YTNicoStrictStripHandle(t);
            if (stripped.length > 0 && YTNicoStrictBodyLooksSafe(stripped)) [parts addObject:stripped];
            continue;
        }
        if (YTNicoStrictIsHandleOnly(t)) { hasAuthor = YES; continue; }
        if (hasAuthor || sorted.count >= 2) {
            if (YTNicoStrictBodyLooksSafe(t)) [parts addObject:t];
        }
    }
    if (!hasAuthor) return @"";
    NSString *body = YTNicoStrictTrim([parts componentsJoinedByString:@" "]);
    if (!YTNicoStrictBodyLooksSafe(body)) return @"";
    return body;
}

static void YTNicoStrictPruneSeen(void) {
    if (!gYTNicoStrictSeen) gYTNicoStrictSeen = [NSMutableDictionary dictionary];
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *k in gYTNicoStrictSeen) {
        if (now - gYTNicoStrictSeen[k].doubleValue > 90.0) [remove addObject:k];
    }
    [gYTNicoStrictSeen removeObjectsForKeys:remove];
}

static void YTNicoStrictEmit(NSString *body, NSString *key) {
    body = YTNicoStrictTrim(body);
    if (!YTNicoStrictBodyLooksSafe(body)) return;
    if (!gYTNicoStrictSeen) gYTNicoStrictSeen = [NSMutableDictionary dictionary];
    YTNicoStrictPruneSeen();
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"strict-ui", body];
    if (gYTNicoStrictSeen[seenKey]) return;
    gYTNicoStrictSeen[seenKey] = @(CACurrentMediaTime());
    NSString *mid = [NSString stringWithFormat:@"strictui-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
}

static void YTNicoStrictScanOnce(void) {
    if (gYTNicoStrictScanning || !YTNicoStrictIsYouTube() || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !SettingsManager.shared.enabled) return;
    gYTNicoStrictScanning = YES;
    @try {
        for (UIWindow *win in UIApplication.sharedApplication.windows) {
            if (!win || win.hidden || win.alpha < 0.02) continue;
            NSMutableArray<YTNicoStrictTextItem *> *all = [NSMutableArray array];
            YTNicoStrictCollectText(win, all);
            if (all.count == 0) continue;
            CGFloat panelTop = YTNicoStrictChatPanelTop(win, all);
            if (panelTop <= 0.0) continue; // Do not scrape the whole YouTube UI unless the chat sheet header is actually visible.

            CGRect wb = win.bounds;
            NSMutableArray<YTNicoStrictTextItem *> *anchors = [NSMutableArray array];
            for (YTNicoStrictTextItem *item in all) {
                NSString *text = YTNicoStrictTrim(item[@"text"] ?: @"");
                CGFloat y = [item[@"y"] doubleValue];
                CGFloat x = [item[@"x"] doubleValue];
                if (y < panelTop || y > wb.size.height - 8.0 || x < -20.0 || x > wb.size.width + 20.0) continue;
                if (YTNicoStrictLooksLikeMetadata(text)) continue;
                if (YTNicoStrictHasHandle(text)) [anchors addObject:item];
            }
            NSArray *sortedAnchors = [anchors sortedArrayUsingComparator:^NSComparisonResult(YTNicoStrictTextItem *a, YTNicoStrictTextItem *b) {
                CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
                return ay < by ? NSOrderedAscending : (ay > by ? NSOrderedDescending : NSOrderedSame);
            }];

            for (NSUInteger i = 0; i < sortedAnchors.count; i++) {
                YTNicoStrictTextItem *anchor = sortedAnchors[i];
                CGFloat ay = [anchor[@"y"] doubleValue];
                CGFloat ax = [anchor[@"x"] doubleValue];
                CGFloat prevY = (i > 0) ? [sortedAnchors[i - 1][@"y"] doubleValue] : panelTop;
                CGFloat nextY = (i + 1 < sortedAnchors.count) ? [sortedAnchors[i + 1][@"y"] doubleValue] : MIN(wb.size.height, ay + 58.0);
                CGFloat top = MAX(panelTop, (prevY + ay) / 2.0 - 4.0);
                CGFloat bottom = MIN(wb.size.height - 8.0, (ay + nextY) / 2.0 + 6.0);
                if (bottom - top < 30.0) bottom = MIN(wb.size.height - 8.0, top + 40.0);

                NSMutableArray *row = [NSMutableArray array];
                for (YTNicoStrictTextItem *item in all) {
                    CGFloat y = [item[@"y"] doubleValue];
                    CGFloat x = [item[@"x"] doubleValue];
                    NSString *text = item[@"text"] ?: @"";
                    if (y < top || y > bottom || x < ax - 24.0 || x > wb.size.width + 20.0) continue;
                    if (YTNicoStrictLooksLikeMetadata(text)) continue;
                    [row addObject:item];
                }
                NSString *body = YTNicoStrictBodyFromRow(row);
                if (body.length == 0) continue;
                NSString *key = [NSString stringWithFormat:@"strict-row-%lu-%lu", (unsigned long)[body hash], (unsigned long)round(ay / 20.0)];
                YTNicoStrictEmit(body, key);
            }
        }
    } @finally {
        gYTNicoStrictScanning = NO;
    }
}

static void YTNicoStrictStopWatch(void) {
    if (gYTNicoStrictScanTimer) {
        dispatch_source_cancel(gYTNicoStrictScanTimer);
        gYTNicoStrictScanTimer = nil;
    }
    gYTNicoStrictScanVideoId = nil;
    [gYTNicoStrictSeen removeAllObjects];
}

static void YTNicoStrictStartWatch(NSString *videoId) {
    if (!YTNicoStrictIsYouTube()) return;
    if (!gYTNicoStrictSeen) gYTNicoStrictSeen = [NSMutableDictionary dictionary];
    YTNicoStrictStopWatch();
    gYTNicoStrictScanVideoId = [videoId copy];
    gYTNicoStrictScanTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!gYTNicoStrictScanTimer) return;
    uint64_t interval = (uint64_t)(0.85 * (double)NSEC_PER_SEC);
    uint64_t leeway = (uint64_t)(0.12 * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(gYTNicoStrictScanTimer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, leeway);
    dispatch_source_set_event_handler(gYTNicoStrictScanTimer, ^{
        if (!SettingsManager.shared.enabled || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        NSString *current = [YouTubeChatAdapter currentVideoId] ?: @"";
        if (gYTNicoStrictScanVideoId.length == 11 && current.length == 11 && ![current isEqualToString:gYTNicoStrictScanVideoId]) {
            YTNicoStrictStopWatch();
            [[DebugInspector shared] important:@"strict chat panel scanner stopped: video changed"];
            return;
        }
        YTNicoStrictScanOnce();
    });
    dispatch_resume(gYTNicoStrictScanTimer);
    [[DebugInspector shared] important:@"strict chat panel scanner started videoId=%@", gYTNicoStrictScanVideoId ?: @""];
}

%hook YTNicoController
- (void)toggleOverlayEnabled {
    %orig;
    NSString *videoId = [YouTubeChatAdapter currentVideoId] ?: @"";
    YTNicoStrictStartWatch(videoId.length == 11 ? videoId : nil);
}

- (void)clearOverlayForVideoChange {
    YTNicoStrictStopWatch();
    %orig;
}

- (void)reloadSettings {
    if (!SettingsManager.shared.enabled) YTNicoStrictStopWatch();
    %orig;
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoStrictIsYouTube()) return;
        gYTNicoStrictSeen = [NSMutableDictionary dictionary];
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"strict live chat panel scanner loaded"];
    });
}

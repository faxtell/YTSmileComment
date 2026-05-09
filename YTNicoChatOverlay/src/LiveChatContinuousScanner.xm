#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static dispatch_source_t gYTNicoLiveScanTimer = nil;
static NSString *gYTNicoLiveScanVideoId = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoLiveScanSeen = nil;
static BOOL gYTNicoLiveScanRunning = NO;

typedef NSDictionary<NSString *, id> YTNicoLiveTextItem;

static BOOL YTNicoLiveIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoLiveTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@", " withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"、 " withString:@" "];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static CGRect YTNicoLiveRectInWindow(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoLiveContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *needle in needles) if ([lower rangeOfString:needle.lowercaseString].location != NSNotFound) return YES;
    return NO;
}

static BOOL YTNicoLiveIsHeader(NSString *text) {
    text = YTNicoLiveTrim(text);
    return [text rangeOfString:@"ライブチャット"].location != NSNotFound ||
           [text rangeOfString:@"チャットのリプレイ"].location != NSNotFound ||
           [text rangeOfString:@"上位のメッセージ"].location != NSNotFound ||
           [text rangeOfString:@"上位チャット"].location != NSNotFound ||
           [text rangeOfString:@"すべてのチャット"].location != NSNotFound;
}

static BOOL YTNicoLiveHasHandle(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (text.length == 0) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(^|[\\s　])[@＠][^\\s　:：,，、]{2,}" options:0 error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoLiveIsShortReaction(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w+|ｗ+|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoLiveLooksLikeMetadata(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoLiveIsShortReaction(text)) return NO;
    if (YTNicoLiveIsHeader(text)) return YES;
    if ([text rangeOfString:@"回視聴"].location != NSNotFound) return YES;
    if ([text rangeOfString:@"人が視聴中"].location != NSNotFound) return YES;
    if ([text rangeOfString:@"チャンネル登録"].location != NSNotFound) return YES;

    NSArray *exact = @[@"返信", @"共有", @"保存", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定", @"閉じる", @"フィルタ", @"その他", @"メンバーになる"];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;

    NSArray *contains = @[@"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium", @"操作メニュー", @"に移動します", @"コメントを見る", @"この動画のライブ配信時", @"チャット欄を開いてから", @"固定されています", @"メッセージを入力"];
    if (YTNicoLiveContainsAny(text, contains)) return YES;

    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    return NO;
}

static BOOL YTNicoLiveLooksLikeAuthorOnly(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (text.length == 0 || text.length > 40) return NO;
    if (YTNicoLiveIsShortReaction(text)) return NO;
    if (YTNicoLiveHasHandle(text)) return YES;
    if ([text rangeOfString:@"。"].location != NSNotFound ||
        [text rangeOfString:@"！"].location != NSNotFound ||
        [text rangeOfString:@"？"].location != NSNotFound ||
        [text rangeOfString:@"!"].location != NSNotFound ||
        [text rangeOfString:@"?"].location != NSNotFound ||
        [text rangeOfString:@"w" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [text rangeOfString:@"ｗ"].location != NSNotFound ||
        [text rangeOfString:@"草"].location != NSNotFound) return NO;
    return YES;
}

static NSString *YTNicoLiveStripHandle(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：,，、]+[\\s　:：,，、-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoLiveTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return @"";
}

static NSString *YTNicoLiveBodyFromSingleText(NSString *text) {
    text = YTNicoLiveTrim(text);
    if (text.length == 0 || YTNicoLiveLooksLikeMetadata(text)) return @"";
    if (YTNicoLiveHasHandle(text)) return YTNicoLiveStripHandle(text);
    if (YTNicoLiveIsShortReaction(text)) return text;

    NSArray<NSString *> *patterns = @[
        @"^.{1,40}[：:、,\\n]+(.{1,220})$",
        @"^[^\\s　]{1,32}[\\s　]+(.{1,220})$"
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (m && m.numberOfRanges >= 2) {
            NSString *body = YTNicoLiveTrim([text substringWithRange:[m rangeAtIndex:1]]);
            if (body.length > 0 && !YTNicoLiveLooksLikeMetadata(body)) return body;
        }
    }
    return @"";
}

static void YTNicoLiveAddItem(NSMutableArray<YTNicoLiveTextItem *> *out, NSString *rawText, CGRect rect, BOOL includeHeader) {
    NSString *text = YTNicoLiveTrim(rawText);
    if (text.length == 0 || CGRectIsEmpty(rect)) return;
    if (!includeHeader && YTNicoLiveIsHeader(text)) return;
    [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(rect)), @"y": @(CGRectGetMidY(rect)), @"h": @(CGRectGetHeight(rect)), @"w": @(CGRectGetWidth(rect))}];
}

static void YTNicoLiveCollectAccessibility(id object, UIView *fallbackView, NSMutableArray<YTNicoLiveTextItem *> *out, BOOL includeHeader) {
    if (!object || out.count > 520) return;
    CGRect fallback = YTNicoLiveRectInWindow(fallbackView);
    if ([object isKindOfClass:NSString.class]) { YTNicoLiveAddItem(out, object, fallback, includeHeader); return; }
    if ([object isKindOfClass:NSAttributedString.class]) { YTNicoLiveAddItem(out, [(NSAttributedString *)object string], fallback, includeHeader); return; }
    CGRect rect = fallback;
    if ([object isKindOfClass:UIView.class]) rect = YTNicoLiveRectInWindow((UIView *)object);
    else if ([object respondsToSelector:@selector(accessibilityFrame)]) {
        CGRect ax = [object accessibilityFrame];
        if (!CGRectIsEmpty(ax)) rect = ax;
    }
    if ([object respondsToSelector:@selector(accessibilityLabel)]) YTNicoLiveAddItem(out, [object accessibilityLabel] ?: @"", rect, includeHeader);
    if ([object respondsToSelector:@selector(accessibilityValue)]) YTNicoLiveAddItem(out, [object accessibilityValue] ?: @"", rect, includeHeader);
}

static void YTNicoLiveCollectText(UIView *view, NSMutableArray<YTNicoLiveTextItem *> *out, BOOL includeHeader) {
    if (!view || view.hidden || view.alpha < 0.02 || out.count > 520) return;
    CGRect rect = YTNicoLiveRectInWindow(view);
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        YTNicoLiveAddItem(out, label.text ?: label.attributedText.string ?: @"", rect, includeHeader);
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        YTNicoLiveAddItem(out, button.currentTitle ?: button.titleLabel.text ?: button.currentAttributedTitle.string ?: @"", rect, includeHeader);
    } else if ([view isKindOfClass:UITextView.class]) {
        YTNicoLiveAddItem(out, [(UITextView *)view text] ?: @"", rect, includeHeader);
    }
    YTNicoLiveAddItem(out, view.accessibilityLabel ?: @"", rect, includeHeader);
    YTNicoLiveAddItem(out, view.accessibilityValue ?: @"", rect, includeHeader);
    NSArray *elements = view.accessibilityElements;
    if ([elements isKindOfClass:NSArray.class]) for (id e in elements) YTNicoLiveCollectAccessibility(e, view, out, includeHeader);
    for (UIView *sub in view.subviews) YTNicoLiveCollectText(sub, out, includeHeader);
}

static CGFloat YTNicoLivePanelTop(UIWindow *win, NSArray<YTNicoLiveTextItem *> *items, BOOL *isLiveChat) {
    CGRect wb = win.bounds;
    CGFloat header = 0;
    *isLiveChat = NO;
    for (YTNicoLiveTextItem *item in items) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoLiveIsHeader(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y > wb.size.height * 0.16) header = MAX(header, y + h / 2.0);
        if ([text rangeOfString:@"ライブチャット"].location != NSNotFound || [text rangeOfString:@"上位"].location != NSNotFound || [text rangeOfString:@"すべて"].location != NSNotFound) *isLiveChat = YES;
    }
    if (header > 0) return header;

    CGFloat firstChatY = CGFLOAT_MAX;
    NSUInteger count = 0;
    for (YTNicoLiveTextItem *item in items) {
        NSString *text = YTNicoLiveTrim(item[@"text"] ?: @"");
        CGFloat y = [item[@"y"] doubleValue];
        if (y < wb.size.height * 0.30) continue;
        if (YTNicoLiveHasHandle(text) || (!YTNicoLiveLooksLikeMetadata(text) && text.length >= 2 && text.length <= 160)) {
            count++;
            firstChatY = MIN(firstChatY, y);
        }
    }
    if (count >= 3 && firstChatY < CGFLOAT_MAX) return MAX(wb.size.height * 0.24, firstChatY - 34.0);
    return wb.size.height * 0.34;
}

static NSString *YTNicoLiveBodyFromRow(NSArray<YTNicoLiveTextItem *> *row, BOOL liveMode) {
    NSArray *sorted = [row sortedArrayUsingComparator:^NSComparisonResult(YTNicoLiveTextItem *a, YTNicoLiveTextItem *b) {
        CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 9.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue], bx = [b[@"x"] doubleValue];
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    BOOL hasAuthor = NO;

    for (NSUInteger i = 0; i < sorted.count; i++) {
        NSString *t = YTNicoLiveTrim(sorted[i][@"text"] ?: @"");
        if (t.length == 0 || [seen containsObject:t] || YTNicoLiveLooksLikeMetadata(t)) continue;
        [seen addObject:t];

        if (YTNicoLiveHasHandle(t)) {
            hasAuthor = YES;
            NSString *body = YTNicoLiveStripHandle(t);
            if (body.length > 0 && !YTNicoLiveLooksLikeMetadata(body)) [parts addObject:body];
            continue;
        }

        NSString *single = YTNicoLiveBodyFromSingleText(t);
        if (single.length > 0 && ![single isEqualToString:t]) {
            hasAuthor = YES;
            [parts addObject:single];
            continue;
        }

        if (i == 0 && sorted.count > 1 && YTNicoLiveLooksLikeAuthorOnly(t)) {
            hasAuthor = YES;
            continue;
        }

        if (liveMode || hasAuthor || sorted.count > 1 || YTNicoLiveIsShortReaction(t)) [parts addObject:t];
    }

    NSString *body = YTNicoLiveTrim([parts componentsJoinedByString:@" "]);
    if (body.length == 0 || YTNicoLiveLooksLikeMetadata(body)) return @"";
    if (!liveMode && !hasAuthor) return @"";
    return body;
}

static void YTNicoLivePruneSeen(void) {
    if (!gYTNicoLiveScanSeen) gYTNicoLiveScanSeen = [NSMutableDictionary dictionary];
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *k in gYTNicoLiveScanSeen) if (now - gYTNicoLiveScanSeen[k].doubleValue > 90.0) [remove addObject:k];
    [gYTNicoLiveScanSeen removeObjectsForKeys:remove];
}

static void YTNicoLiveEmit(NSString *body, NSString *key) {
    body = YTNicoLiveTrim(body);
    if (body.length == 0 || YTNicoLiveLooksLikeMetadata(body)) return;
    if (!gYTNicoLiveScanSeen) gYTNicoLiveScanSeen = [NSMutableDictionary dictionary];
    YTNicoLivePruneSeen();
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"live-ui", body];
    if (gYTNicoLiveScanSeen[seenKey]) return;
    gYTNicoLiveScanSeen[seenKey] = @(CACurrentMediaTime());
    NSString *mid = [NSString stringWithFormat:@"liveui-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
}

static void YTNicoLiveScanOnce(void) {
    if (gYTNicoLiveScanRunning || !YTNicoLiveIsYouTube() || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !SettingsManager.shared.enabled) return;
    gYTNicoLiveScanRunning = YES;
    @try {
        for (UIWindow *win in UIApplication.sharedApplication.windows) {
            if (!win || win.hidden || win.alpha < 0.02) continue;
            NSMutableArray<YTNicoLiveTextItem *> *all = [NSMutableArray array];
            YTNicoLiveCollectText(win, all, YES);
            if (all.count == 0) continue;
            BOOL liveMode = NO;
            CGFloat panelTop = YTNicoLivePanelTop(win, all, &liveMode);
            CGRect wb = win.bounds;

            NSMutableArray<YTNicoLiveTextItem *> *anchors = [NSMutableArray array];
            for (YTNicoLiveTextItem *item in all) {
                NSString *text = YTNicoLiveTrim(item[@"text"] ?: @"");
                CGFloat y = [item[@"y"] doubleValue];
                CGFloat x = [item[@"x"] doubleValue];
                if (y < panelTop || y > wb.size.height - 8.0 || x < -30.0 || x > wb.size.width + 30.0) continue;
                if (YTNicoLiveLooksLikeMetadata(text)) continue;
                if (YTNicoLiveHasHandle(text) || liveMode || YTNicoLiveBodyFromSingleText(text).length > 0) [anchors addObject:item];
            }
            NSArray *sortedAnchors = [anchors sortedArrayUsingComparator:^NSComparisonResult(YTNicoLiveTextItem *a, YTNicoLiveTextItem *b) {
                CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
                return ay < by ? NSOrderedAscending : (ay > by ? NSOrderedDescending : NSOrderedSame);
            }];
            for (NSUInteger i = 0; i < sortedAnchors.count; i++) {
                YTNicoLiveTextItem *anchor = sortedAnchors[i];
                CGFloat ay = [anchor[@"y"] doubleValue];
                CGFloat ax = [anchor[@"x"] doubleValue];
                CGFloat prevY = (i > 0) ? [sortedAnchors[i - 1][@"y"] doubleValue] : panelTop;
                CGFloat nextY = (i + 1 < sortedAnchors.count) ? [sortedAnchors[i + 1][@"y"] doubleValue] : MIN(wb.size.height, ay + 58.0);
                CGFloat top = MAX(panelTop, (prevY + ay) / 2.0 - 4.0);
                CGFloat bottom = MIN(wb.size.height - 8.0, (ay + nextY) / 2.0 + 4.0);
                if (bottom - top < 34.0) bottom = MIN(wb.size.height - 8.0, top + 42.0);
                NSMutableArray *row = [NSMutableArray array];
                for (YTNicoLiveTextItem *item in all) {
                    CGFloat y = [item[@"y"] doubleValue];
                    CGFloat x = [item[@"x"] doubleValue];
                    NSString *text = item[@"text"] ?: @"";
                    if (y < top || y > bottom || x < ax - 24.0 || x > wb.size.width + 30.0) continue;
                    if (YTNicoLiveLooksLikeMetadata(text)) continue;
                    [row addObject:item];
                }
                NSString *body = YTNicoLiveBodyFromRow(row, liveMode);
                if (body.length == 0) continue;
                NSString *key = [NSString stringWithFormat:@"live-row-%lu-%lu", (unsigned long)[body hash], (unsigned long)round(ay / 24.0)];
                YTNicoLiveEmit(body, key);
            }
        }
    } @finally {
        gYTNicoLiveScanRunning = NO;
    }
}

static void YTNicoLiveStopWatch(void) {
    if (gYTNicoLiveScanTimer) {
        dispatch_source_cancel(gYTNicoLiveScanTimer);
        gYTNicoLiveScanTimer = nil;
    }
    gYTNicoLiveScanVideoId = nil;
    [gYTNicoLiveScanSeen removeAllObjects];
}

static void YTNicoLiveStartWatch(NSString *videoId) {
    if (!YTNicoLiveIsYouTube()) return;
    if (!gYTNicoLiveScanSeen) gYTNicoLiveScanSeen = [NSMutableDictionary dictionary];
    gYTNicoLiveScanVideoId = [videoId copy];
    YTNicoLiveStopWatch();
    gYTNicoLiveScanVideoId = [videoId copy];
    gYTNicoLiveScanTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!gYTNicoLiveScanTimer) return;
    uint64_t interval = (uint64_t)(0.90 * (double)NSEC_PER_SEC);
    uint64_t leeway = (uint64_t)(0.12 * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(gYTNicoLiveScanTimer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, leeway);
    dispatch_source_set_event_handler(gYTNicoLiveScanTimer, ^{
        if (!SettingsManager.shared.enabled || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        NSString *current = [YouTubeChatAdapter currentVideoId] ?: @"";
        if (gYTNicoLiveScanVideoId.length == 11 && current.length == 11 && ![current isEqualToString:gYTNicoLiveScanVideoId]) {
            YTNicoLiveStopWatch();
            [[DebugInspector shared] important:@"live chat UI watch stopped: video changed"];
            return;
        }
        YTNicoLiveScanOnce();
    });
    dispatch_resume(gYTNicoLiveScanTimer);
    [[DebugInspector shared] important:@"live chat UI watch started videoId=%@", gYTNicoLiveScanVideoId ?: @""];
}

%hook YTNicoController
- (void)toggleOverlayEnabled {
    %orig;
    NSString *videoId = [YouTubeChatAdapter currentVideoId] ?: @"";
    YTNicoLiveStartWatch(videoId.length == 11 ? videoId : nil);
}

- (void)clearOverlayForVideoChange {
    YTNicoLiveStopWatch();
    %orig;
}

- (void)reloadSettings {
    if (!SettingsManager.shared.enabled) YTNicoLiveStopWatch();
    %orig;
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoLiveIsYouTube()) return;
        gYTNicoLiveScanSeen = [NSMutableDictionary dictionary];
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"live chat continuous scanner loaded"];
    });
}

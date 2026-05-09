#import <UIKit/UIKit.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static BOOL gYTNicoManualScanRunning = NO;
static NSUInteger gYTNicoManualEmitCount = 0;
static CFTimeInterval gYTNicoManualLastLog = 0;
static NSTimer *gYTNicoManualWatchTimer = nil;
static NSString *gYTNicoManualWatchVideoId = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoManualSeen = nil;

typedef NSDictionary<NSString *, id> YTNicoTextItem;

static BOOL YTNicoManualIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoManualTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@"、 " withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@", " withString:@" "];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static CGRect YTNicoManualRectInWindow(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoManualContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([lower rangeOfString:needle.lowercaseString].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL YTNicoManualIsHeaderText(NSString *text) {
    text = YTNicoManualTrim(text);
    return [text rangeOfString:@"チャットのリプレイ"].location != NSNotFound ||
           [text rangeOfString:@"ライブチャット"].location != NSNotFound ||
           [text rangeOfString:@"上位のメッセージ"].location != NSNotFound ||
           [text rangeOfString:@"上位チャット"].location != NSNotFound ||
           [text rangeOfString:@"すべてのチャット"].location != NSNotFound;
}

static BOOL YTNicoManualHasHandleToken(NSString *text) {
    text = YTNicoManualTrim(text);
    if (text.length == 0) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(^|[\\s　])[@＠][^\\s　:：,，、]{2,}" options:0 error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoManualIsHandleOnly(NSString *text) {
    text = YTNicoManualTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return NO;
    if (text.length > 96) return NO;
    if ([text rangeOfString:@"。"].location != NSNotFound ||
        [text rangeOfString:@"！"].location != NSNotFound ||
        [text rangeOfString:@"？"].location != NSNotFound ||
        [text rangeOfString:@"w" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [text rangeOfString:@"ｗ"].location != NSNotFound) return NO;
    return YES;
}

static BOOL YTNicoManualIsShortReaction(NSString *text) {
    text = YTNicoManualTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w+|ｗ+|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoManualLooksLikeMetadata(NSString *text) {
    text = YTNicoManualTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoManualIsShortReaction(text)) return NO;
    if (YTNicoManualIsHeaderText(text)) return YES;
    if ([text rangeOfString:@"回視聴"].location != NSNotFound) return YES;
    if ([text rangeOfString:@"人が視聴中"].location != NSNotFound) return YES;

    NSArray *exact = @[
        @"返信", @"共有", @"保存", @"チャンネル登録", @"高評価", @"低評価", @"ライブチャット", @"チャット",
        @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え",
        @"キャンセル", @"送信", @"検索", @"設定", @"閉じる", @"フィルタ", @"その他"
    ];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;

    NSArray *contains = @[
        @"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium",
        @"チャット欄を開いてから", @"操作メニュー", @"に移動します", @"コメントを見る", @"この動画のライブ配信時"
    ];
    if (YTNicoManualContainsAny(text, contains)) return YES;

    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    return NO;
}

static NSString *YTNicoManualStripHandlePrefix(NSString *text) {
    text = YTNicoManualTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *withSep = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：,，、]+[\\s　:：,，、-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [withSep firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoManualTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return @"";
}

static void YTNicoManualAddItem(NSMutableArray<YTNicoTextItem *> *out, NSString *rawText, CGRect rect, BOOL includeHeader) {
    NSString *text = YTNicoManualTrim(rawText);
    if (text.length == 0 || CGRectIsEmpty(rect)) return;
    if (!includeHeader && YTNicoManualIsHeaderText(text)) return;
    [out addObject:@{@"text": text,
                     @"x": @(CGRectGetMinX(rect)),
                     @"y": @(CGRectGetMidY(rect)),
                     @"h": @(CGRectGetHeight(rect)),
                     @"w": @(CGRectGetWidth(rect))}];
}

static void YTNicoManualCollectAccessibilityElements(id object, UIView *fallbackView, NSMutableArray<YTNicoTextItem *> *out, BOOL includeHeader) {
    if (!object || out.count > 420) return;

    CGRect fallbackRect = YTNicoManualRectInWindow(fallbackView);
    if ([object isKindOfClass:NSString.class]) {
        YTNicoManualAddItem(out, (NSString *)object, fallbackRect, includeHeader);
        return;
    }
    if ([object isKindOfClass:NSAttributedString.class]) {
        YTNicoManualAddItem(out, [(NSAttributedString *)object string], fallbackRect, includeHeader);
        return;
    }
    if ([object isKindOfClass:UIView.class]) {
        UIView *view = (UIView *)object;
        CGRect rect = YTNicoManualRectInWindow(view);
        YTNicoManualAddItem(out, view.accessibilityLabel ?: @"", rect, includeHeader);
        YTNicoManualAddItem(out, view.accessibilityValue ?: @"", rect, includeHeader);
        return;
    }

    CGRect rect = fallbackRect;
    if ([object respondsToSelector:@selector(accessibilityFrame)]) {
        CGRect axRect = [object accessibilityFrame];
        if (!CGRectIsEmpty(axRect)) rect = axRect;
    }
    if ([object respondsToSelector:@selector(accessibilityLabel)]) YTNicoManualAddItem(out, [object accessibilityLabel] ?: @"", rect, includeHeader);
    if ([object respondsToSelector:@selector(accessibilityValue)]) YTNicoManualAddItem(out, [object accessibilityValue] ?: @"", rect, includeHeader);
}

static void YTNicoManualCollectTextItems(UIView *view, NSMutableArray<YTNicoTextItem *> *out, BOOL includeHeader) {
    if (!view || view.hidden || view.alpha < 0.02 || out.count > 420) return;

    CGRect rect = YTNicoManualRectInWindow(view);
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        YTNicoManualAddItem(out, label.text ?: label.attributedText.string ?: @"", rect, includeHeader);
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        YTNicoManualAddItem(out, button.currentTitle ?: button.titleLabel.text ?: button.currentAttributedTitle.string ?: @"", rect, includeHeader);
    } else if ([view isKindOfClass:UITextView.class]) {
        YTNicoManualAddItem(out, [(UITextView *)view text] ?: @"", rect, includeHeader);
    }

    YTNicoManualAddItem(out, view.accessibilityLabel ?: @"", rect, includeHeader);
    YTNicoManualAddItem(out, view.accessibilityValue ?: @"", rect, includeHeader);

    NSArray *elements = view.accessibilityElements;
    if ([elements isKindOfClass:NSArray.class]) {
        for (id element in elements) YTNicoManualCollectAccessibilityElements(element, view, out, includeHeader);
    }

    for (UIView *sub in view.subviews) YTNicoManualCollectTextItems(sub, out, includeHeader);
}

static CGFloat YTNicoManualInferPanelTop(UIWindow *win, NSArray<YTNicoTextItem *> *items) {
    CGRect wb = win.bounds;
    CGFloat headerBottom = 0.0;
    for (YTNicoTextItem *item in items) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoManualIsHeaderText(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y > wb.size.height * 0.16) headerBottom = MAX(headerBottom, y + h / 2.0);
    }
    if (headerBottom > 0) return headerBottom;

    CGFloat firstHandleY = CGFLOAT_MAX;
    NSUInteger handleCount = 0;
    for (YTNicoTextItem *item in items) {
        NSString *text = YTNicoManualTrim(item[@"text"] ?: @"");
        CGFloat y = [item[@"y"] doubleValue];
        if (y < wb.size.height * 0.30) continue;
        if (YTNicoManualHasHandleToken(text)) {
            handleCount++;
            firstHandleY = MIN(firstHandleY, y);
        }
    }
    if (handleCount >= 2 && firstHandleY < CGFLOAT_MAX) return MAX(wb.size.height * 0.24, firstHandleY - 34.0);

    return wb.size.height * 0.34;
}

static NSString *YTNicoManualBodyFromChatRow(NSArray<YTNicoTextItem *> *rowItems) {
    NSArray<YTNicoTextItem *> *sorted = [rowItems sortedArrayUsingComparator:^NSComparisonResult(YTNicoTextItem *a, YTNicoTextItem *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 9.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue];
        CGFloat bx = [b[@"x"] doubleValue];
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    BOOL hasHandle = NO;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (YTNicoTextItem *item in sorted) {
        NSString *t = YTNicoManualTrim(item[@"text"] ?: @"");
        if (t.length == 0 || [seen containsObject:t]) continue;
        [seen addObject:t];
        if (YTNicoManualLooksLikeMetadata(t)) continue;

        if (YTNicoManualHasHandleToken(t)) {
            hasHandle = YES;
            NSString *body = YTNicoManualStripHandlePrefix(t);
            if (body.length > 0 && !YTNicoManualLooksLikeMetadata(body)) [parts addObject:body];
            continue;
        }

        if (YTNicoManualIsHandleOnly(t)) {
            hasHandle = YES;
            continue;
        }

        if (!YTNicoManualLooksLikeMetadata(t)) [parts addObject:t];
    }

    if (!hasHandle) return @"";
    return YTNicoManualTrim([parts componentsJoinedByString:@" "]);
}

static NSString *YTNicoManualFingerprintForRow(NSArray<YTNicoTextItem *> *rowItems, NSString *body) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (YTNicoTextItem *item in rowItems) {
        NSString *text = YTNicoManualTrim(item[@"text"] ?: @"");
        if (text.length > 0) [parts addObject:text];
    }
    NSString *joined = [parts componentsJoinedByString:@"|"] ?: @"";
    if (joined.length == 0) joined = body ?: @"";
    return joined;
}

static void YTNicoManualPruneSeen(void) {
    if (!gYTNicoManualSeen) gYTNicoManualSeen = [NSMutableDictionary dictionary];
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *key in gYTNicoManualSeen) {
        if (now - gYTNicoManualSeen[key].doubleValue > 90.0) [remove addObject:key];
    }
    [gYTNicoManualSeen removeObjectsForKeys:remove];
}

static void YTNicoManualEmit(NSString *body, NSString *key, NSMutableSet<NSString *> *emitted) {
    body = YTNicoManualTrim(body);
    if (body.length == 0 || YTNicoManualLooksLikeMetadata(body)) return;
    if (!gYTNicoManualSeen) gYTNicoManualSeen = [NSMutableDictionary dictionary];
    YTNicoManualPruneSeen();

    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"manual", body];
    if ([emitted containsObject:seenKey] || gYTNicoManualSeen[seenKey]) return;
    [emitted addObject:seenKey];
    gYTNicoManualSeen[seenKey] = @(CACurrentMediaTime());

    NSString *mid = [NSString stringWithFormat:@"manualui-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
    gYTNicoManualEmitCount++;

    CFTimeInterval now = CACurrentMediaTime();
    if (SettingsManager.shared.debugLogging && now - gYTNicoManualLastLog > 1.0) {
        gYTNicoManualLastLog = now;
        [[DebugInspector shared] important:@"manual chat scan emitted %@", body];
    }
}

static void YTNicoManualScanWindow(UIWindow *win, NSMutableSet<NSString *> *emitted) {
    if (!win || win.hidden || win.alpha < 0.02) return;

    NSMutableArray<YTNicoTextItem *> *all = [NSMutableArray array];
    YTNicoManualCollectTextItems(win, all, YES);
    if (all.count == 0) return;

    CGRect wb = win.bounds;
    CGFloat panelTop = YTNicoManualInferPanelTop(win, all);

    NSMutableArray<YTNicoTextItem *> *handles = [NSMutableArray array];
    for (YTNicoTextItem *item in all) {
        NSString *text = YTNicoManualTrim(item[@"text"] ?: @"");
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat x = [item[@"x"] doubleValue];
        if (y < panelTop || y > wb.size.height - 8.0) continue;
        if (x < -30.0 || x > wb.size.width + 30.0) continue;
        if (YTNicoManualHasHandleToken(text)) [handles addObject:item];
    }

    NSArray<YTNicoTextItem *> *sortedHandles = [handles sortedArrayUsingComparator:^NSComparisonResult(YTNicoTextItem *a, YTNicoTextItem *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (ay < by) return NSOrderedAscending;
        if (ay > by) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    for (NSUInteger i = 0; i < sortedHandles.count; i++) {
        YTNicoTextItem *handleItem = sortedHandles[i];
        CGFloat hy = [handleItem[@"y"] doubleValue];
        CGFloat hx = [handleItem[@"x"] doubleValue];
        CGFloat prevY = (i > 0) ? [sortedHandles[i - 1][@"y"] doubleValue] : panelTop;
        CGFloat nextY = (i + 1 < sortedHandles.count) ? [sortedHandles[i + 1][@"y"] doubleValue] : MIN(wb.size.height, hy + 58.0);
        CGFloat top = MAX(panelTop, (prevY + hy) / 2.0 - 4.0);
        CGFloat bottom = MIN(wb.size.height - 8.0, (hy + nextY) / 2.0 + 4.0);
        if (bottom - top < 34.0) bottom = MIN(wb.size.height - 8.0, top + 42.0);

        NSMutableArray<YTNicoTextItem *> *row = [NSMutableArray array];
        for (YTNicoTextItem *item in all) {
            CGFloat y = [item[@"y"] doubleValue];
            CGFloat x = [item[@"x"] doubleValue];
            NSString *text = item[@"text"] ?: @"";
            if (y < top || y > bottom) continue;
            if (x < hx - 18.0 || x > wb.size.width + 30.0) continue;
            if (YTNicoManualLooksLikeMetadata(text)) continue;
            [row addObject:item];
        }
        NSString *body = YTNicoManualBodyFromChatRow(row);
        if (body.length == 0) continue;
        NSString *fingerprint = YTNicoManualFingerprintForRow(row, body);
        NSString *key = [NSString stringWithFormat:@"manual-row-%lu-%lu", (unsigned long)[fingerprint hash], (unsigned long)round(hy / 24.0)];
        YTNicoManualEmit(body, key, emitted);
    }
}

static NSUInteger YTNicoManualScanVisibleChatPanelInternal(void) {
    if (![NSThread isMainThread]) {
        __block NSUInteger count = 0;
        dispatch_sync(dispatch_get_main_queue(), ^{ count = YTNicoManualScanVisibleChatPanelInternal(); });
        return count;
    }
    if (gYTNicoManualScanRunning) return 0;
    if (!YTNicoManualIsYouTube()) return 0;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return 0;
    if (!SettingsManager.shared.enabled) return 0;

    gYTNicoManualScanRunning = YES;
    gYTNicoManualEmitCount = 0;
    NSMutableSet<NSString *> *emitted = [NSMutableSet set];
    @try {
        for (UIWindow *win in UIApplication.sharedApplication.windows) YTNicoManualScanWindow(win, emitted);
    } @finally {
        gYTNicoManualScanRunning = NO;
    }
    return gYTNicoManualEmitCount;
}

static void YTNicoManualWatchTick(void) {
    if (!SettingsManager.shared.enabled || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        return;
    }
    NSString *currentVideoId = [YouTubeChatAdapter currentVideoId] ?: @"";
    if (gYTNicoManualWatchVideoId.length == 11 && currentVideoId.length == 11 && ![currentVideoId isEqualToString:gYTNicoManualWatchVideoId]) {
        if (gYTNicoManualWatchTimer) {
            [gYTNicoManualWatchTimer invalidate];
            gYTNicoManualWatchTimer = nil;
        }
        gYTNicoManualWatchVideoId = nil;
        [gYTNicoManualSeen removeAllObjects];
        [[DebugInspector shared] important:@"manual chat watch stopped: video changed"];
        return;
    }
    YTNicoManualScanVisibleChatPanelInternal();
}

extern "C" NSUInteger YTNicoManualScanVisibleChatPanel(void) {
    return YTNicoManualScanVisibleChatPanelInternal();
}

extern "C" void YTNicoStartManualChatPanelWatch(NSString *videoId) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ YTNicoStartManualChatPanelWatch(videoId); });
        return;
    }
    if (!YTNicoManualIsYouTube()) return;
    if (!gYTNicoManualSeen) gYTNicoManualSeen = [NSMutableDictionary dictionary];
    [gYTNicoManualSeen removeAllObjects];
    gYTNicoManualWatchVideoId = [videoId copy];
    if (gYTNicoManualWatchTimer) [gYTNicoManualWatchTimer invalidate];
    gYTNicoManualWatchTimer = [NSTimer scheduledTimerWithTimeInterval:0.90 repeats:YES block:^(__unused NSTimer *timer) {
        YTNicoManualWatchTick();
    }];
    [[NSRunLoop mainRunLoop] addTimer:gYTNicoManualWatchTimer forMode:NSDefaultRunLoopMode];
    [[DebugInspector shared] important:@"manual chat watch started videoId=%@", gYTNicoManualWatchVideoId ?: @""];
}

extern "C" void YTNicoStopManualChatPanelWatch(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ YTNicoStopManualChatPanelWatch(); });
        return;
    }
    if (gYTNicoManualWatchTimer) {
        [gYTNicoManualWatchTimer invalidate];
        gYTNicoManualWatchTimer = nil;
    }
    gYTNicoManualWatchVideoId = nil;
    [gYTNicoManualSeen removeAllObjects];
    [[DebugInspector shared] important:@"manual chat watch stopped"];
}

extern "C" BOOL YTNicoManualChatPanelWatchIsActive(void) {
    return gYTNicoManualWatchTimer != nil;
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoManualIsYouTube()) return;
        gYTNicoManualSeen = [NSMutableDictionary dictionary];
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"manual chat scanner loaded watch mode"];
    });
}

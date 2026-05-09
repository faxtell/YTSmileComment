#import <UIKit/UIKit.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static BOOL gYTNicoManualScanRunning = NO;
static NSUInteger gYTNicoManualEmitCount = 0;
static CFTimeInterval gYTNicoManualLastLog = 0;

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

    NSArray *contains = @[@"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium", @"チャット欄を開いてから"];
    if (YTNicoManualContainsAny(text, contains)) return YES;

    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;

    return NO;
}

static BOOL YTNicoManualLooksLikeHandle(NSString *text) {
    text = YTNicoManualTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return NO;
    if (text.length > 96) return NO;
    if ([text rangeOfString:@"。"].location != NSNotFound || [text rangeOfString:@"！"].location != NSNotFound || [text rangeOfString:@"？"].location != NSNotFound) return NO;
    return YES;
}

static NSString *YTNicoManualStripSeparatedHandle(NSString *text) {
    text = YTNicoManualTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *withSep = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：,，、]+[\\s　:：,，、-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [withSep firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoManualTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return text;
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

    if ([object isKindOfClass:NSString.class]) {
        YTNicoManualAddItem(out, (NSString *)object, YTNicoManualRectInWindow(fallbackView), includeHeader);
        return;
    }
    if ([object isKindOfClass:NSAttributedString.class]) {
        YTNicoManualAddItem(out, [(NSAttributedString *)object string], YTNicoManualRectInWindow(fallbackView), includeHeader);
        return;
    }
    if ([object isKindOfClass:UIView.class]) {
        // UIView accessibility containers may not be normal subviews of the text node, so
        // still read their label/value here, but do not recurse to avoid double-heavy scans.
        UIView *view = (UIView *)object;
        NSString *label = YTNicoManualTrim(view.accessibilityLabel ?: @"");
        if (label.length > 0) YTNicoManualAddItem(out, label, YTNicoManualRectInWindow(view), includeHeader);
        NSString *value = YTNicoManualTrim(view.accessibilityValue ?: @"");
        if (value.length > 0) YTNicoManualAddItem(out, value, YTNicoManualRectInWindow(view), includeHeader);
        return;
    }

    if ([object respondsToSelector:@selector(accessibilityLabel)]) {
        NSString *label = YTNicoManualTrim([object accessibilityLabel] ?: @"");
        if (label.length > 0) {
            CGRect rect = CGRectZero;
            if ([object respondsToSelector:@selector(accessibilityFrame)]) rect = [object accessibilityFrame];
            if (CGRectIsEmpty(rect)) rect = YTNicoManualRectInWindow(fallbackView);
            YTNicoManualAddItem(out, label, rect, includeHeader);
        }
    }
    if ([object respondsToSelector:@selector(accessibilityValue)]) {
        NSString *value = YTNicoManualTrim([object accessibilityValue] ?: @"");
        if (value.length > 0) {
            CGRect rect = CGRectZero;
            if ([object respondsToSelector:@selector(accessibilityFrame)]) rect = [object accessibilityFrame];
            if (CGRectIsEmpty(rect)) rect = YTNicoManualRectInWindow(fallbackView);
            YTNicoManualAddItem(out, value, rect, includeHeader);
        }
    }
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

    NSString *axLabel = YTNicoManualTrim(view.accessibilityLabel ?: @"");
    if (axLabel.length > 0) YTNicoManualAddItem(out, axLabel, rect, includeHeader);
    NSString *axValue = YTNicoManualTrim(view.accessibilityValue ?: @"");
    if (axValue.length > 0) YTNicoManualAddItem(out, axValue, rect, includeHeader);

    NSArray *elements = view.accessibilityElements;
    if ([elements isKindOfClass:NSArray.class]) {
        for (id element in elements) YTNicoManualCollectAccessibilityElements(element, view, out, includeHeader);
    }

    for (UIView *sub in view.subviews) YTNicoManualCollectTextItems(sub, out, includeHeader);
}

static BOOL YTNicoManualColorLooksLight(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) return a > 0.18 && ((r + g + b) / 3.0) > 0.72;
    CGFloat white = 0;
    if ([color getWhite:&white alpha:&a]) return a > 0.18 && white > 0.72;
    return NO;
}

static void YTNicoManualFindSheetCandidate(UIView *view, CGRect winBounds, CGFloat *bestTop, CGFloat *bestScore) {
    if (!view || view.hidden || view.alpha < 0.02 || !view.window) return;
    CGRect r = YTNicoManualRectInWindow(view);
    if (!CGRectIsEmpty(r)) {
        BOOL lower = CGRectGetMinY(r) > winBounds.size.height * 0.22;
        BOOL large = r.size.width > winBounds.size.width * 0.72 && r.size.height > winBounds.size.height * 0.22;
        BOOL notWholeWindow = r.size.height < winBounds.size.height * 0.88;
        NSString *cls = NSStringFromClass(view.class).lowercaseString ?: @"";
        BOOL classHint = YTNicoManualContainsAny(cls, @[@"sheet", @"panel", @"drawer", @"presentation", @"bottom", @"detent"]);
        BOOL rounded = view.layer.cornerRadius >= 10.0;
        BOOL light = YTNicoManualColorLooksLight(view.backgroundColor);
        if (lower && large && notWholeWindow && (light || rounded || classHint)) {
            CGFloat score = (r.size.width / MAX(winBounds.size.width, 1.0)) * 90.0 +
                            (r.size.height / MAX(winBounds.size.height, 1.0)) * 40.0 +
                            (rounded ? 30.0 : 0.0) + (light ? 20.0 : 0.0) + (classHint ? 16.0 : 0.0) -
                            fabs(CGRectGetMinY(r) - winBounds.size.height * 0.36) * 0.05;
            if (score > *bestScore) {
                *bestScore = score;
                *bestTop = CGRectGetMinY(r);
            }
        }
    }
    for (UIView *sub in view.subviews) YTNicoManualFindSheetCandidate(sub, winBounds, bestTop, bestScore);
}

static CGFloat YTNicoManualFindHeaderBottom(UIWindow *win, NSArray<YTNicoTextItem *> *items) {
    CGRect wb = win.bounds;
    CGFloat headerBottom = 0.0;

    for (YTNicoTextItem *item in items) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoManualIsHeaderText(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y < wb.size.height * 0.18) continue;
        headerBottom = MAX(headerBottom, y + h / 2.0);
    }
    if (headerBottom > 0) return headerBottom;

    // Header may be drawn by Texture/AsyncDisplayKit without an accessible text node.
    // If we can see multiple @handle rows in the lower half, infer the chat list start.
    CGFloat firstHandleY = CGFLOAT_MAX;
    NSUInteger handleCount = 0;
    for (YTNicoTextItem *item in items) {
        NSString *text = YTNicoManualTrim(item[@"text"] ?: @"");
        CGFloat y = [item[@"y"] doubleValue];
        if (y < wb.size.height * 0.38) continue;
        if ([text hasPrefix:@"@"] || [text hasPrefix:@"＠"] || [text rangeOfString:@" @"].location != NSNotFound) {
            handleCount++;
            firstHandleY = MIN(firstHandleY, y);
        }
    }
    if (handleCount >= 3 && firstHandleY < CGFLOAT_MAX) return MAX(wb.size.height * 0.28, firstHandleY - 22.0);

    // Last resort: infer the bottom sheet itself. This avoids showing the generic
    // "open chat" toast when the sheet is visibly open but its header is not accessible.
    CGFloat sheetTop = 0.0;
    CGFloat sheetScore = -CGFLOAT_MAX;
    YTNicoManualFindSheetCandidate(win, wb, &sheetTop, &sheetScore);
    if (sheetTop > 0) {
        CGFloat offset = MIN(MAX(wb.size.height * 0.075, 112.0), 164.0);
        return sheetTop + offset;
    }

    return 0.0;
}

static NSString *YTNicoManualBodyFromItems(NSArray<YTNicoTextItem *> *items) {
    NSArray<YTNicoTextItem *> *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(YTNicoTextItem *a, YTNicoTextItem *b) {
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
    for (YTNicoTextItem *item in sorted) {
        NSString *t = YTNicoManualTrim(item[@"text"] ?: @"");
        if (t.length == 0 || [seen containsObject:t]) continue;
        [seen addObject:t];
        if (YTNicoManualLooksLikeMetadata(t)) continue;
        if (YTNicoManualLooksLikeHandle(t) && sorted.count > 1) continue;
        NSString *body = YTNicoManualStripSeparatedHandle(t);
        if (body.length > 0 && !YTNicoManualLooksLikeMetadata(body)) [parts addObject:body];
    }
    return YTNicoManualTrim([parts componentsJoinedByString:@" "]);
}

static void YTNicoManualEmit(NSString *body, NSString *key, NSMutableSet<NSString *> *emitted) {
    body = YTNicoManualTrim(body);
    if (body.length == 0 || YTNicoManualLooksLikeMetadata(body)) return;
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"manual", body];
    if ([emitted containsObject:seenKey]) return;
    [emitted addObject:seenKey];
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
    CGFloat headerBottom = YTNicoManualFindHeaderBottom(win, all);
    if (headerBottom <= 0) return;

    NSMutableDictionary<NSNumber *, NSMutableArray<YTNicoTextItem *> *> *rows = [NSMutableDictionary dictionary];
    for (YTNicoTextItem *item in all) {
        NSString *text = item[@"text"] ?: @"";
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat x = [item[@"x"] doubleValue];
        if (y <= headerBottom + 8.0) continue;
        if (y > wb.size.height - 8.0) continue;
        if (x < -30.0 || x > wb.size.width + 30.0) continue;
        if (YTNicoManualLooksLikeMetadata(text)) continue;
        NSNumber *bucket = @((NSInteger)round(y / 28.0));
        NSMutableArray *arr = rows[bucket];
        if (!arr) {
            arr = [NSMutableArray array];
            rows[bucket] = arr;
        }
        [arr addObject:item];
    }

    for (NSNumber *bucket in rows) {
        NSString *body = YTNicoManualBodyFromItems(rows[bucket]);
        if (body.length == 0) continue;
        NSString *key = [NSString stringWithFormat:@"manual-%ld", (long)bucket.integerValue];
        YTNicoManualEmit(body, key, emitted);
    }
}

extern "C" NSUInteger YTNicoManualScanVisibleChatPanel(void) {
    if (![NSThread isMainThread]) {
        __block NSUInteger count = 0;
        dispatch_sync(dispatch_get_main_queue(), ^{ count = YTNicoManualScanVisibleChatPanel(); });
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

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoManualIsYouTube()) return;
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"manual chat scanner loaded header-inference mode"];
    });
}

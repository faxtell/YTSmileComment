#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoManualSeen = nil;
static CFTimeInterval gYTNicoManualLastLog = 0;
static CGFloat gYTNicoManualHeaderBottomY = 0;
static CFTimeInterval gYTNicoManualHeaderSeenAt = 0;
static BOOL gYTNicoManualScanRunning = NO;
static NSUInteger gYTNicoManualEmitCount = 0;

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

static CGRect YTNicoManualWindowRect(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoManualContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *n in needles) if ([lower rangeOfString:n.lowercaseString].location != NSNotFound) return YES;
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
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w{1,}|ｗ{1,}|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoManualLooksLikeMetadata(NSString *text) {
    text = YTNicoManualTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoManualIsShortReaction(text)) return NO;
    if ([text rangeOfString:@"回視聴"].location != NSNotFound) return YES;
    if ([text rangeOfString:@"人が視聴中"].location != NSNotFound) return YES;
    NSArray *exact = @[@"返信", @"共有", @"保存", @"チャンネル登録", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定", @"閉じる", @"フィルタ", @"その他"];
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
    if (text.length > 84) return NO;
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

static void YTNicoManualAddTextItem(NSMutableArray<NSDictionary *> *out, NSString *rawText, UIView *sourceView, BOOL includeHeader) {
    NSString *text = YTNicoManualTrim(rawText);
    if (text.length == 0 || !sourceView.window) return;
    if (!includeHeader && YTNicoManualIsHeaderText(text)) return;
    CGRect r = YTNicoManualWindowRect(sourceView);
    if (CGRectIsEmpty(r)) return;
    [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(r)), @"y": @(CGRectGetMidY(r)), @"h": @(CGRectGetHeight(r)), @"w": @(CGRectGetWidth(r))}];
}

static void YTNicoManualCollectLabels(UIView *view, NSMutableArray<NSDictionary *> *out, BOOL includeHeader) {
    if (!view || view.hidden || view.alpha < 0.02 || !view.window) return;
    if (out.count > 320) return;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        YTNicoManualAddTextItem(out, label.text ?: label.attributedText.string ?: @"", label, includeHeader);
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        YTNicoManualAddTextItem(out, button.currentTitle ?: button.titleLabel.text ?: button.currentAttributedTitle.string ?: @"", button, includeHeader);
    }

    // YouTube often renders chat replay rows with AsyncDisplayKit views. In that case
    // the visible text is not a UILabel, but the row/accessibility container still has
    // accessibilityLabel. Read it only on manual scan so it does not interfere with taps.
    NSString *ax = YTNicoManualTrim(view.accessibilityLabel ?: @"");
    if (ax.length > 0) YTNicoManualAddTextItem(out, ax, view, includeHeader);

    for (UIView *sub in view.subviews) YTNicoManualCollectLabels(sub, out, includeHeader);
}

static CGFloat YTNicoManualFindChatHeader(UIWindow *win) {
    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoManualCollectLabels(win, labels, YES);
    CGRect wb = win.bounds;
    CGFloat best = 0;
    for (NSDictionary *item in labels) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoManualIsHeaderText(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y < wb.size.height * 0.20) continue;
        best = MAX(best, y + h / 2.0);
    }
    if (best > 0) {
        gYTNicoManualHeaderBottomY = best;
        gYTNicoManualHeaderSeenAt = CACurrentMediaTime();
    }
    return best;
}

static NSString *YTNicoManualBodyFromItems(NSArray<NSDictionary *> *items) {
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

static void YTNicoManualEmit(NSString *body, NSString *key) {
    body = YTNicoManualTrim(body);
    if (body.length == 0 || YTNicoManualLooksLikeMetadata(body)) return;
    if (!gYTNicoManualSeen) gYTNicoManualSeen = [NSMutableDictionary dictionary];
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"manual", body];
    if (gYTNicoManualSeen[seenKey]) return;
    gYTNicoManualSeen[seenKey] = @(CACurrentMediaTime());
    NSString *mid = [NSString stringWithFormat:@"manualui-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
    gYTNicoManualEmitCount++;
    CFTimeInterval now = CACurrentMediaTime();
    if (SettingsManager.shared.debugLogging && now - gYTNicoManualLastLog > 1.0) {
        gYTNicoManualLastLog = now;
        [[DebugInspector shared] important:@"manual chat panel emitted %@", body];
    }
}

static void YTNicoManualScanWindow(UIWindow *win) {
    if (!win || win.hidden || win.alpha < 0.02) return;
    CGFloat headerBottom = YTNicoManualFindChatHeader(win);
    if (headerBottom <= 0 && gYTNicoManualHeaderBottomY > 0 && CACurrentMediaTime() - gYTNicoManualHeaderSeenAt < 30.0) headerBottom = gYTNicoManualHeaderBottomY;
    if (headerBottom <= 0) return;

    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoManualCollectLabels(win, labels, NO);
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
        if (YTNicoManualLooksLikeMetadata(text)) continue;
        NSNumber *bucket = @((NSInteger)round(y / 28.0));
        NSMutableArray *arr = rows[bucket];
        if (!arr) { arr = [NSMutableArray array]; rows[bucket] = arr; }
        [arr addObject:item];
    }

    for (NSNumber *bucket in rows) {
        NSArray *items = rows[bucket];
        NSString *body = YTNicoManualBodyFromItems(items);
        if (body.length == 0) continue;
        NSString *key = [NSString stringWithFormat:@"manual-%ld", (long)bucket.integerValue];
        YTNicoManualEmit(body, key);
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
    SettingsManager *settings = SettingsManager.shared;
    if (!settings.enabled) return 0;

    gYTNicoManualScanRunning = YES;
    gYTNicoManualEmitCount = 0;
    if (!gYTNicoManualSeen) gYTNicoManualSeen = [NSMutableDictionary dictionary];
    [gYTNicoManualSeen removeAllObjects];
    @try {
        for (UIWindow *win in UIApplication.sharedApplication.windows) YTNicoManualScanWindow(win);
    } @finally {
        gYTNicoManualScanRunning = NO;
    }
    return gYTNicoManualEmitCount;
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoManualIsYouTube()) return;
        gYTNicoManualSeen = [NSMutableDictionary dictionary];
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"manual chat panel scanner loaded accessibility mode"];
    });
}

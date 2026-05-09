#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoUIScrapeSeen = nil;
static NSMutableArray<NSString *> *gYTNicoUIScrapeRecentTexts = nil;
static NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *gYTNicoUIScrapeRowBuffers = nil;
static NSMutableSet<NSString *> *gYTNicoUIScrapeFlushScheduled = nil;
static CFTimeInterval gYTNicoLastUIScrapePrune = 0;
static CFTimeInterval gYTNicoLastUIScrapeLog = 0;
static NSTimer *gYTNicoUIScrapeScanTimer = nil;

static BOOL YTNicoUIScrapeIsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static BOOL YTNicoObjectResponds(id obj, SEL sel) {
    return obj && [(NSObject *)obj respondsToSelector:sel];
}

static UIView *YTNicoViewFromNode(id node) {
    if (!YTNicoObjectResponds(node, @selector(view))) return nil;
    UIView *(*send)(id, SEL) = (UIView *(*)(id, SEL))objc_msgSend;
    UIView *view = send(node, @selector(view));
    return [view isKindOfClass:UIView.class] ? view : nil;
}

static NSAttributedString *YTNicoAttributedTextFromNode(id node) {
    if (!YTNicoObjectResponds(node, @selector(attributedText))) return nil;
    NSAttributedString *(*send)(id, SEL) = (NSAttributedString *(*)(id, SEL))objc_msgSend;
    NSAttributedString *attr = send(node, @selector(attributedText));
    return [attr isKindOfClass:NSAttributedString.class] ? attr : nil;
}

static NSString *YTNicoUIScrapeTrim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static BOOL YTNicoUIScrapeContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *n in needles) if ([lower rangeOfString:n.lowercaseString].location != NSNotFound) return YES;
    return NO;
}

static NSString *YTNicoUIScrapeClassPath(UIView *view, NSInteger maxDepth) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *v = view;
    NSInteger depth = 0;
    while (v && depth < maxDepth) {
        [parts addObject:NSStringFromClass(object_getClass(v)) ?: @""];
        v = v.superview;
        depth++;
    }
    return [parts componentsJoinedByString:@"/"];
}

static CGRect YTNicoUIScrapeWindowRect(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoUIScrapeIsInsideChatSheetByGeometry(UIView *view) {
    if (!view.window) return NO;
    CGRect r = YTNicoUIScrapeWindowRect(view);
    CGRect w = view.window.bounds;
    if (CGRectIsEmpty(r) || w.size.height <= 0 || w.size.width <= 0) return NO;
    BOOL portraitLowerPanel = CGRectGetMidY(r) > w.size.height * 0.34;
    BOOL landscapeRightPanel = w.size.width > w.size.height && CGRectGetMidX(r) > w.size.width * 0.42;
    BOOL notTiny = r.size.height >= 4.0 && r.size.width >= 10.0;
    BOOL notFullScreenTitle = r.size.height < w.size.height * 0.78;
    BOOL withinMargins = CGRectGetMinX(r) >= -40.0 && CGRectGetMaxX(r) <= w.size.width + 40.0;
    return (portraitLowerPanel || landscapeRightPanel) && notTiny && notFullScreenTitle && withinMargins;
}

static BOOL YTNicoUIScrapeLooksLikeMetadataPath(NSString *path) {
    return YTNicoUIScrapeContainsAny(path, @[
        @"description", @"metadata", @"metadataview", @"title", @"watchmetadata", @"videoowner",
        @"slimvideo", @"expandablemetadata", @"engagementpaneldescription", @"infopanel",
        @"compactvideo", @"related", @"thumbnail", @"playlist", @"shelf"
    ]);
}

static BOOL YTNicoUIScrapeLooksLikeChatHierarchy(UIView *view) {
    NSString *path = YTNicoUIScrapeClassPath(view, 18);
    if (YTNicoUIScrapeLooksLikeMetadataPath(path)) return NO;

    BOOL strongChatSignal = YTNicoUIScrapeContainsAny(path, @[
        @"livechat", @"live_chat", @"ytlivechat", @"ytlive", @"chatreplay", @"livechatreplay",
        @"chatmessage", @"livechatmessage", @"livechatitem", @"replaychat", @"conversationbar", @"livechattext"
    ]);
    if (strongChatSignal) return YES;

    BOOL genericRow = YTNicoUIScrapeContainsAny(path, @[@"asdisplay", @"collection", @"table", @"cell", @"renderer", @"stack", @"label", @"display"]);
    BOOL plausibleYouTubeTree = YTNicoUIScrapeContainsAny(path, @[@"yt", @"youtube", @"asdisplay", @"uicollection", @"uitable"]);
    return genericRow && plausibleYouTubeTree && YTNicoUIScrapeIsInsideChatSheetByGeometry(view);
}

static BOOL YTNicoIsJapaneseShortReaction(NSString *text) {
    text = YTNicoUIScrapeTrim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(w{1,}|ｗ{1,}|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな+|せやね+|そやね+|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoUIScrapeRejectText(NSString *text) {
    text = YTNicoUIScrapeTrim(text);
    if (text.length < 1 || text.length > 520) return YES;
    if (YTNicoIsJapaneseShortReaction(text)) return NO;

    NSArray *rejectExact = @[
        @"返信", @"共有", @"保存", @"チャンネル登録", @"高評価", @"低評価", @"ライブチャット", @"チャット",
        @"上位チャット", @"すべてのチャット", @"チャットのリプレイ", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定"
    ];
    for (NSString *r in rejectExact) if ([text isEqualToString:r]) return YES;
    NSArray *rejectContains = @[
        @"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"メンバーになる", @"チャンネルを作成", @"ログイン", @"Google", @"YouTube Premium"
    ];
    return YTNicoUIScrapeContainsAny(text, rejectContains);
}

static BOOL YTNicoUIScrapeLooksLikeMetadataOnly(NSString *text) {
    text = YTNicoUIScrapeTrim(text);
    if (text.length == 0) return YES;
    if (YTNicoIsJapaneseShortReaction(text)) return NO;
    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

static BOOL YTNicoUIScrapeFragmentLooksLikeHandle(NSString *text) {
    text = YTNicoUIScrapeTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return NO;
    if (text.length > 84) return NO;
    if ([text rangeOfString:@"。"].location != NSNotFound || [text rangeOfString:@"！"].location != NSNotFound || [text rangeOfString:@"？"].location != NSNotFound) return NO;
    return YES;
}

static NSString *YTNicoStripSeparatedHandle(NSString *text) {
    text = YTNicoUIScrapeTrim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *withSep = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：]+[\\s　:：-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [withSep firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoUIScrapeTrim([text substringWithRange:[m rangeAtIndex:1]]);
    return text;
}

static NSString *YTNicoBodyFromSingleText(NSString *rawText) {
    NSString *text = YTNicoUIScrapeTrim(rawText);
    if (text.length == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *lineRaw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = YTNicoUIScrapeTrim(lineRaw);
        if (line.length == 0) continue;
        if (YTNicoUIScrapeRejectText(line) || YTNicoUIScrapeLooksLikeMetadataOnly(line)) continue;
        [lines addObject:line];
    }
    if (lines.count == 0) return @"";
    if (lines.count >= 2 && YTNicoUIScrapeFragmentLooksLikeHandle(lines[0])) {
        return YTNicoUIScrapeTrim([[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] componentsJoinedByString:@" "]);
    }
    NSString *joined = YTNicoUIScrapeTrim([lines componentsJoinedByString:@" "]);
    NSString *stripped = YTNicoStripSeparatedHandle(joined);
    return stripped.length ? stripped : joined;
}

static void YTNicoCollectLabelsInView(UIView *view, NSMutableArray<NSDictionary *> *out) {
    if (!view || view.hidden || view.alpha < 0.02) return;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = YTNicoUIScrapeTrim(label.text ?: label.attributedText.string ?: @"");
        if (text.length > 0) {
            CGRect r = YTNicoUIScrapeWindowRect(label);
            if (!CGRectIsEmpty(r)) [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(r)), @"y": @(CGRectGetMidY(r)), @"w": @(CGRectGetWidth(r)), @"h": @(CGRectGetHeight(r))}];
        }
    }
    for (UIView *sub in view.subviews) YTNicoCollectLabelsInView(sub, out);
}

static UIView *YTNicoUIScrapeRowContainer(UIView *view) {
    UIView *best = nil;
    UIView *v = view;
    NSInteger depth = 0;
    while (v && depth < 14) {
        CGRect r = YTNicoUIScrapeWindowRect(v);
        CGRect w = v.window.bounds;
        NSString *cls = NSStringFromClass(object_getClass(v)) ?: @"";
        BOOL classLooksRow = YTNicoUIScrapeContainsAny(cls, @[@"cell", @"renderer", @"row", @"item", @"stack", @"asdisplay", @"message"]);
        BOOL sizeLooksRow = v.window && r.size.width > w.size.width * 0.36 && r.size.height >= 18.0 && r.size.height <= 160.0;
        if (YTNicoUIScrapeIsInsideChatSheetByGeometry(v) && (classLooksRow || sizeLooksRow)) best = v;
        v = v.superview;
        depth++;
    }
    return best ?: view;
}

static NSString *YTNicoUIScrapeRowKey(UIView *sourceView) {
    UIView *row = YTNicoUIScrapeRowContainer(sourceView);
    CGRect r = YTNicoUIScrapeWindowRect(row);
    NSInteger yBucket = (NSInteger)round(CGRectGetMidY(r) / 10.0);
    return [NSString stringWithFormat:@"%p|%ld", (__bridge void *)row, (long)yBucket];
}

static NSString *YTNicoBodyFromLabelItems(NSArray<NSDictionary *> *items) {
    if (items.count == 0) return @"";
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

    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    NSMutableSet<NSString *> *partSeen = [NSMutableSet set];
    for (NSDictionary *item in sorted) {
        NSString *t = YTNicoUIScrapeTrim(item[@"text"] ?: @"");
        if (t.length == 0 || [partSeen containsObject:t]) continue;
        [partSeen addObject:t];
        if (YTNicoUIScrapeRejectText(t) || YTNicoUIScrapeLooksLikeMetadataOnly(t)) continue;
        if (YTNicoUIScrapeFragmentLooksLikeHandle(t) && sorted.count > 1) continue;
        NSString *bodyPart = YTNicoStripSeparatedHandle(t);
        if (bodyPart.length == 0) continue;
        [kept addObject:bodyPart];
    }

    if (kept.count == 0 && sorted.count == 1) return YTNicoBodyFromSingleText(sorted.firstObject[@"text"] ?: @"");
    return YTNicoUIScrapeTrim([kept componentsJoinedByString:@" "]);
}

static void YTNicoUIScrapePruneSeen(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLastUIScrapePrune < 1.5) return;
    gYTNicoLastUIScrapePrune = now;
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *key in gYTNicoUIScrapeSeen) if (now - gYTNicoUIScrapeSeen[key].doubleValue > 4.0) [remove addObject:key];
    [gYTNicoUIScrapeSeen removeObjectsForKeys:remove];
    while (gYTNicoUIScrapeRecentTexts.count > 100) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];
}

static void YTNicoUIScrapeEmitBody(NSString *body, NSString *rowKey) {
    SettingsManager *settings = SettingsManager.shared;
    body = YTNicoUIScrapeTrim(body);
    if (body.length == 0) return;
    if (YTNicoUIScrapeRejectText(body) || YTNicoUIScrapeLooksLikeMetadataOnly(body)) return;

    if (!gYTNicoUIScrapeSeen) gYTNicoUIScrapeSeen = [NSMutableDictionary dictionary];
    if (!gYTNicoUIScrapeRecentTexts) gYTNicoUIScrapeRecentTexts = [NSMutableArray array];
    YTNicoUIScrapePruneSeen();

    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", rowKey ?: @"row", body ?: @""];
    if (gYTNicoUIScrapeSeen[seenKey]) return;
    gYTNicoUIScrapeSeen[seenKey] = @(CACurrentMediaTime());
    [gYTNicoUIScrapeRecentTexts addObject:body];
    while (gYTNicoUIScrapeRecentTexts.count > 100) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];

    NSString *mid = [NSString stringWithFormat:@"uirow-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];

    CFTimeInterval now = CACurrentMediaTime();
    if (settings.debugLogging && now - gYTNicoLastUIScrapeLog > 1.0) {
        gYTNicoLastUIScrapeLog = now;
        [[DebugInspector shared] important:@"UI cell scrape emitted body=%@", body ?: @""];
    }
}

static void YTNicoUIScrapeFlushRow(NSString *rowKey) {
    if (rowKey.length == 0) return;
    NSMutableArray<NSDictionary *> *items = gYTNicoUIScrapeRowBuffers[rowKey];
    if (items.count == 0) {
        [gYTNicoUIScrapeFlushScheduled removeObject:rowKey];
        return;
    }
    NSArray<NSDictionary *> *snapshot = [items copy];
    [gYTNicoUIScrapeRowBuffers removeObjectForKey:rowKey];
    [gYTNicoUIScrapeFlushScheduled removeObject:rowKey];
    NSString *body = YTNicoBodyFromLabelItems(snapshot);
    if (body.length > 0) YTNicoUIScrapeEmitBody(body, rowKey);
}

static void YTNicoUIScrapeBufferText(NSString *rawText, UIView *sourceView) {
    SettingsManager *settings = SettingsManager.shared;
    if (!YTNicoUIScrapeIsYouTube() || !settings.enabled) return;
    if ([settings respondsToSelector:@selector(uiScrapeFallback)] && !settings.uiScrapeFallback) return;
    if (![sourceView isKindOfClass:UIView.class]) return;
    if (!YTNicoUIScrapeLooksLikeChatHierarchy(sourceView)) return;

    NSString *text = YTNicoUIScrapeTrim(rawText);
    if (text.length == 0) return;
    if (YTNicoUIScrapeRejectText(text) || YTNicoUIScrapeLooksLikeMetadataOnly(text)) return;

    UIView *row = YTNicoUIScrapeRowContainer(sourceView);
    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoCollectLabelsInView(row, labels);
    if (labels.count >= 2) {
        NSString *body = YTNicoBodyFromLabelItems(labels);
        if (body.length > 0) {
            YTNicoUIScrapeEmitBody(body, YTNicoUIScrapeRowKey(row));
            return;
        }
    }

    if (!gYTNicoUIScrapeRowBuffers) gYTNicoUIScrapeRowBuffers = [NSMutableDictionary dictionary];
    if (!gYTNicoUIScrapeFlushScheduled) gYTNicoUIScrapeFlushScheduled = [NSMutableSet set];

    CGRect r = YTNicoUIScrapeWindowRect(sourceView);
    NSString *rowKey = YTNicoUIScrapeRowKey(sourceView);
    if (rowKey.length == 0) return;
    NSMutableArray *bucket = gYTNicoUIScrapeRowBuffers[rowKey];
    if (!bucket) {
        bucket = [NSMutableArray array];
        gYTNicoUIScrapeRowBuffers[rowKey] = bucket;
    }
    [bucket addObject:@{@"text": text, @"x": @(CGRectGetMinX(r)), @"y": @(CGRectGetMidY(r)), @"w": @(CGRectGetWidth(r)), @"h": @(CGRectGetHeight(r))}];

    if (![gYTNicoUIScrapeFlushScheduled containsObject:rowKey]) {
        [gYTNicoUIScrapeFlushScheduled addObject:rowKey];
        NSString *keyCopy = [rowKey copy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ YTNicoUIScrapeFlushRow(keyCopy); });
    }
}

static BOOL YTNicoViewLooksLikeChatRowCandidate(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.02 || !view.window) return NO;
    if (!YTNicoUIScrapeLooksLikeChatHierarchy(view)) return NO;
    CGRect r = YTNicoUIScrapeWindowRect(view);
    CGRect w = view.window.bounds;
    if (CGRectIsEmpty(r)) return NO;
    if (r.size.height < 18.0 || r.size.height > 170.0) return NO;
    if (r.size.width < w.size.width * 0.30) return NO;
    NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
    YTNicoCollectLabelsInView(view, labels);
    if (labels.count < 1 || labels.count > 12) return NO;
    NSString *body = YTNicoBodyFromLabelItems(labels);
    if (body.length == 0) return NO;
    return YES;
}

static void YTNicoScanRowCandidatesInView(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.02) return;
    if (YTNicoViewLooksLikeChatRowCandidate(view)) {
        NSMutableArray<NSDictionary *> *labels = [NSMutableArray array];
        YTNicoCollectLabelsInView(view, labels);
        NSString *body = YTNicoBodyFromLabelItems(labels);
        if (body.length > 0) {
            CGRect r = YTNicoUIScrapeWindowRect(view);
            NSString *key = [NSString stringWithFormat:@"cell-%p-%ld", (__bridge void *)view, (long)round(CGRectGetMidY(r) / 10.0)];
            YTNicoUIScrapeEmitBody(body, key);
            return; // avoid also scanning children of the same row candidate
        }
    }
    for (UIView *sub in view.subviews) YTNicoScanRowCandidatesInView(sub);
}

static void YTNicoUIScrapePeriodicScan(void) {
    if (!YTNicoUIScrapeIsYouTube()) return;
    SettingsManager *settings = SettingsManager.shared;
    if (!settings.enabled) return;
    if ([settings respondsToSelector:@selector(uiScrapeFallback)] && !settings.uiScrapeFallback) return;
    for (UIWindow *win in UIApplication.sharedApplication.windows) YTNicoScanRowCandidatesInView(win);
}

%hook UILabel
- (void)setText:(NSString *)text { %orig(text); if (text.length > 0) YTNicoUIScrapeBufferText(text, self); }
- (void)setAttributedText:(NSAttributedString *)attributedText { %orig(attributedText); NSString *text = attributedText.string ?: @""; if (text.length > 0) YTNicoUIScrapeBufferText(text, self); }
- (void)didMoveToWindow { %orig; NSString *text = self.text ?: self.attributedText.string ?: @""; if (text.length > 0) YTNicoUIScrapeBufferText(text, self); }
%end

%hook ASTextNode
- (void)setAttributedText:(NSAttributedString *)attributedText { %orig(attributedText); NSString *text = attributedText.string ?: @""; UIView *view = YTNicoViewFromNode((id)self); if (text.length > 0 && view) YTNicoUIScrapeBufferText(text, view); }
%end

%hook ASDisplayNode
- (void)didEnterVisibleState {
    %orig;
    id node = (id)self;
    UIView *view = YTNicoViewFromNode(node);
    if (!view) return;
    NSString *className = NSStringFromClass(object_getClass(node));
    if (!YTNicoUIScrapeContainsAny(className, @[@"text", @"label", @"message", @"chat", @"comment", @"node", @"display"])) return;
    NSAttributedString *attr = YTNicoAttributedTextFromNode(node);
    NSString *desc = attr.string ?: @"";
    if (desc.length > 0) YTNicoUIScrapeBufferText(desc, view);
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoUIScrapeIsYouTube()) return;
        gYTNicoUIScrapeSeen = [NSMutableDictionary dictionary];
        gYTNicoUIScrapeRecentTexts = [NSMutableArray array];
        gYTNicoUIScrapeRowBuffers = [NSMutableDictionary dictionary];
        gYTNicoUIScrapeFlushScheduled = [NSMutableSet set];
        if (!gYTNicoUIScrapeScanTimer) {
            gYTNicoUIScrapeScanTimer = [NSTimer scheduledTimerWithTimeInterval:0.55 repeats:YES block:^(__unused NSTimer *timer) { YTNicoUIScrapePeriodicScan(); }];
            [[NSRunLoop mainRunLoop] addTimer:gYTNicoUIScrapeScanTimer forMode:NSRunLoopCommonModes];
        }
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"UI chat scrape fallback loaded cell-scan mode"];
    });
}

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static dispatch_source_t gYTNicoStrictV2Timer = nil;
static NSString *gYTNicoStrictV2VideoId = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoStrictV2Seen = nil;
static BOOL gYTNicoStrictV2Busy = NO;

typedef NSDictionary<NSString *, id> YTNicoStrictV2Item;

static BOOL YTNicoStrictV2IsYouTube(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"];
}

static NSString *YTNicoStrictV2Trim(NSString *s) {
    if (![s isKindOfClass:NSString.class]) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    while ([s rangeOfString:@"\n\n"].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"\n\n" withString:@"\n"];
    return s ?: @"";
}

static CGRect YTNicoStrictV2Rect(UIView *view) {
    if (!view.window) return CGRectZero;
    return [view convertRect:view.bounds toView:view.window];
}

static BOOL YTNicoStrictV2ContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *lower = s.lowercaseString ?: @"";
    for (NSString *needle in needles) if ([lower rangeOfString:needle.lowercaseString].location != NSNotFound) return YES;
    return NO;
}

static NSRegularExpression *YTNicoStrictV2HandleRegex(void) {
    static NSRegularExpression *re = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"(^|[\\s　])[@＠][^\\s　:：,，、]{2,84}" options:0 error:nil];
    });
    return re;
}

static BOOL YTNicoStrictV2HasHandle(NSString *text) {
    text = YTNicoStrictV2Trim(text);
    if (text.length == 0) return NO;
    NSRegularExpression *re = YTNicoStrictV2HandleRegex();
    return re && [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoStrictV2IsHeader(NSString *text) {
    text = YTNicoStrictV2Trim(text);
    return [text isEqualToString:@"チャットのリプレイ"] ||
           [text isEqualToString:@"ライブチャット"] ||
           [text isEqualToString:@"上位のメッセージ"] ||
           [text isEqualToString:@"上位チャット"] ||
           [text isEqualToString:@"すべてのチャット"] ||
           [text hasPrefix:@"チャットのリプレイ "] ||
           [text hasPrefix:@"ライブチャット "];
}

static BOOL YTNicoStrictV2IsShortReaction(NSString *text) {
    text = YTNicoStrictV2Trim(text);
    if (text.length == 0 || text.length > 24) return NO;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(0|w+|ｗ+|草+|笑+|www+|WWW+|お+|うん+|いいね+|すご+|すごい+|それな|せやね|そやね|たしかに|確かに|ふむ+|へぇ+|ええ+|やば+|かわい+|かわいい+|キタ+|きた+|ドキドキ|ワクワク|！？+|!!+|！+|\\?+|？+|😂+|🤣+|😭+|🥹+)$" options:NSRegularExpressionCaseInsensitive error:nil];
    return re && [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YTNicoStrictV2LooksLikeMetadata(NSString *text) {
    text = YTNicoStrictV2Trim(text);
    if (text.length == 0) return YES;
    if (YTNicoStrictV2IsShortReaction(text)) return NO;
    if (YTNicoStrictV2IsHeader(text)) return YES;

    NSArray *exact = @[@"返信", @"共有", @"保存", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"チャットのリプレイ", @"上位のメッセージ", @"上位チャット", @"すべてのチャット", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定", @"閉じる", @"フィルタ", @"その他", @"新着", @"メンバーになる"];
    for (NSString *x in exact) if ([text isEqualToString:x]) return YES;

    NSArray *blocked = @[@"回視聴", @"人が視聴中", @"チャンネル登録", @"操作メニュー", @"概要欄", @"動画を再生", @"コメントを見る", @"この動画のライブ配信時", @"メッセージを入力", @"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"Google", @"YouTube Premium", @"CUTIE STREET", @"FRUITS ZIPPER", @"関連動画", @"次の動画", @"ショート", @"ホーム"];
    if (YTNicoStrictV2ContainsAny(text, blocked)) return YES;

    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if (timeOnly && [timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億０-９，]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    return countOnly && [countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static NSString *YTNicoStrictV2StripHandle(NSString *text) {
    text = YTNicoStrictV2Trim(text);
    if (![text hasPrefix:@"@"] && ![text hasPrefix:@"＠"]) return text;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^[＠@][^\\s　:：,，、]+[\\s　:：,，、-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = re ? [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] : nil;
    if (m && m.numberOfRanges >= 2) return YTNicoStrictV2Trim([text substringWithRange:[m rangeAtIndex:1]]);
    return @"";
}

static BOOL YTNicoStrictV2BodySafe(NSString *body) {
    body = YTNicoStrictV2Trim(body);
    if (body.length == 0 || body.length > 140) return NO;
    if (YTNicoStrictV2LooksLikeMetadata(body)) return NO;
    if (YTNicoStrictV2HasHandle(body)) body = YTNicoStrictV2StripHandle(body);
    if (body.length == 0 || YTNicoStrictV2LooksLikeMetadata(body)) return NO;
    NSUInteger spaces = [[body componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count] - 1;
    if (body.length > 70 && spaces >= 5) return NO;
    if ([body rangeOfString:@"\n"].location != NSNotFound && body.length > 60) return NO;
    return YES;
}

static void YTNicoStrictV2Add(NSMutableArray<YTNicoStrictV2Item *> *out, NSString *text, CGRect rect) {
    text = YTNicoStrictV2Trim(text);
    if (text.length == 0 || CGRectIsEmpty(rect)) return;
    [out addObject:@{@"text": text, @"x": @(CGRectGetMinX(rect)), @"y": @(CGRectGetMidY(rect)), @"w": @(CGRectGetWidth(rect)), @"h": @(CGRectGetHeight(rect))}];
}

static void YTNicoStrictV2CollectAX(id object, UIView *fallback, NSMutableArray<YTNicoStrictV2Item *> *out) {
    if (!object || out.count > 450) return;
    CGRect rect = YTNicoStrictV2Rect(fallback);
    if ([object isKindOfClass:NSString.class]) { YTNicoStrictV2Add(out, object, rect); return; }
    if ([object isKindOfClass:NSAttributedString.class]) { YTNicoStrictV2Add(out, [(NSAttributedString *)object string], rect); return; }
    if ([object isKindOfClass:UIView.class]) rect = YTNicoStrictV2Rect((UIView *)object);
    else if ([object respondsToSelector:@selector(accessibilityFrame)]) {
        CGRect ax = [object accessibilityFrame];
        if (!CGRectIsEmpty(ax)) rect = ax;
    }
    if ([object respondsToSelector:@selector(accessibilityLabel)]) YTNicoStrictV2Add(out, [object accessibilityLabel] ?: @"", rect);
    if ([object respondsToSelector:@selector(accessibilityValue)]) YTNicoStrictV2Add(out, [object accessibilityValue] ?: @"", rect);
}

static void YTNicoStrictV2Collect(UIView *view, NSMutableArray<YTNicoStrictV2Item *> *out) {
    if (!view || view.hidden || view.alpha < 0.02 || out.count > 450) return;
    CGRect rect = YTNicoStrictV2Rect(view);
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        YTNicoStrictV2Add(out, label.text ?: label.attributedText.string ?: @"", rect);
    } else if ([view isKindOfClass:UITextView.class]) {
        YTNicoStrictV2Add(out, ((UITextView *)view).text ?: @"", rect);
    }
    YTNicoStrictV2Add(out, view.accessibilityLabel ?: @"", rect);
    NSArray *elements = view.accessibilityElements;
    if ([elements isKindOfClass:NSArray.class]) for (id e in elements) YTNicoStrictV2CollectAX(e, view, out);
    for (UIView *sub in view.subviews) YTNicoStrictV2Collect(sub, out);
}

static CGFloat YTNicoStrictV2PanelTop(UIWindow *win, NSArray<YTNicoStrictV2Item *> *items) {
    CGRect wb = win.bounds;
    CGFloat top = 0.0;
    for (YTNicoStrictV2Item *item in items) {
        NSString *text = item[@"text"] ?: @"";
        if (!YTNicoStrictV2IsHeader(text)) continue;
        CGFloat y = [item[@"y"] doubleValue];
        CGFloat h = [item[@"h"] doubleValue];
        if (y < wb.size.height * 0.20) continue;
        top = MAX(top, y + h / 2.0 + 10.0);
    }
    return top;
}

static NSString *YTNicoStrictV2BodyFromRow(NSArray<YTNicoStrictV2Item *> *row) {
    NSArray *sorted = [row sortedArrayUsingComparator:^NSComparisonResult(YTNicoStrictV2Item *a, YTNicoStrictV2Item *b) {
        CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 9.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue], bx = [b[@"x"] doubleValue];
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];

    BOOL hasAuthor = NO;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (YTNicoStrictV2Item *item in sorted) {
        NSString *t = YTNicoStrictV2Trim(item[@"text"] ?: @"");
        if (t.length == 0 || [seen containsObject:t] || YTNicoStrictV2LooksLikeMetadata(t)) continue;
        [seen addObject:t];
        if (YTNicoStrictV2HasHandle(t)) {
            hasAuthor = YES;
            NSString *stripped = YTNicoStrictV2StripHandle(t);
            if (YTNicoStrictV2BodySafe(stripped)) [parts addObject:stripped];
            continue;
        }
        if (hasAuthor && YTNicoStrictV2BodySafe(t)) [parts addObject:t];
    }
    if (!hasAuthor) return @"";
    NSString *body = YTNicoStrictV2Trim([parts componentsJoinedByString:@" "]);
    return YTNicoStrictV2BodySafe(body) ? body : @"";
}

static void YTNicoStrictV2PruneSeen(void) {
    if (!gYTNicoStrictV2Seen) gYTNicoStrictV2Seen = [NSMutableDictionary dictionary];
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableArray *remove = [NSMutableArray array];
    for (NSString *k in gYTNicoStrictV2Seen) if (now - gYTNicoStrictV2Seen[k].doubleValue > 90.0) [remove addObject:k];
    [gYTNicoStrictV2Seen removeObjectsForKeys:remove];
}

static void YTNicoStrictV2Emit(NSString *body, NSString *key) {
    body = YTNicoStrictV2Trim(body);
    if (!YTNicoStrictV2BodySafe(body)) return;
    if (!gYTNicoStrictV2Seen) gYTNicoStrictV2Seen = [NSMutableDictionary dictionary];
    YTNicoStrictV2PruneSeen();
    NSString *seenKey = [NSString stringWithFormat:@"%@|%@", key ?: @"strict-v2", body];
    if (gYTNicoStrictV2Seen[seenKey]) return;
    gYTNicoStrictV2Seen[seenKey] = @(CACurrentMediaTime());
    NSString *mid = [NSString stringWithFormat:@"strictv2-%lu-%llu", (unsigned long)[seenKey hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:body messageId:mid];
}

static void YTNicoStrictV2ScanOnce(void) {
    if (gYTNicoStrictV2Busy || !YTNicoStrictV2IsYouTube() || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || !SettingsManager.shared.enabled) return;
    gYTNicoStrictV2Busy = YES;
    @try {
        for (UIWindow *win in UIApplication.sharedApplication.windows) {
            if (!win || win.hidden || win.alpha < 0.02) continue;
            NSMutableArray<YTNicoStrictV2Item *> *all = [NSMutableArray array];
            YTNicoStrictV2Collect(win, all);
            CGFloat panelTop = YTNicoStrictV2PanelTop(win, all);
            if (panelTop <= 0.0) continue;
            CGRect wb = win.bounds;

            NSMutableArray<YTNicoStrictV2Item *> *anchors = [NSMutableArray array];
            for (YTNicoStrictV2Item *item in all) {
                NSString *text = YTNicoStrictV2Trim(item[@"text"] ?: @"");
                CGFloat y = [item[@"y"] doubleValue];
                CGFloat x = [item[@"x"] doubleValue];
                if (y < panelTop || y > wb.size.height - 8.0 || x < -20.0 || x > wb.size.width + 20.0) continue;
                if (YTNicoStrictV2LooksLikeMetadata(text)) continue;
                if (YTNicoStrictV2HasHandle(text)) [anchors addObject:item];
            }
            NSArray *sortedAnchors = [anchors sortedArrayUsingComparator:^NSComparisonResult(YTNicoStrictV2Item *a, YTNicoStrictV2Item *b) {
                CGFloat ay = [a[@"y"] doubleValue], by = [b[@"y"] doubleValue];
                return ay < by ? NSOrderedAscending : (ay > by ? NSOrderedDescending : NSOrderedSame);
            }];

            for (NSUInteger i = 0; i < sortedAnchors.count; i++) {
                YTNicoStrictV2Item *anchor = sortedAnchors[i];
                CGFloat ay = [anchor[@"y"] doubleValue];
                CGFloat ax = [anchor[@"x"] doubleValue];
                CGFloat prevY = (i > 0) ? [sortedAnchors[i - 1][@"y"] doubleValue] : panelTop;
                CGFloat nextY = (i + 1 < sortedAnchors.count) ? [sortedAnchors[i + 1][@"y"] doubleValue] : MIN(wb.size.height, ay + 58.0);
                CGFloat top = MAX(panelTop, (prevY + ay) / 2.0 - 4.0);
                CGFloat bottom = MIN(wb.size.height - 8.0, (ay + nextY) / 2.0 + 6.0);
                if (bottom - top < 30.0) bottom = MIN(wb.size.height - 8.0, top + 40.0);

                NSMutableArray *row = [NSMutableArray array];
                for (YTNicoStrictV2Item *item in all) {
                    CGFloat y = [item[@"y"] doubleValue];
                    CGFloat x = [item[@"x"] doubleValue];
                    NSString *text = item[@"text"] ?: @"";
                    if (y < top || y > bottom || x < ax - 24.0 || x > wb.size.width + 20.0) continue;
                    if (YTNicoStrictV2LooksLikeMetadata(text)) continue;
                    [row addObject:item];
                }
                NSString *body = YTNicoStrictV2BodyFromRow(row);
                if (body.length == 0) continue;
                NSString *key = [NSString stringWithFormat:@"strictv2-row-%lu-%lu", (unsigned long)[body hash], (unsigned long)round(ay / 20.0)];
                YTNicoStrictV2Emit(body, key);
            }
        }
    } @finally {
        gYTNicoStrictV2Busy = NO;
    }
}

static void YTNicoStrictV2Stop(void) {
    if (gYTNicoStrictV2Timer) {
        dispatch_source_cancel(gYTNicoStrictV2Timer);
        gYTNicoStrictV2Timer = nil;
    }
    gYTNicoStrictV2VideoId = nil;
    [gYTNicoStrictV2Seen removeAllObjects];
}

static void YTNicoStrictV2Start(NSString *videoId) {
    if (!YTNicoStrictV2IsYouTube()) return;
    if (!gYTNicoStrictV2Seen) gYTNicoStrictV2Seen = [NSMutableDictionary dictionary];
    YTNicoStrictV2Stop();
    gYTNicoStrictV2VideoId = [videoId copy];
    gYTNicoStrictV2Timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!gYTNicoStrictV2Timer) return;
    uint64_t interval = (uint64_t)(0.85 * (double)NSEC_PER_SEC);
    uint64_t leeway = (uint64_t)(0.12 * (double)NSEC_PER_SEC);
    dispatch_source_set_timer(gYTNicoStrictV2Timer, dispatch_time(DISPATCH_TIME_NOW, interval), interval, leeway);
    dispatch_source_set_event_handler(gYTNicoStrictV2Timer, ^{
        if (!SettingsManager.shared.enabled || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        NSString *current = [YouTubeChatAdapter currentVideoId] ?: @"";
        if (gYTNicoStrictV2VideoId.length == 11 && current.length == 11 && ![current isEqualToString:gYTNicoStrictV2VideoId]) {
            YTNicoStrictV2Stop();
            [[DebugInspector shared] important:@"strict v2 chat scanner stopped: video changed"];
            return;
        }
        YTNicoStrictV2ScanOnce();
    });
    dispatch_resume(gYTNicoStrictV2Timer);
    [[DebugInspector shared] important:@"strict v2 chat scanner started videoId=%@", gYTNicoStrictV2VideoId ?: @""];
}

%hook YTNicoController
- (void)toggleOverlayEnabled {
    %orig;
    NSString *videoId = [YouTubeChatAdapter currentVideoId] ?: @"";
    YTNicoStrictV2Start(videoId.length == 11 ? videoId : nil);
}

- (void)clearOverlayForVideoChange {
    YTNicoStrictV2Stop();
    %orig;
}

- (void)reloadSettings {
    if (!SettingsManager.shared.enabled) YTNicoStrictV2Stop();
    %orig;
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoStrictV2IsYouTube()) return;
        gYTNicoStrictV2Seen = [NSMutableDictionary dictionary];
        if (SettingsManager.shared.debugLogging) [[DebugInspector shared] important:@"strict v2 live chat panel scanner loaded"];
    });
}

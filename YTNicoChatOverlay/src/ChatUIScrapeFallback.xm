#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSMutableDictionary<NSString *, NSNumber *> *gYTNicoUIScrapeSeen = nil;
static NSMutableArray<NSString *> *gYTNicoUIScrapeRecentTexts = nil;
static CFTimeInterval gYTNicoLastUIScrapePrune = 0;
static CFTimeInterval gYTNicoLastUIScrapeLog = 0;
static BOOL gYTNicoUIScrapeEnabled = YES;

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
    for (NSString *n in needles) {
        if ([lower rangeOfString:n.lowercaseString].location != NSNotFound) return YES;
    }
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

static BOOL YTNicoUIScrapeIsInsideChatSheetByGeometry(UIView *view) {
    if (!view.window) return NO;
    CGRect r = [view convertRect:view.bounds toView:view.window];
    CGRect w = view.window.bounds;
    if (CGRectIsEmpty(r) || w.size.height <= 0 || w.size.width <= 0) return NO;

    // Chat replay sheet in portrait lives below the player, roughly lower half.
    BOOL lowerHalf = CGRectGetMidY(r) > w.size.height * 0.42;
    BOOL notTiny = r.size.height >= 8.0 && r.size.width >= 24.0;
    BOOL withinSideMargins = CGRectGetMinX(r) >= -8.0 && CGRectGetMaxX(r) <= w.size.width + 8.0;
    return lowerHalf && notTiny && withinSideMargins;
}

static BOOL YTNicoUIScrapeLooksLikeMetadataPath(NSString *path) {
    return YTNicoUIScrapeContainsAny(path, @[
        @"description",
        @"metadata",
        @"metadataview",
        @"title",
        @"watchmetadata",
        @"videoowner",
        @"slimvideo",
        @"expandablemetadata",
        @"engagementpaneldescription",
        @"infopanel",
        @"compactvideo",
        @"related",
        @"thumbnail"
    ]);
}

static BOOL YTNicoUIScrapeLooksLikeChatHierarchy(UIView *view) {
    NSString *path = YTNicoUIScrapeClassPath(view, 18);
    if (YTNicoUIScrapeLooksLikeMetadataPath(path)) return NO;

    BOOL strongChatSignal = YTNicoUIScrapeContainsAny(path, @[
        @"livechat",
        @"live_chat",
        @"ytlivechat",
        @"ytlive",
        @"chatreplay",
        @"livechatreplay",
        @"chatmessage",
        @"livechatmessage",
        @"livechatitem",
        @"replaychat",
        @"conversationbar"
    ]);
    if (strongChatSignal) return YES;

    // YouTube often uses generic ASDisplayView / UICollectionView cells for replay rows.
    // Permit those only when they are in the lower chat sheet area. This restores UI
    // scrape without reopening the video title / description panel.
    BOOL genericRow = YTNicoUIScrapeContainsAny(path, @[@"asdisplay", @"collection", @"table", @"cell", @"renderer", @"stack"]);
    BOOL youtubeView = YTNicoUIScrapeContainsAny(path, @[@"yt", @"youtube", @"asdisplay"]);
    if (genericRow && youtubeView && YTNicoUIScrapeIsInsideChatSheetByGeometry(view)) return YES;

    return NO;
}

static BOOL YTNicoUIScrapeRejectText(NSString *text) {
    if (text.length < 1 || text.length > 220) return YES;
    NSArray *rejectExact = @[@"返信", @"共有", @"保存", @"チャンネル登録", @"高評価", @"低評価", @"ライブチャット", @"チャット", @"上位チャット", @"すべてのチャット", @"チャットのリプレイ", @"コメント", @"並べ替え", @"キャンセル", @"送信", @"検索", @"設定"];
    for (NSString *r in rejectExact) if ([text isEqualToString:r]) return YES;
    NSArray *rejectContains = @[@"http://", @"https://", @"利用規約", @"プライバシー", @"広告", @"メンバーになる", @"チャンネルを作成", @"ログイン", @"Google", @"YouTube Premium"];
    if (YTNicoUIScrapeContainsAny(text, rejectContains)) return YES;
    return NO;
}

static BOOL YTNicoUIScrapeLooksLikeMetadataOnly(NSString *text) {
    if (text.length == 0) return YES;
    NSRegularExpression *timeOnly = [NSRegularExpression regularExpressionWithPattern:@"^([0-9]{1,2}:)?[0-9]{1,2}:[0-9]{2}$" options:0 error:nil];
    if ([timeOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    NSRegularExpression *countOnly = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億]+\\s*(回視聴|人が視聴中|件|日前|時間前|分前)$" options:0 error:nil];
    if ([countOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    NSRegularExpression *handleOnly = [NSRegularExpression regularExpressionWithPattern:@"^@[^\\s　:：]+$" options:0 error:nil];
    if ([handleOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

static NSString *YTNicoStripLeadingHandleFromLine(NSString *line) {
    line = YTNicoUIScrapeTrim(line);
    if (![line hasPrefix:@"@"]) return line;

    NSRegularExpression *withSep = [NSRegularExpression regularExpressionWithPattern:@"^@[^\\s　:：]+[\\s　:：-－—–|｜・]+(.+)$" options:0 error:nil];
    NSTextCheckingResult *m = [withSep firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (m && m.numberOfRanges >= 2) return YTNicoUIScrapeTrim([line substringWithRange:[m rangeAtIndex:1]]);

    // Handles in YouTube can be Japanese and sometimes get concatenated with body.
    // If a sentence-looking part starts after the handle, keep it.
    NSArray<NSString *> *sentenceMarks = @[@"楽", @"嬉", @"待", @"来", @"行", @"や", @"わ", @"す", @"こ", @"つ", @"久", @"立", @"キ", @"！", @"？", @"ー", @"〜", @"～"];
    for (NSString *mark in sentenceMarks) {
        NSRange r = [line rangeOfString:mark options:0 range:NSMakeRange(1, line.length - 1)];
        if (r.location != NSNotFound && r.location > 2) {
            NSString *rest = [line substringFromIndex:r.location];
            if (rest.length >= 1) return YTNicoUIScrapeTrim(rest);
        }
    }

    return @"";
}

static BOOL YTNicoLooksLikeAuthorLine(NSString *line) {
    if (line.length == 0 || line.length > 46) return NO;
    if ([line hasPrefix:@"@"]) return YES;
    if ([line rangeOfString:@"。"].location != NSNotFound || [line rangeOfString:@"！"].location != NSNotFound || [line rangeOfString:@"？"].location != NSNotFound) return NO;
    return YES;
}

static NSString *YTNicoUIScrapeCommentBodyOnly(NSString *rawText) {
    NSString *text = YTNicoUIScrapeTrim(rawText);
    if (text.length == 0) return @"";

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *lineRaw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = YTNicoUIScrapeTrim(lineRaw);
        if (line.length == 0) continue;
        line = YTNicoStripLeadingHandleFromLine(line);
        if (line.length == 0) continue;
        if (YTNicoUIScrapeRejectText(line) || YTNicoUIScrapeLooksLikeMetadataOnly(line)) continue;
        [lines addObject:line];
    }

    if (lines.count == 0) return @"";
    if (lines.count >= 3 && YTNicoLooksLikeAuthorLine(lines[0]) && YTNicoLooksLikeAuthorLine(lines[1])) {
        return YTNicoUIScrapeTrim([[lines subarrayWithRange:NSMakeRange(2, lines.count - 2)] componentsJoinedByString:@" "]);
    }
    if (lines.count >= 2 && YTNicoLooksLikeAuthorLine(lines[0])) {
        return YTNicoUIScrapeTrim([[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)] componentsJoinedByString:@" "]);
    }
    return YTNicoUIScrapeTrim([lines componentsJoinedByString:@" "]);
}

static void YTNicoUIScrapePruneSeen(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLastUIScrapePrune < 20.0) return;
    gYTNicoLastUIScrapePrune = now;
    NSMutableArray<NSString *> *remove = [NSMutableArray array];
    for (NSString *key in gYTNicoUIScrapeSeen) {
        if (now - gYTNicoUIScrapeSeen[key].doubleValue > 180.0) [remove addObject:key];
    }
    [gYTNicoUIScrapeSeen removeObjectsForKeys:remove];
    while (gYTNicoUIScrapeRecentTexts.count > 24) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];
}

static void YTNicoUIScrapeEmitText(NSString *rawText, UIView *sourceView) {
    if (!YTNicoUIScrapeIsYouTube() || !gYTNicoUIScrapeEnabled) return;
    if (!SettingsManager.shared.enabled) return;
    if (![sourceView isKindOfClass:UIView.class]) return;
    if (!YTNicoUIScrapeLooksLikeChatHierarchy(sourceView)) return;

    NSString *text = YTNicoUIScrapeCommentBodyOnly(rawText);
    if (YTNicoUIScrapeRejectText(text) || YTNicoUIScrapeLooksLikeMetadataOnly(text)) return;

    if (!gYTNicoUIScrapeSeen) gYTNicoUIScrapeSeen = [NSMutableDictionary dictionary];
    if (!gYTNicoUIScrapeRecentTexts) gYTNicoUIScrapeRecentTexts = [NSMutableArray array];
    YTNicoUIScrapePruneSeen();

    NSString *key = text ?: @"";
    if (gYTNicoUIScrapeSeen[key]) {
        [gYTNicoUIScrapeRecentTexts addObject:text];
        while (gYTNicoUIScrapeRecentTexts.count > 24) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];
        return;
    }
    gYTNicoUIScrapeSeen[key] = @(CACurrentMediaTime());
    [gYTNicoUIScrapeRecentTexts addObject:text];
    while (gYTNicoUIScrapeRecentTexts.count > 24) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];

    NSString *mid = [NSString stringWithFormat:@"ui-%lu-%llu", (unsigned long)[key hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:@"" text:text messageId:mid];

    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLastUIScrapeLog > 1.0) {
        gYTNicoLastUIScrapeLog = now;
        [[DebugInspector shared] important:@"UI scrape emitted body=%@ path=%@", text ?: @"", YTNicoUIScrapeClassPath(sourceView, 6)];
    }
}

%hook UILabel

- (void)setText:(NSString *)text {
    %orig(text);
    if (text.length > 0) YTNicoUIScrapeEmitText(text, self);
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    %orig(attributedText);
    NSString *text = attributedText.string ?: @"";
    if (text.length > 0) YTNicoUIScrapeEmitText(text, self);
}

- (void)didMoveToWindow {
    %orig;
    NSString *text = self.text ?: self.attributedText.string ?: @"";
    if (text.length > 0) YTNicoUIScrapeEmitText(text, self);
}

%end

%hook ASTextNode

- (void)setAttributedText:(NSAttributedString *)attributedText {
    %orig(attributedText);
    NSString *text = attributedText.string ?: @"";
    UIView *view = YTNicoViewFromNode((id)self);
    if (text.length > 0 && view) YTNicoUIScrapeEmitText(text, view);
}

%end

%hook ASDisplayNode

- (void)didEnterVisibleState {
    %orig;
    id node = (id)self;
    UIView *view = YTNicoViewFromNode(node);
    if (!view) return;
    NSString *className = NSStringFromClass(object_getClass(node));
    if (!YTNicoUIScrapeContainsAny(className, @[@"text", @"label", @"message", @"chat", @"comment"])) return;
    NSAttributedString *attr = YTNicoAttributedTextFromNode(node);
    NSString *desc = attr.string ?: @"";
    if (desc.length > 0) YTNicoUIScrapeEmitText(desc, view);
}

%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!YTNicoUIScrapeIsYouTube()) return;
        gYTNicoUIScrapeSeen = [NSMutableDictionary dictionary];
        gYTNicoUIScrapeRecentTexts = [NSMutableArray array];
        [[DebugInspector shared] important:@"UI chat scrape fallback loaded balanced body-only mode"];
    });
}

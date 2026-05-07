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

static BOOL YTNicoUIScrapeLooksLikeChatHierarchy(UIView *view) {
    NSString *path = YTNicoUIScrapeClassPath(view, 14);
    if (YTNicoUIScrapeContainsAny(path, @[@"livechat", @"live_chat", @"ytlive", @"chat", @"replay", @"conversation", @"message", @"comment"])) return YES;
    if (YTNicoUIScrapeContainsAny(path, @[@"table", @"collection", @"asdisplay", @"cell", @"renderer"]) &&
        YTNicoUIScrapeContainsAny(path, @[@"yt", @"youtube", @"watch"])) return YES;
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
    return NO;
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

static NSString *YTNicoUIScrapeAuthorCandidate(void) {
    for (NSInteger i = (NSInteger)gYTNicoUIScrapeRecentTexts.count - 1; i >= 0; i--) {
        NSString *t = gYTNicoUIScrapeRecentTexts[(NSUInteger)i];
        if (t.length == 0 || t.length > 42) continue;
        if (YTNicoUIScrapeRejectText(t) || YTNicoUIScrapeLooksLikeMetadataOnly(t)) continue;
        if ([t rangeOfString:@"。"].location != NSNotFound || [t rangeOfString:@"！"].location != NSNotFound || [t rangeOfString:@"？"].location != NSNotFound) continue;
        return t;
    }
    return @"chat";
}

static void YTNicoUIScrapeEmitText(NSString *rawText, UIView *sourceView) {
    if (!YTNicoUIScrapeIsYouTube() || !gYTNicoUIScrapeEnabled) return;
    if (!SettingsManager.shared.enabled) return;
    if (![sourceView isKindOfClass:UIView.class]) return;
    NSString *text = YTNicoUIScrapeTrim(rawText);
    if (YTNicoUIScrapeRejectText(text) || YTNicoUIScrapeLooksLikeMetadataOnly(text)) return;
    if (!YTNicoUIScrapeLooksLikeChatHierarchy(sourceView)) return;

    if (!gYTNicoUIScrapeSeen) gYTNicoUIScrapeSeen = [NSMutableDictionary dictionary];
    if (!gYTNicoUIScrapeRecentTexts) gYTNicoUIScrapeRecentTexts = [NSMutableArray array];
    YTNicoUIScrapePruneSeen();

    NSString *author = YTNicoUIScrapeAuthorCandidate();
    NSString *key = [NSString stringWithFormat:@"%@|%@", author ?: @"", text ?: @""];
    if (gYTNicoUIScrapeSeen[key]) {
        [gYTNicoUIScrapeRecentTexts addObject:text];
        while (gYTNicoUIScrapeRecentTexts.count > 24) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];
        return;
    }
    gYTNicoUIScrapeSeen[key] = @(CACurrentMediaTime());
    [gYTNicoUIScrapeRecentTexts addObject:text];
    while (gYTNicoUIScrapeRecentTexts.count > 24) [gYTNicoUIScrapeRecentTexts removeObjectAtIndex:0];

    NSString *mid = [NSString stringWithFormat:@"ui-%lu-%llu", (unsigned long)[key hash], (unsigned long long)(CACurrentMediaTime() * 1000.0)];
    [YouTubeChatAdapter emitNowAuthor:author.length ? author : @"chat" text:text messageId:mid];

    CFTimeInterval now = CACurrentMediaTime();
    if (now - gYTNicoLastUIScrapeLog > 1.0) {
        gYTNicoLastUIScrapeLog = now;
        [[DebugInspector shared] important:@"UI scrape emitted author=%@ text=%@ path=%@", author ?: @"", text ?: @"", YTNicoUIScrapeClassPath(sourceView, 6)];
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
        [[DebugInspector shared] important:@"UI chat scrape fallback loaded"];
    });
}

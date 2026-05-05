#import "YouTubeChatAdapter.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"
#import "DebugInspector.h"
#import <WebKit/WebKit.h>

@interface YouTubeChatAdapter ()
@property (nonatomic, weak) UIView *root;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) NSTimer *mockTimer;
@property (nonatomic, strong) NicoMessageLRUCache *cache;
@end

@implementation YouTubeChatAdapter

- (instancetype)init {
    if ((self = [super init])) {
        _cache = [[NicoMessageLRUCache alloc] initWithCapacity:1600];
    }
    return self;
}

- (void)startObservingInRootView:(UIView *)rootView {
    if (self.root == rootView && self.pollTimer) {
        [self refreshMockTimer];
        return;
    }
    self.root = rootView;
    [self stopObserving];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(scanTree) userInfo:nil repeats:YES];
    [self refreshMockTimer];
    [self scanTree];
}

- (void)refreshMockTimer {
    BOOL wantsMock = [SettingsManager shared].mockMode;
    if (wantsMock && !self.mockTimer) {
        self.mockTimer = [NSTimer scheduledTimerWithTimeInterval:1.4 target:self selector:@selector(emitMock) userInfo:nil repeats:YES];
    } else if (!wantsMock && self.mockTimer) {
        [self.mockTimer invalidate];
        self.mockTimer = nil;
    }
}

- (void)stopObserving {
    [self.pollTimer invalidate]; self.pollTimer = nil;
    [self.mockTimer invalidate]; self.mockTimer = nil;
}

- (void)scanTree {
    UIView *root = self.root;
    if (!root || root.hidden || root.alpha < 0.05) return;

    NSArray<NSDictionary *> *items = [self visibleTextItemsInView:root limit:320 allowPlayerArea:NO];
    if (items.count == 0) return;

    BOOL hasCommentUI = NO;
    for (NSDictionary *item in items) {
        NSString *text = item[@"text"];
        if ([self isCommentRegionHeader:text]) {
            hasCommentUI = YES;
            break;
        }
    }
    if (!hasCommentUI) {
        [[DebugInspector shared] log:@"No visible comments/chat header"];
        return;
    }

    [[DebugInspector shared] log:@"Visible text items=%lu", (unsigned long)items.count];
    [self parseVisibleTextItems:items];
}

#pragma mark - Visible text collection

- (NSArray<NSDictionary *> *)visibleTextItemsInView:(UIView *)view limit:(NSInteger)limit allowPlayerArea:(BOOL)allowPlayerArea {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    [self collectTextItemsFromView:view into:items limit:limit depth:0 allowPlayerArea:allowPlayerArea];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 4.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue];
        CGFloat bx = [b[@"x"] doubleValue];
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return items;
}

- (void)collectTextItemsFromView:(UIView *)view
                            into:(NSMutableArray<NSDictionary *> *)items
                           limit:(NSInteger)limit
                           depth:(NSInteger)depth
                 allowPlayerArea:(BOOL)allowPlayerArea {
    if (!view || depth > 9 || items.count >= limit || view.hidden || view.alpha < 0.05) return;
    if (!allowPlayerArea && [self isInsidePlayerArea:view]) return;

    NSMutableArray<NSString *> *texts = [NSMutableArray array];

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        [self addText:label.text toArray:texts];
        [self addText:label.attributedText.string toArray:texts];
    }

    if (![view isKindOfClass:UIControl.class]) {
        [self addText:view.accessibilityLabel toArray:texts];
        [self addText:view.accessibilityValue toArray:texts];
    }

    if ([view isKindOfClass:WKWebView.class]) {
        [self extractMessagesFromWebView:(WKWebView *)view];
    }

    if (texts.count > 0) {
        CGRect rect = [view convertRect:view.bounds toView:nil];
        for (NSString *raw in texts) {
            NSArray<NSString *> *split = [self splitRawText:raw];
            for (NSString *part in split) {
                NSString *clean = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (clean.length == 0 || clean.length > 260) continue;
                if ([self isLikelyPlayerChromeText:clean]) continue;
                NSDictionary *item = @{@"text": clean,
                                       @"x": @(CGRectGetMinX(rect)),
                                       @"y": @(CGRectGetMinY(rect)),
                                       @"class": NSStringFromClass(view.class)};
                if (![items containsObject:item]) [items addObject:item];
                if (items.count >= limit) break;
            }
            if (items.count >= limit) break;
        }
    }

    for (UIView *subview in view.subviews) {
        [self collectTextItemsFromView:subview into:items limit:limit depth:depth + 1 allowPlayerArea:allowPlayerArea];
        if (items.count >= limit) break;
    }
}

- (void)addText:(NSString *)text toArray:(NSMutableArray<NSString *> *)array {
    if (![text isKindOfClass:NSString.class]) return;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return;
    if (![array containsObject:trimmed]) [array addObject:trimmed];
}

- (NSArray<NSString *> *)splitRawText:(NSString *)raw {
    if (raw.length == 0) return @[];
    NSString *normalized = [raw stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0 && ![result containsObject:trimmed]) [result addObject:trimmed];
    }
    return result;
}

#pragma mark - Parsing

- (void)parseVisibleTextItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *text = item[@"text"];
        if (text.length == 0) continue;
        if ([texts containsObject:text]) continue;
        [texts addObject:text];
    }

    for (NSInteger i = 0; i < texts.count; i++) {
        NSString *line = texts[i];
        if ([self parsePotentialInlineMessage:line]) continue;

        NSString *author = [self cleanAuthorFromCandidate:line];
        if (![self looksLikeAuthor:author]) continue;

        NSString *body = nil;
        for (NSInteger j = i + 1; j < MIN((NSInteger)texts.count, i + 6); j++) {
            NSString *candidate = texts[j];
            if ([self isCommentRegionHeader:candidate]) continue;
            if ([self shouldIgnoreText:candidate]) continue;
            if ([self isTimeOrActionText:candidate]) continue;
            if ([self looksLikeAuthor:[self cleanAuthorFromCandidate:candidate]]) break;
            if (![self looksLikeMessageBody:candidate]) continue;
            body = candidate;
            break;
        }

        if (body.length > 0) {
            [self emitAuthor:author text:body];
        }
    }
}

- (NSString *)cleanAuthorFromCandidate:(NSString *)candidate {
    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *separators = @[@"・", @"•", @"·", @" ･ ", @" - "];
    for (NSString *sep in separators) {
        NSRange r = [trimmed rangeOfString:sep];
        if (r.location != NSNotFound && r.location > 0) {
            trimmed = [[trimmed substringToIndex:r.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            break;
        }
    }
    return trimmed;
}

- (BOOL)parsePotentialInlineMessage:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || [self shouldIgnoreText:trimmed]) return NO;

    NSArray<NSString *> *separators = @[@"：", @":"];
    for (NSString *separator in separators) {
        NSRange range = [trimmed rangeOfString:separator];
        if (range.location == NSNotFound || range.location == 0) continue;
        NSString *author = [self cleanAuthorFromCandidate:[trimmed substringToIndex:range.location]];
        NSString *body = [[trimmed substringFromIndex:range.location + separator.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![self looksLikeAuthor:author] || ![self looksLikeMessageBody:body]) continue;
        [self emitAuthor:author text:body];
        return YES;
    }
    return NO;
}

#pragma mark - Filtering

- (BOOL)isCommentRegionHeader:(NSString *)text {
    NSString *lower = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSArray<NSString *> *headers = @[@"コメント", @"返信", @"ライブ チャット", @"ライブチャット", @"上位チャット", @"チャット", @"chat replay", @"comments", @"replies", @"reply", @"live chat", @"top chat"];
    for (NSString *h in headers) {
        NSString *hl = h.lowercaseString;
        if ([lower isEqualToString:hl] || [lower hasPrefix:hl]) return YES;
    }
    return NO;
}

- (BOOL)looksLikeAuthor:(NSString *)author {
    NSString *trimmed = [author stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 80) return NO;
    if ([self shouldIgnoreText:trimmed]) return NO;
    if ([trimmed hasPrefix:@"@"] && trimmed.length >= 2) return YES;
    if ([self isTimeOrActionText:trimmed]) return NO;
    if ([trimmed containsString:@"http://"] || [trimmed containsString:@"https://"]) return NO;
    return trimmed.length <= 48;
}

- (BOOL)looksLikeMessageBody:(NSString *)body {
    NSString *trimmed = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 360) return NO;
    if ([self shouldIgnoreText:trimmed]) return NO;
    if ([self isTimeOrActionText:trimmed]) return NO;
    if ([self isCommentRegionHeader:trimmed]) return NO;
    if ([trimmed hasPrefix:@"@"] && trimmed.length < 80) return NO;
    return YES;
}

- (BOOL)shouldIgnoreText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;

    for (NSString *blocked in [SettingsManager shared].blockWords) {
        if (blocked.length > 0 && [trimmed rangeOfString:blocked options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }

    NSString *lower = trimmed.lowercaseString;
    NSSet<NSString *> *exactUI = [NSSet setWithArray:@[@"高評価", @"低評価", @"共有", @"保存", @"オフライン", @"チャンネル登録", @"その他", @"キャンセル", @"送信", @"並べ替え", @"コメントを追加", @"コメントする", @"続きを読む", @"もっと見る", @"翻訳"]];
    if ([exactUI containsObject:lower]) return YES;

    NSArray<NSString *> *uiFragments = @[@"回視聴", @"人が視聴中", @"チャンネル登録者", @"www.youtube.com", @"youtube.com/", @"字幕", @"cc"];
    for (NSString *fragment in uiFragments) {
        if ([lower containsString:fragment.lowercaseString]) return YES;
    }
    return NO;
}

- (BOOL)isLikelyPlayerChromeText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;
    NSString *lower = trimmed.lowercaseString;
    NSArray<NSString *> *chrome = @[@"再生", @"一時停止", @"全画面", @"ミュート", @"字幕", @"画質", @"設定", @"pause", @"play", @"fullscreen", @"captions", @"quality", @"settings"];
    for (NSString *c in chrome) if ([lower containsString:c.lowercaseString]) return YES;
    return NO;
}

- (BOOL)isTimeOrActionText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;
    NSString *lower = trimmed.lowercaseString;

    NSArray<NSString *> *exact = @[@"返信", @"replies", @"reply", @"表示", @"もっと見る", @"続きを読む", @"翻訳", @"translate"];
    for (NSString *s in exact) if ([lower isEqualToString:s]) return YES;

    NSArray<NSString *> *suffixes = @[@"秒前", @"分前", @"時間前", @"日前", @"週間前", @"か月前", @"ヶ月前", @"年前", @"seconds ago", @"minutes ago", @"hours ago", @"days ago", @"weeks ago", @"months ago", @"years ago"];
    for (NSString *suffix in suffixes) if ([lower hasSuffix:suffix]) return YES;

    NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}:\\d{2}(:\\d{2})?$" options:0 error:nil];
    if ([timeRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0) return YES;

    NSRegularExpression *countRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億kKmM]+$" options:0 error:nil];
    if ([countRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0) return YES;
    return NO;
}

- (BOOL)isInsidePlayerArea:(UIView *)view {
    CGRect rect = [view convertRect:view.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);
    BOOL portraitPlayer = (rect.origin.y < screen.height * 0.43 && rect.size.width >= screen.width * 0.65 && ratio > 1.25 && ratio < 2.6 && rect.size.height <= screen.height * 0.55);
    BOOL fullscreenPlayer = (rect.size.width >= screen.width * 0.92 && rect.size.height >= screen.height * 0.70 && ratio > 1.2);
    return portraitPlayer || fullscreenPlayer;
}

#pragma mark - WebView

- (void)extractMessagesFromWebView:(WKWebView *)webView {
    if ([self isInsidePlayerArea:webView]) return;
    NSString *script = @"(function(){var text=document.body?document.body.innerText:''; if(!text){return [];} return text.split('\\n').map(function(x){return x.trim();}).filter(Boolean).slice(-80);})();";
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (![result isKindOfClass:NSArray.class]) return;
        NSMutableArray *items = [NSMutableArray array];
        NSInteger y = 0;
        for (id item in (NSArray *)result) {
            if ([item isKindOfClass:NSString.class]) {
                [items addObject:@{@"text": item, @"x": @0, @"y": @(y++), @"class": @"WKWebView"}];
            }
        }
        [self parseVisibleTextItems:items];
    }];
}

#pragma mark - Emit

- (void)emitAuthor:(NSString *)author text:(NSString *)text {
    if (![SettingsManager shared].enabled) return;
    NSString *a = author ?: @"";
    NSString *t = text ?: @"";
    if (t.length == 0) return;
    NSString *line = [NSString stringWithFormat:@"%@|%@", a, t];
    NSString *mid = [NSString stringWithFormat:@"%lu", (unsigned long)line.hash];
    if ([self.cache containsMessageId:mid]) return;
    [self.cache addMessageId:mid];
    [[DebugInspector shared] log:@"emit comment author=%@ text=%@", a, t];
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:mid authorName:a text:t timestamp:NSDate.date];
    [self.delegate chatAdapterDidReceiveMessage:msg];
}

- (void)emitMock {
    if (![SettingsManager shared].mockMode) return;
    NSArray *samples = @[@"テストコメント", @"ライブありがとう！", @"888888", @"初見です", @"ナイス配信"];
    NSString *text = samples[arc4random_uniform((uint32_t)samples.count)];
    NSString *mid = [NSUUID UUID].UUIDString;
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:mid authorName:@"mock" text:text timestamp:NSDate.date];
    [self.delegate chatAdapterDidReceiveMessage:msg];
}
@end

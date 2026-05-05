#import "YouTubeChatAdapter.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"
#import "DebugInspector.h"
#import <UIKit/UIKit.h>
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
        _cache = [[NicoMessageLRUCache alloc] initWithCapacity:2400];
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
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.75 target:self selector:@selector(scanTree) userInfo:nil repeats:YES];
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

    NSArray<NSDictionary *> *items = [self visibleTextItemsInView:root limit:700 allowPlayerArea:NO];
    if (items.count == 0) return;

    BOOL hasCommentUI = NO;
    NSInteger authorLikeCount = 0;
    for (NSDictionary *item in items) {
        NSString *text = item[@"text"];
        if ([self isCommentRegionHeader:text]) hasCommentUI = YES;
        if ([self looksLikeAuthor:[self cleanAuthorFromCandidate:text]]) authorLikeCount++;
        if ([self textContainsAuthorToken:text]) authorLikeCount++;
    }

    // Usually require a visible comments/chat header. If YouTube hides the exact header
    // but multiple @ handles are visible, still parse aggressively.
    if (!hasCommentUI && authorLikeCount < 2) {
        [[DebugInspector shared] log:@"No visible comments/chat header or author rows"];
        return;
    }

    [[DebugInspector shared] log:@"Visible text items=%lu authorLike=%ld", (unsigned long)items.count, (long)authorLikeCount];
    [self parseCompactLinesFromItems:items];
    [self parseRowsFromItems:items];
    [self parseSequentialTextItems:items];
}

#pragma mark - Visible text collection

- (NSArray<NSDictionary *> *)visibleTextItemsInView:(UIView *)view limit:(NSInteger)limit allowPlayerArea:(BOOL)allowPlayerArea {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    [self collectTextItemsFromView:view into:items limit:limit depth:0 allowPlayerArea:allowPlayerArea];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 5.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
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
    if (!view || depth > 11 || items.count >= limit || view.hidden || view.alpha < 0.05) return;
    if (!allowPlayerArea && [self isInsidePlayerArea:view]) return;

    NSMutableArray<NSString *> *texts = [NSMutableArray array];

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        [self addText:label.text toArray:texts];
        [self addText:label.attributedText.string toArray:texts];
    }

    // YouTube often exposes chat/comment text only via accessibility.
    [self addText:view.accessibilityLabel toArray:texts];
    [self addText:view.accessibilityValue toArray:texts];

    if (texts.count > 0) {
        CGRect rect = [view convertRect:view.bounds toView:nil];
        [self addTextArray:texts frame:rect className:NSStringFromClass(view.class) into:items limit:limit];
    }

    NSArray *accessibilityElements = view.accessibilityElements;
    if ([accessibilityElements isKindOfClass:NSArray.class]) {
        for (id element in accessibilityElements) {
            if (items.count >= limit) break;
            if ([element isKindOfClass:UIView.class]) {
                [self collectTextItemsFromView:(UIView *)element into:items limit:limit depth:depth + 1 allowPlayerArea:allowPlayerArea];
                continue;
            }

            NSMutableArray<NSString *> *elementTexts = [NSMutableArray array];
            if ([element respondsToSelector:@selector(accessibilityLabel)]) {
                id label = [element accessibilityLabel];
                if ([label isKindOfClass:NSString.class]) [self addText:label toArray:elementTexts];
            }
            if ([element respondsToSelector:@selector(accessibilityValue)]) {
                id value = [element accessibilityValue];
                if ([value isKindOfClass:NSString.class]) [self addText:value toArray:elementTexts];
            }
            if (elementTexts.count > 0) {
                CGRect frame = CGRectZero;
                if ([element respondsToSelector:@selector(accessibilityFrame)]) frame = [element accessibilityFrame];
                [self addTextArray:elementTexts frame:frame className:NSStringFromClass([element class]) into:items limit:limit];
            }
        }
    }

    if ([view isKindOfClass:WKWebView.class]) {
        [self extractMessagesFromWebView:(WKWebView *)view];
    }

    for (UIView *subview in view.subviews) {
        [self collectTextItemsFromView:subview into:items limit:limit depth:depth + 1 allowPlayerArea:allowPlayerArea];
        if (items.count >= limit) break;
    }
}

- (void)addTextArray:(NSArray<NSString *> *)texts frame:(CGRect)rect className:(NSString *)className into:(NSMutableArray<NSDictionary *> *)items limit:(NSInteger)limit {
    for (NSString *raw in texts) {
        for (NSString *part in [self splitRawText:raw]) {
            NSString *clean = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (clean.length == 0 || clean.length > 420) continue;
            if ([self isLikelyPlayerChromeText:clean]) continue;
            NSDictionary *item = @{@"text": clean,
                                   @"x": @(CGRectGetMinX(rect)),
                                   @"y": @(CGRectGetMinY(rect)),
                                   @"class": className ?: @""};
            if (![items containsObject:item]) [items addObject:item];
            if (items.count >= limit) return;
        }
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
    normalized = [normalized stringByReplacingOccurrencesOfString:@"\t" withString:@"\n"];
    NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0 && ![result containsObject:trimmed]) [result addObject:trimmed];
    }
    return result;
}

#pragma mark - Parsing

- (void)parseCompactLinesFromItems:(NSArray<NSDictionary *> *)items {
    for (NSDictionary *item in items) {
        NSString *text = item[@"text"];
        [self parsePotentialCompactLine:text];
    }
}

- (BOOL)parsePotentialCompactLine:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self textContainsAuthorToken:trimmed]) return NO;
    if ([self shouldIgnoreText:trimmed]) return NO;

    NSArray<NSString *> *tokens = [self whitespaceTokens:trimmed];
    NSInteger atIndex = NSNotFound;
    for (NSInteger i = 0; i < tokens.count; i++) {
        if ([tokens[i] hasPrefix:@"@"] && tokens[i].length >= 2) {
            atIndex = i;
            break;
        }
    }
    if (atIndex == NSNotFound) return NO;

    NSMutableArray<NSString *> *authorParts = [NSMutableArray array];
    NSMutableArray<NSString *> *bodyParts = [NSMutableArray array];
    BOOL bodyStarted = NO;

    for (NSInteger i = atIndex; i < tokens.count; i++) {
        NSString *token = tokens[i];
        if (!bodyStarted) {
            if ([self isBadgeOrRankText:token] || [self isTimeOrActionText:token]) {
                bodyStarted = YES;
                continue;
            }
            if (authorParts.count >= 3) {
                bodyStarted = YES;
            } else {
                [authorParts addObject:token];
                continue;
            }
        }
        if ([self isBadgeOrRankText:token] || [self isTimeOrActionText:token] || [self shouldIgnoreText:token]) continue;
        [bodyParts addObject:token];
    }

    if (authorParts.count == 0 || bodyParts.count == 0) return NO;
    NSString *author = [self cleanAuthorFromCandidate:[authorParts componentsJoinedByString:@" "]];
    NSString *body = [bodyParts componentsJoinedByString:@" "];
    if (![self looksLikeAuthor:author] || ![self looksLikeMessageBody:body]) return NO;
    [self emitAuthor:author text:body];
    return YES;
}

- (NSArray<NSString *> *)whitespaceTokens:(NSString *)text {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSString *part in [text componentsSeparatedByCharactersInSet:ws]) {
        NSString *t = [part stringByTrimmingCharactersInSet:ws];
        if (t.length > 0) [tokens addObject:t];
    }
    return tokens;
}

- (BOOL)textContainsAuthorToken:(NSString *)text {
    if (text.length == 0) return NO;
    for (NSString *token in [self whitespaceTokens:text]) {
        if ([token hasPrefix:@"@"] && token.length >= 2) return YES;
    }
    return [text hasPrefix:@"@"]; 
}

- (void)parseRowsFromItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSArray<NSDictionary *> *> *rows = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *current = [NSMutableArray array];
    CGFloat currentY = CGFLOAT_MAX;

    for (NSDictionary *item in items) {
        CGFloat y = [item[@"y"] doubleValue];
        if (current.count == 0 || fabs(y - currentY) <= 28.0) {
            [current addObject:item];
            if (currentY == CGFLOAT_MAX) currentY = y;
        } else {
            [rows addObject:[current copy]];
            current = [NSMutableArray arrayWithObject:item];
            currentY = y;
        }
    }
    if (current.count > 0) [rows addObject:[current copy]];

    for (NSArray<NSDictionary *> *row in rows) {
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        for (NSDictionary *item in row) {
            NSString *text = item[@"text"];
            if (text.length > 0 && ![texts containsObject:text]) [texts addObject:text];
        }
        [self parsePotentialRowTexts:texts];
    }
}

- (void)parsePotentialRowTexts:(NSArray<NSString *> *)texts {
    if (texts.count < 2) return;

    NSString *author = nil;
    NSInteger authorIndex = NSNotFound;
    for (NSInteger i = 0; i < texts.count; i++) {
        NSString *candidate = [self cleanAuthorFromCandidate:texts[i]];
        if ([self looksLikeAuthor:candidate]) {
            author = candidate;
            authorIndex = i;
            break;
        }
    }
    if (!author || authorIndex == NSNotFound) return;

    NSMutableArray<NSString *> *bodyParts = [NSMutableArray array];
    for (NSInteger i = authorIndex + 1; i < texts.count; i++) {
        NSString *candidate = texts[i];
        if ([self isBadgeOrRankText:candidate]) continue;
        if ([self isCommentRegionHeader:candidate]) continue;
        if ([self shouldIgnoreText:candidate]) continue;
        if ([self isTimeOrActionText:candidate]) continue;
        NSString *maybeAuthor = [self cleanAuthorFromCandidate:candidate];
        if ([self looksLikeAuthor:maybeAuthor]) break;
        if ([self looksLikeMessageBody:candidate]) [bodyParts addObject:candidate];
    }

    if (bodyParts.count > 0) {
        NSString *body = [bodyParts componentsJoinedByString:@" "];
        [self emitAuthor:author text:body];
    }
}

- (void)parseSequentialTextItems:(NSArray<NSDictionary *> *)items {
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
        if ([self parsePotentialCompactLine:line]) continue;

        NSString *author = [self cleanAuthorFromCandidate:line];
        if (![self looksLikeAuthor:author]) continue;

        NSString *body = nil;
        for (NSInteger j = i + 1; j < MIN((NSInteger)texts.count, i + 10); j++) {
            NSString *candidate = texts[j];
            if ([self isBadgeOrRankText:candidate]) continue;
            if ([self isCommentRegionHeader:candidate]) continue;
            if ([self shouldIgnoreText:candidate]) continue;
            if ([self isTimeOrActionText:candidate]) continue;
            if ([self parsePotentialCompactLine:candidate]) break;
            if ([self looksLikeAuthor:[self cleanAuthorFromCandidate:candidate]]) break;
            if (![self looksLikeMessageBody:candidate]) continue;
            body = candidate;
            break;
        }

        if (body.length > 0) [self emitAuthor:author text:body];
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
    if ([self isBadgeOrRankText:trimmed]) return NO;
    if ([trimmed hasPrefix:@"@"] && trimmed.length >= 2) return YES;
    if ([self isTimeOrActionText:trimmed]) return NO;
    if ([trimmed containsString:@"http://"] || [trimmed containsString:@"https://"]) return NO;
    return trimmed.length <= 48;
}

- (BOOL)looksLikeMessageBody:(NSString *)body {
    NSString *trimmed = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 420) return NO;
    if ([self shouldIgnoreText:trimmed]) return NO;
    if ([self isTimeOrActionText:trimmed]) return NO;
    if ([self isBadgeOrRankText:trimmed]) return NO;
    if ([self isCommentRegionHeader:trimmed]) return NO;
    if ([trimmed hasPrefix:@"@"] && trimmed.length < 80) return NO;
    return YES;
}

- (BOOL)isBadgeOrRankText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;
    NSString *upper = trimmed.uppercaseString;
    if ([upper hasSuffix:@"XP"] || [upper containsString:@" XP"]) return YES;
    if ([trimmed hasPrefix:@"#"] && trimmed.length <= 5) return YES;
    if ([trimmed containsString:@"#"] && trimmed.length <= 8) return YES;
    if ([trimmed containsString:@"👑"] || [trimmed containsString:@"♛"] || [trimmed containsString:@"♕"]) return YES;
    return NO;
}

- (BOOL)shouldIgnoreText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;
    if ([self isBadgeOrRankText:trimmed]) return YES;

    for (NSString *blocked in [SettingsManager shared].blockWords) {
        if (blocked.length > 0 && [trimmed rangeOfString:blocked options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }

    NSString *lower = trimmed.lowercaseString;
    NSSet<NSString *> *exactUI = [NSSet setWithArray:@[@"高評価", @"低評価", @"共有", @"保存", @"オフライン", @"チャンネル登録", @"その他", @"キャンセル", @"送信", @"並べ替え", @"コメントを追加", @"コメントする", @"続きを読む", @"もっと見る", @"翻訳", @"詳細"]];
    if ([exactUI containsObject:lower]) return YES;

    NSArray<NSString *> *uiFragments = @[@"回視聴", @"人が視聴中", @"チャンネル登録者", @"www.youtube.com", @"youtube.com/", @"字幕", @"cc", @"チャンネル登録者のみモード"];
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
    NSString *script = @"(function(){var text=document.body?document.body.innerText:''; if(!text){return [];} return text.split('\\n').map(function(x){return x.trim();}).filter(Boolean).slice(-120);})();";
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (![result isKindOfClass:NSArray.class]) return;
        NSMutableArray *items = [NSMutableArray array];
        NSInteger y = 0;
        for (id item in (NSArray *)result) {
            if ([item isKindOfClass:NSString.class]) {
                [items addObject:@{@"text": item, @"x": @0, @"y": @(y++), @"class": @"WKWebView"}];
            }
        }
        [self parseCompactLinesFromItems:items];
        [self parseRowsFromItems:items];
        [self parseSequentialTextItems:items];
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

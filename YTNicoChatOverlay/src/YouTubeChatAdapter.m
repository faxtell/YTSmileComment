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
        _cache = [[NicoMessageLRUCache alloc] initWithCapacity:1200];
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

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.25
                                                      target:self
                                                    selector:@selector(scanTree)
                                                    userInfo:nil
                                                     repeats:YES];
    [self refreshMockTimer];
    [self scanTree];
}

- (void)refreshMockTimer {
    BOOL wantsMock = [SettingsManager shared].mockMode;
    if (wantsMock && !self.mockTimer) {
        self.mockTimer = [NSTimer scheduledTimerWithTimeInterval:1.4
                                                          target:self
                                                        selector:@selector(emitMock)
                                                        userInfo:nil
                                                         repeats:YES];
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
    [[DebugInspector shared] log:@"scanTree start"];

    NSArray<UIView *> *regions = [self commentRegionsInView:root];
    if (regions.count == 0) {
        [[DebugInspector shared] log:@"No comment/chat region found"];
        return;
    }

    for (UIView *region in regions) {
        [self scanMessageContainersInRegion:region depth:0];
    }
}

#pragma mark - Region detection

- (NSArray<UIView *> *)commentRegionsInView:(UIView *)root {
    NSMutableArray<UIView *> *regions = [NSMutableArray array];
    [self collectCommentRegionsFromView:root into:regions depth:0];
    return [self deduplicatedRegions:regions];
}

- (void)collectCommentRegionsFromView:(UIView *)view into:(NSMutableArray<UIView *> *)regions depth:(NSInteger)depth {
    if (!view || depth > 8 || view.hidden || view.alpha < 0.05) return;

    if ([self isLikelyCommentRegion:view]) {
        [regions addObject:view];
        // Do not return. Nested sheets/cells can contain a better scrolling container.
    }

    for (UIView *subview in view.subviews) {
        [self collectCommentRegionsFromView:subview into:regions depth:depth + 1];
    }
}

- (NSArray<UIView *> *)deduplicatedRegions:(NSArray<UIView *> *)regions {
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    for (UIView *candidate in regions) {
        BOOL isInsideExisting = NO;
        for (UIView *existing in result) {
            if ([candidate isDescendantOfView:existing]) {
                isInsideExisting = YES;
                break;
            }
        }
        if (!isInsideExisting) [result addObject:candidate];
    }
    return result;
}

- (BOOL)isLikelyCommentRegion:(UIView *)view {
    if (!view || view.bounds.size.width < 180.0 || view.bounds.size.height < 80.0) return NO;
    if ([self isInsidePlayerArea:view]) return NO;

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    BOOL classHint = ([className containsString:@"comment"] ||
                      [className containsString:@"comments"] ||
                      [className containsString:@"reply"] ||
                      [className containsString:@"chat"] ||
                      [className containsString:@"engagement"] ||
                      [className containsString:@"sheet"] ||
                      [className containsString:@"collection"] ||
                      [className containsString:@"table"] ||
                      [className containsString:@"scroll"]);

    NSArray<NSString *> *texts = [self visibleLabelTextsInView:view limit:16 allowPlayerArea:NO];
    NSInteger headerHits = 0;
    NSInteger messageLike = 0;
    for (NSString *text in texts) {
        if ([self isCommentRegionHeader:text]) headerHits++;
        if (![self shouldIgnoreText:text] && ![self isTimeOrActionText:text]) messageLike++;
    }

    if (headerHits > 0 && messageLike >= 1) return YES;
    if (classHint && messageLike >= 2) return YES;
    return NO;
}

- (BOOL)isCommentRegionHeader:(NSString *)text {
    NSString *lower = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSArray<NSString *> *headers = @[
        @"コメント", @"返信", @"ライブ チャット", @"ライブチャット", @"上位チャット", @"チャット",
        @"comments", @"replies", @"reply", @"live chat", @"top chat", @"chat replay"
    ];
    for (NSString *h in headers) {
        if ([lower isEqualToString:h.lowercaseString] || [lower hasPrefix:h.lowercaseString]) return YES;
    }
    return NO;
}

- (BOOL)isInsidePlayerArea:(UIView *)view {
    CGRect rect = [view convertRect:view.bounds toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat ratio = rect.size.width / MAX(rect.size.height, 1.0);

    BOOL topVideoLike = (rect.origin.y < screen.height * 0.45 &&
                         rect.size.width >= screen.width * 0.65 &&
                         ratio > 1.25 && ratio < 2.5 &&
                         rect.size.height <= screen.height * 0.55);
    BOOL fullscreenVideoLike = (rect.size.width >= screen.width * 0.85 &&
                                rect.size.height >= screen.height * 0.55 &&
                                ratio > 1.25);
    return topVideoLike || fullscreenVideoLike;
}

#pragma mark - Message scanning

- (void)scanMessageContainersInRegion:(UIView *)region depth:(NSInteger)depth {
    if (!region || depth > 9 || region.hidden || region.alpha < 0.05) return;

    if ([region isKindOfClass:WKWebView.class]) {
        [self extractMessagesFromWebView:(WKWebView *)region];
        return;
    }

    if ([self looksLikeMessageContainer:region]) {
        [self tryEmitMessageFromContainer:region];
    }

    for (UIView *subview in region.subviews) {
        [self scanMessageContainersInRegion:subview depth:depth + 1];
    }
}

- (BOOL)looksLikeMessageContainer:(UIView *)view {
    if (!view || view.bounds.size.width < 120.0) return NO;
    if ([self isInsidePlayerArea:view]) return NO;
    CGFloat h = view.bounds.size.height;
    if (h < 28.0 || h > 280.0) return NO;

    NSInteger labelCount = [self countLabelsInView:view limit:12 depth:0];
    if (labelCount < 2 || labelCount > 10) return NO;

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    BOOL classLooksRight = ([className containsString:@"cell"] ||
                            [className containsString:@"comment"] ||
                            [className containsString:@"reply"] ||
                            [className containsString:@"chat"] ||
                            [className containsString:@"message"] ||
                            [className containsString:@"renderer"]);

    NSArray<NSString *> *texts = [self visibleLabelTextsInView:view limit:12 allowPlayerArea:NO];
    NSInteger useful = 0;
    for (NSString *text in texts) {
        if (![self shouldIgnoreText:text] && ![self isTimeOrActionText:text]) useful++;
    }

    return classLooksRight || useful >= 2;
}

- (NSInteger)countLabelsInView:(UIView *)view limit:(NSInteger)limit depth:(NSInteger)depth {
    if (!view || limit <= 0 || depth > 5 || view.hidden || view.alpha < 0.05) return 0;
    NSInteger total = [view isKindOfClass:UILabel.class] ? 1 : 0;
    if (total >= limit) return total;
    for (UIView *subview in view.subviews) {
        total += [self countLabelsInView:subview limit:(limit - total) depth:depth + 1];
        if (total >= limit) break;
    }
    return total;
}

- (void)tryEmitMessageFromContainer:(UIView *)container {
    NSArray<NSString *> *texts = [self visibleLabelTextsInView:container limit:14 allowPlayerArea:NO];
    if (texts.count < 2) return;

    for (NSString *line in texts) {
        if ([self parsePotentialInlineMessage:line]) return;
    }

    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (NSString *text in texts) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) continue;
        if ([self shouldIgnoreText:trimmed]) continue;
        if ([self isTimeOrActionText:trimmed]) continue;
        if ([self isLikelySubtitleLine:trimmed]) continue;
        if (![clean containsObject:trimmed]) [clean addObject:trimmed];
    }

    if (clean.count < 2) return;

    NSString *author = nil;
    NSInteger authorIndex = NSNotFound;
    for (NSInteger i = 0; i < clean.count; i++) {
        NSString *candidate = clean[i];
        if ([self looksLikeAuthor:candidate]) {
            author = candidate;
            authorIndex = i;
            break;
        }
    }
    if (!author || authorIndex == NSNotFound) return;

    NSString *body = nil;
    for (NSInteger i = authorIndex + 1; i < clean.count; i++) {
        NSString *candidate = clean[i];
        if (![self looksLikeMessageBody:candidate]) continue;
        if (!body || candidate.length > body.length) body = candidate;
    }

    if (!body) return;
    [self emitAuthor:author text:body];
}

#pragma mark - Text collection

- (NSArray<NSString *> *)visibleLabelTextsInView:(UIView *)view limit:(NSInteger)limit allowPlayerArea:(BOOL)allowPlayerArea {
    NSMutableArray<NSDictionary *> *infos = [NSMutableArray array];
    [self collectLabelInfosFromView:view into:infos limit:limit depth:0 allowPlayerArea:allowPlayerArea];
    [infos sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        CGFloat ay = [a[@"y"] doubleValue];
        CGFloat by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 3.0) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ax = [a[@"x"] doubleValue];
        CGFloat bx = [b[@"x"] doubleValue];
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSDictionary *info in infos) {
        NSString *text = info[@"text"];
        if (text.length > 0 && ![texts containsObject:text]) [texts addObject:text];
    }
    return texts;
}

- (void)collectLabelInfosFromView:(UIView *)view
                             into:(NSMutableArray<NSDictionary *> *)infos
                            limit:(NSInteger)limit
                            depth:(NSInteger)depth
                  allowPlayerArea:(BOOL)allowPlayerArea {
    if (!view || depth > 6 || infos.count >= limit || view.hidden || view.alpha < 0.05) return;
    if (!allowPlayerArea && [self isInsidePlayerArea:view]) return;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 0 && text.length <= 240 && ![self isLikelySubtitleLine:text]) {
            CGRect rect = [label convertRect:label.bounds toView:nil];
            [infos addObject:@{@"text": text, @"x": @(CGRectGetMinX(rect)), @"y": @(CGRectGetMinY(rect))}];
        }
    }

    for (UIView *subview in view.subviews) {
        [self collectLabelInfosFromView:subview into:infos limit:limit depth:depth + 1 allowPlayerArea:allowPlayerArea];
        if (infos.count >= limit) break;
    }
}

#pragma mark - WebView extraction

- (void)extractMessagesFromWebView:(WKWebView *)webView {
    if ([self isInsidePlayerArea:webView]) return;
    NSString *script = @"(function(){"
                         "var text=document.body?document.body.innerText:'';"
                         "if(!text){return [];}"
                         "return text.split('\\n').map(function(x){return x.trim();}).filter(Boolean).slice(-40);"
                       "})();";
    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (![result isKindOfClass:NSArray.class]) return;
        NSArray *lines = (NSArray *)result;
        for (id item in lines) {
            if ([item isKindOfClass:NSString.class]) {
                [self parsePotentialInlineMessage:(NSString *)item];
            }
        }
    }];
}

#pragma mark - Parsing and filtering

- (BOOL)parsePotentialInlineMessage:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || [self shouldIgnoreText:trimmed] || [self isLikelySubtitleLine:trimmed]) return NO;

    NSArray<NSString *> *separators = @[@"：", @":"];
    for (NSString *separator in separators) {
        NSRange range = [trimmed rangeOfString:separator];
        if (range.location == NSNotFound || range.location == 0) continue;
        NSString *author = [[trimmed substringToIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *body = [[trimmed substringFromIndex:range.location + separator.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![self looksLikeAuthor:author] || ![self looksLikeMessageBody:body]) continue;
        [self emitAuthor:author text:body];
        return YES;
    }
    return NO;
}

- (BOOL)looksLikeAuthor:(NSString *)author {
    NSString *trimmed = [author stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 64) return NO;
    if ([self shouldIgnoreText:trimmed] || [self isTimeOrActionText:trimmed] || [self isLikelySubtitleLine:trimmed]) return NO;
    if ([trimmed containsString:@"http://"] || [trimmed containsString:@"https://"]) return NO;
    return YES;
}

- (BOOL)looksLikeMessageBody:(NSString *)body {
    NSString *trimmed = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 220) return NO;
    if ([self shouldIgnoreText:trimmed] || [self isTimeOrActionText:trimmed] || [self isLikelySubtitleLine:trimmed]) return NO;
    return YES;
}

- (BOOL)shouldIgnoreText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;

    for (NSString *blocked in [SettingsManager shared].blockWords) {
        if (blocked.length > 0 && [trimmed rangeOfString:blocked options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }

    NSString *lower = trimmed.lowercaseString;
    NSSet<NSString *> *exactUI = [NSSet setWithArray:@[
        @"コメント", @"ライブ チャット", @"ライブチャット", @"上位チャット", @"top chat", @"live chat",
        @"高評価", @"低評価", @"共有", @"保存", @"オフライン", @"チャンネル登録", @"その他",
        @"返信", @"キャンセル", @"送信", @"並べ替え", @"コメントを追加", @"コメントする", @"完璧な経歴"
    ]];
    if ([exactUI containsObject:lower]) return YES;

    NSArray<NSString *> *uiFragments = @[@"回視聴", @"人が視聴中", @"チャンネル登録者", @"www.youtube.com", @"youtube.com/", @"字幕", @"cc"];
    for (NSString *fragment in uiFragments) {
        if ([lower containsString:fragment.lowercaseString]) return YES;
    }
    return NO;
}

- (BOOL)isLikelySubtitleLine:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;

    // Subtitles often appear as long sentence-like labels without an author, and
    // are located inside the player area before collection. This extra filter
    // catches common caption fragments that may be copied into parent containers.
    if (trimmed.length >= 22 && ![trimmed hasPrefix:@"@"] && ![trimmed containsString:@"・"] && ![trimmed containsString:@"•"]) {
        NSCharacterSet *punct = [NSCharacterSet characterSetWithCharactersInString:@"。！？.!?、,"];
        if ([trimmed rangeOfCharacterFromSet:punct].location != NSNotFound) return YES;
    }
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

    NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d{1,2}:\\d{2}(:\\d{2})?$"
                                                                               options:0
                                                                                 error:nil];
    if ([timeRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0) return YES;

    NSRegularExpression *countRegex = [NSRegularExpression regularExpressionWithPattern:@"^[0-9,.万億kKmM]+$"
                                                                                options:0
                                                                                  error:nil];
    if ([countRegex numberOfMatchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)] > 0) return YES;
    return NO;
}

#pragma mark - Emit

- (void)emitAuthor:(NSString *)author text:(NSString *)text {
    if (![SettingsManager shared].enabled) return;
    NSString *line = [NSString stringWithFormat:@"%@|%@", author ?: @"", text ?: @""];
    NSString *mid = [NSString stringWithFormat:@"%lu", (unsigned long)line.hash];
    if ([self.cache containsMessageId:mid]) return;
    [self.cache addMessageId:mid];
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:mid authorName:author ?: @"" text:text ?: @"" timestamp:NSDate.date];
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

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
        _cache = [[NicoMessageLRUCache alloc] initWithCapacity:800];
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
    [self scanViewForMessages:root depth:0];
}

#pragma mark - View scanning

- (void)scanViewForMessages:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 9 || view.hidden || view.alpha < 0.05) return;

    if ([view isKindOfClass:WKWebView.class]) {
        [self extractMessagesFromWebView:(WKWebView *)view];
        return;
    }

    if ([self looksLikeMessageContainer:view]) {
        [self tryEmitMessageFromContainer:view];
    }

    for (UIView *subview in view.subviews) {
        [self scanViewForMessages:subview depth:depth + 1];
    }
}

- (BOOL)looksLikeMessageContainer:(UIView *)view {
    if (!view || view.bounds.size.width < 96.0) return NO;
    CGFloat h = view.bounds.size.height;
    if (h < 20.0 || h > 240.0) return NO;

    NSInteger labelCount = [self countLabelsInView:view limit:10 depth:0];
    if (labelCount < 2 || labelCount > 9) return NO;

    NSString *className = NSStringFromClass(view.class).lowercaseString;
    BOOL classLooksRight = ([className containsString:@"cell"] ||
                            [className containsString:@"comment"] ||
                            [className containsString:@"chat"] ||
                            [className containsString:@"message"] ||
                            [className containsString:@"renderer"]);

    NSArray<NSString *> *texts = [self visibleLabelTextsInView:view limit:10];
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
    NSArray<NSString *> *texts = [self visibleLabelTextsInView:container limit:12];
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

- (NSArray<NSString *> *)visibleLabelTextsInView:(UIView *)view limit:(NSInteger)limit {
    NSMutableArray<NSDictionary *> *infos = [NSMutableArray array];
    [self collectLabelInfosFromView:view into:infos limit:limit depth:0];
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
                            depth:(NSInteger)depth {
    if (!view || depth > 6 || infos.count >= limit || view.hidden || view.alpha < 0.05) return;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 0 && text.length <= 240) {
            CGRect rect = [label convertRect:label.bounds toView:nil];
            [infos addObject:@{@"text": text, @"x": @(CGRectGetMinX(rect)), @"y": @(CGRectGetMinY(rect))}];
        }
    }

    for (UIView *subview in view.subviews) {
        [self collectLabelInfosFromView:subview into:infos limit:limit depth:depth + 1];
        if (infos.count >= limit) break;
    }
}

#pragma mark - WebView extraction

- (void)extractMessagesFromWebView:(WKWebView *)webView {
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

#pragma mark - Parsing

- (BOOL)parsePotentialInlineMessage:(NSString *)line {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || [self shouldIgnoreText:trimmed]) return NO;

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
    if ([self shouldIgnoreText:trimmed] || [self isTimeOrActionText:trimmed]) return NO;
    if ([trimmed containsString:@"http://"] || [trimmed containsString:@"https://"]) return NO;
    return YES;
}

- (BOOL)looksLikeMessageBody:(NSString *)body {
    NSString *trimmed = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || trimmed.length > 220) return NO;
    if ([self shouldIgnoreText:trimmed] || [self isTimeOrActionText:trimmed]) return NO;
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
        @"返信", @"キャンセル", @"送信", @"並べ替え", @"コメントを追加", @"コメントする"
    ]];
    if ([exactUI containsObject:lower]) return YES;

    NSArray<NSString *> *uiFragments = @[@"回視聴", @"人が視聴中", @"チャンネル登録者", @"www.youtube.com", @"youtube.com/"];
    for (NSString *fragment in uiFragments) {
        if ([lower containsString:fragment.lowercaseString]) return YES;
    }
    return NO;
}

- (BOOL)isTimeOrActionText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return YES;
    NSString *lower = trimmed.lowercaseString;

    NSArray<NSString *> *exact = @[@"返信", @"replies", @"reply", @"表示", @"もっと見る", @"続きを読む", @"翻訳", @"translate"];
    for (NSString *s in exact) if ([lower isEqualToString:s]) return YES;

    NSArray<NSString *> *suffixes = @[@"秒前", @"分前", @"時間前", @"日前", @"週間前", @"か月前", @"年前", @"seconds ago", @"minutes ago", @"hours ago", @"days ago", @"weeks ago", @"months ago", @"years ago"];
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

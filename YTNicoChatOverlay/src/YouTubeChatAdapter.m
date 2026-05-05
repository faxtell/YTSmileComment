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
- (instancetype)init { if ((self=[super init])) { _cache=[[NicoMessageLRUCache alloc] initWithCapacity:500]; } return self; }
- (void)startObservingInRootView:(UIView *)rootView {
    self.root = rootView;
    [self stopObserving];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(scanTree) userInfo:nil repeats:YES];
    if ([SettingsManager shared].mockMode && [SettingsManager shared].debugLogging) {
        self.mockTimer = [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(emitMock) userInfo:nil repeats:YES];
    }
}
- (void)stopObserving { [self.pollTimer invalidate]; self.pollTimer=nil; [self.mockTimer invalidate]; self.mockTimer=nil; }

- (BOOL)isChatKeyword:(NSString *)t {
    NSArray *keys=@[@"ライブ チャット",@"ライブチャット",@"上位チャット",@"Top chat",@"Live chat",@"Chat replay",@"チャット"];
    for (NSString *k in keys) if ([t localizedCaseInsensitiveContainsString:k]) return YES;
    return NO;
}
- (BOOL)isIgnoredChromeText:(NSString *)t {
    NSArray *bad=@[@"コメント",@"高評価",@"低評価",@"共有",@"保存",@"チャンネル登録",@"回視聴",@"視聴中",@"プレミア公開",@"その他"];
    for (NSString *k in bad) if ([t localizedCaseInsensitiveContainsString:k]) return YES;
    return NO;
}

- (UIView *)findLikelyChatRoot:(UIView *)view {
    if (!view) return nil;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        if ([self isChatKeyword:label.text ?: @""]) return view.superview ?: view;
    }
    for (UIView *sub in view.subviews) {
        UIView *r=[self findLikelyChatRoot:sub];
        if (r) return r;
    }
    return nil;
}

- (NSArray<UILabel *> *)collectLabelsIn:(UIView *)root {
    NSMutableArray<UILabel *> *arr=[NSMutableArray array];
    if (!root) return arr;
    NSMutableArray<UIView *> *queue=[NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v=queue.firstObject; [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *l=(UILabel *)v;
            if (l.text.length > 0 && ![self isIgnoredChromeText:l.text]) [arr addObject:l];
        }
        [queue addObjectsFromArray:v.subviews ?: @[]];
    }
    return arr;
}

- (void)scanTree {
    UIView *root = self.root; if (!root) return;
    UIView *chatRoot = [self findLikelyChatRoot:root];
    if (!chatRoot) { [[DebugInspector shared] log:@"chat root not found"]; return; }

    NSArray<UILabel *> *labels = [self collectLabelsIn:chatRoot];
    for (NSInteger i=0;i<labels.count;i++) {
        NSString *line = labels[i].text ?: @"";
        if ([line containsString:@":"]) {
            [self parseInlineChatLine:line];
            continue;
        }
        if (i + 1 < labels.count) {
            NSString *author = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSMutableArray<NSString *> *body=[NSMutableArray array];
            for (NSInteger j=i+1;j<MIN(i+3, labels.count);j++) {
                NSString *t=[labels[j].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (t.length == 0 || [self isIgnoredChromeText:t] || [self isChatKeyword:t]) break;
                [body addObject:t];
            }
            if (author.length > 0 && body.count > 0 && ![self isIgnoredChromeText:author]) {
                [self emitAuthor:author text:[body componentsJoinedByString:@" "]];
            }
        }
    }

    for (UIView *sub in chatRoot.subviews) {
        if ([sub isKindOfClass:WKWebView.class]) {
            WKWebView *web=(WKWebView *)sub;
            [web evaluateJavaScript:@"(function(){var e=document.body?document.body.innerText:'';return e?e.split('\\n').slice(-40).join('\\n'):'';})()" completionHandler:^(id result, NSError *error) {
                if (![result isKindOfClass:NSString.class]) return;
                for (NSString *line in [(NSString *)result componentsSeparatedByString:@"\n"]) {
                    [self parseInlineChatLine:line];
                }
            }];
        }
    }
}

- (void)parseInlineChatLine:(NSString *)line {
    if (line.length < 3 || [self isIgnoredChromeText:line]) return;
    NSArray *parts = [line componentsSeparatedByString:@":"]; if (parts.count < 2) return;
    NSString *author = [parts.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *text = [[parts subarrayWithRange:NSMakeRange(1, parts.count-1)] componentsJoinedByString:@":"];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    [self emitAuthor:author text:text];
}

- (void)emitAuthor:(NSString *)author text:(NSString *)text {
    if (author.length == 0 || text.length == 0) return;
    if ([self isIgnoredChromeText:author] || [self isIgnoredChromeText:text]) return;
    NSString *mid = [NSString stringWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@",author,text] hash]];
    if ([self.cache containsMessageId:mid]) return;
    [self.cache addMessageId:mid];
    NicoChatMessage *msg=[[NicoChatMessage alloc] initWithId:mid authorName:author text:text timestamp:NSDate.date];
    [self.delegate chatAdapterDidReceiveMessage:msg];
}

- (void)emitMock {
    NSArray *samples=@[@"テストコメント",@"ライブありがとう！",@"888888",@"初見です",@"ナイス配信"];
    NSString *text=samples[arc4random_uniform((uint32_t)samples.count)];
    NSString *mid=[NSUUID UUID].UUIDString;
    NicoChatMessage *msg=[[NicoChatMessage alloc] initWithId:mid authorName:@"mock" text:text timestamp:NSDate.date];
    [self.delegate chatAdapterDidReceiveMessage:msg];
}
@end

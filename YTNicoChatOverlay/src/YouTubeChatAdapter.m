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
    self.root = rootView; [self stopObserving];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(scanTree) userInfo:nil repeats:YES];
    if ([SettingsManager shared].mockMode) {
        self.mockTimer = [NSTimer scheduledTimerWithTimeInterval:1.2 target:self selector:@selector(emitMock) userInfo:nil repeats:YES];
    }
}
- (void)stopObserving { [self.pollTimer invalidate]; self.pollTimer=nil; [self.mockTimer invalidate]; self.mockTimer=nil; }
- (void)scanTree {
    UIView *root = self.root; if (!root) return;
    [[DebugInspector shared] log:@"scanTree start"]; 
    [self scanView:root];
}
- (void)scanView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view; NSString *t=label.text;
        if (t.length > 0 && t.length < 140 && [t containsString:@":"]) {
            [self parsePotentialChat:t];
        }
    } else if ([view isKindOfClass:WKWebView.class]) {
        WKWebView *web=(WKWebView *)view;
        [web evaluateJavaScript:@"(function(){var e=document.body?document.body.innerText:''; return e ? e.split('\\n').slice(-8).join('\\n') : '';})()" completionHandler:^(id result, NSError *error) {
            if ([result isKindOfClass:NSString.class]) {
                NSArray *lines=[(NSString *)result componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) [self parsePotentialChat:line];
            }
        }];
    }
    for (UIView *sub in view.subviews) [self scanView:sub];
}
- (void)parsePotentialChat:(NSString *)line {
    NSArray *parts = [line componentsSeparatedByString:@":"]; if (parts.count < 2) return;
    NSString *author = [parts.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *text = [[parts subarrayWithRange:NSMakeRange(1, parts.count-1)] componentsJoinedByString:@":"];
    text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (author.length == 0 || text.length == 0) return;
    NSString *mid = [NSString stringWithFormat:@"%lu", (unsigned long)line.hash];
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

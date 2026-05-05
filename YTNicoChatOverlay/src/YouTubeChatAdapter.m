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
- (instancetype)init { if ((self=[super init])) _cache=[[NicoMessageLRUCache alloc] initWithCapacity:500]; return self; }
- (void)startObservingInRootView:(UIView *)rootView { self.root = rootView; [self stopObserving]; self.pollTimer=[NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(scanTree) userInfo:nil repeats:YES]; }
- (void)stopObserving { [self.pollTimer invalidate]; self.pollTimer=nil; [self.mockTimer invalidate]; self.mockTimer=nil; }

- (NSArray<NSString *> *)normalHeaders { return @[@"コメント",@"返信",@"Comments",@"Replies"]; }
- (NSArray<NSString *> *)liveHeaders { return @[@"ライブ チャット",@"ライブチャット",@"上位チャット",@"チャット リプレイ",@"Live chat",@"Top chat",@"Chat replay"]; }

- (BOOL)containsAny:(NSString *)text in:(NSArray<NSString *> *)keys {
    for (NSString *k in keys) if ([text localizedCaseInsensitiveContainsString:k]) return YES;
    return NO;
}
- (UIView *)findRegion:(UIView *)view headers:(NSArray<NSString *> *)headers {
    if (!view) return nil;
    if ([view isKindOfClass:UILabel.class]) {
        NSString *t=((UILabel *)view).text ?: @"";
        if ([self containsAny:t in:headers]) return view.superview ?: view;
    }
    for (UIView *sub in view.subviews) { UIView *f=[self findRegion:sub headers:headers]; if (f) return f; }
    return nil;
}
- (NSArray<UILabel *> *)labelsInRegion:(UIView *)root {
    NSMutableArray *arr=[NSMutableArray array]; if (!root) return arr;
    NSMutableArray *q=[NSMutableArray arrayWithObject:root];
    while (q.count) { UIView *v=q.firstObject; [q removeObjectAtIndex:0];
        if ([v isKindOfClass:UILabel.class]) { UILabel *l=(UILabel *)v; if (!l.hidden && l.alpha>0.1 && l.text.length) [arr addObject:l]; }
        [q addObjectsFromArray:v.subviews ?: @[]];
    }
    return arr;
}

- (NSString *)cleanAuthorFromCandidate:(NSString *)candidate {
    NSString *trimmed = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *separators = @[@"・", @"•", @"·"];
    for (NSString *sep in separators) {
        NSRange r = [trimmed rangeOfString:sep];
        if (r.location != NSNotFound && r.location > 0) { trimmed = [[trimmed substringToIndex:r.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; break; }
    }
    return trimmed;
}
- (BOOL)looksLikeAuthor:(NSString *)author { if (author.length==0) return NO; if ([author hasPrefix:@"@"]) return YES; return author.length < 40; }
- (BOOL)isInsidePlayerArea:(UIView *)v {
    CGRect r=[v convertRect:v.bounds toView:nil]; CGSize s=UIScreen.mainScreen.bounds.size;
    return CGRectGetMinY(r) < s.height * 0.55 && CGRectGetHeight(r) > 80;
}
- (BOOL)containsBlockedWord:(NSString *)text { for (NSString *w in [SettingsManager shared].blockWords) if (w.length && [text localizedCaseInsensitiveContainsString:w]) return YES; return NO; }
- (void)emitAuthor:(NSString *)author text:(NSString *)text {
    if (author.length==0 || text.length==0 || [self containsBlockedWord:text]) return;
    NSString *mid=[NSString stringWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@",author,text] hash]];
    if ([self.cache containsMessageId:mid]) return; [self.cache addMessageId:mid];
    if ([SettingsManager shared].debugLogging) [[DebugInspector shared] log:@"emit chat author=%@ text=%@", author, text];
    [self.delegate chatAdapterDidReceiveMessage:[[NicoChatMessage alloc] initWithId:mid authorName:author text:text timestamp:NSDate.date]];
}

- (void)scanRegion:(UIView *)region {
    if (!region || [self isInsidePlayerArea:region]) return; // 字幕等のプレイヤー内は対象外
    if ([SettingsManager shared].debugLogging) [[DebugInspector shared] log:@"region=%@ frame=%@", NSStringFromClass(region.class), NSStringFromCGRect(region.frame)];
    NSArray<UILabel *> *labels=[self labelsInRegion:region];
    NSMutableArray<NSString *> *clean=[NSMutableArray array];
    for (UILabel *l in labels) { NSString *t=[l.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (t.length) [clean addObject:t]; }
    for (NSInteger i=0;i<clean.count;i++) {
        NSString *rawAuthor = clean[i];
        NSString *author = [self cleanAuthorFromCandidate:rawAuthor];
        if ([rawAuthor containsString:@":"]) { NSArray *p=[rawAuthor componentsSeparatedByString:@":"]; if (p.count>=2) [self emitAuthor:[self cleanAuthorFromCandidate:p.firstObject] text:[[p subarrayWithRange:NSMakeRange(1,p.count-1)] componentsJoinedByString:@":"]]; continue; }
        if ([self looksLikeAuthor:author] && i+1<clean.count) {
            NSString *body = clean[i+1];
            if (body.length > 0) [self emitAuthor:author text:body];
        }
    }
    for (UIView *sub in region.subviews) if ([sub isKindOfClass:WKWebView.class]) {
        [(WKWebView *)sub evaluateJavaScript:@"(function(){var e=document.body?document.body.innerText:'';return e?e.split('\\n').slice(-50).join('\\n'):'';})()" completionHandler:^(id result, NSError *error) {
            if (![result isKindOfClass:NSString.class]) return;
            for (NSString *line in [(NSString *)result componentsSeparatedByString:@"\n"]) {
                NSArray *p=[line componentsSeparatedByString:@":"]; if (p.count>=2) [self emitAuthor:[self cleanAuthorFromCandidate:p.firstObject] text:[[p subarrayWithRange:NSMakeRange(1,p.count-1)] componentsJoinedByString:@":"]];
            }
        }];
    }
}
- (void)scanTree {
    UIView *root=self.root; if (!root) return;
    UIView *liveRegion=[self findRegion:root headers:[self liveHeaders]];
    UIView *normalRegion=[self findRegion:root headers:[self normalHeaders]];
    if (liveRegion) [self scanRegion:liveRegion];
    if (normalRegion) [self scanRegion:normalRegion];
}
@end

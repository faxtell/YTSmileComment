#import "DebugInspector.h"
#import "SettingsManager.h"

@implementation DebugInspector
+ (instancetype)shared { static DebugInspector *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[DebugInspector new]; }); return s; }
- (void)log:(NSString *)format, ... {
    if (![SettingsManager shared].debugLogging) return;
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[YTNico] %@", msg);
}
- (void)dumpViewTreeFrom:(UIView *)view maxDepth:(NSInteger)maxDepth {
    if (!view || maxDepth < 0) return;
    [self walk:view depth:0 maxDepth:maxDepth];
}
- (void)walk:(UIView *)view depth:(NSInteger)depth maxDepth:(NSInteger)maxDepth {
    if (!view || depth > maxDepth) return;
    [self log:@"%@<%@ frame=%@ hidden=%d alpha=%.2f>", [@"" stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0], NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.hidden, view.alpha];
    for (UIView *sub in view.subviews) {
        [self walk:sub depth:depth+1 maxDepth:maxDepth];
    }
}
@end

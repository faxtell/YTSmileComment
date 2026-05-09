#import "DebugInspector.h"
#import "SettingsManager.h"

@interface DebugInspector ()
@property (nonatomic, strong) NSMutableArray<NSString *> *buffer;
@property (nonatomic, strong) NSDateFormatter *formatter;
@end

@implementation DebugInspector
+ (instancetype)shared { static DebugInspector *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[DebugInspector new]; }); return s; }

- (instancetype)init {
    if ((self = [super init])) {
        _buffer = [NSMutableArray array];
        _formatter = [NSDateFormatter new];
        _formatter.dateFormat = @"HH:mm:ss.SSS";
    }
    return self;
}

- (void)appendMessage:(NSString *)msg forceNSLog:(BOOL)forceNSLog {
    if (msg.length == 0) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@", [self.formatter stringFromDate:NSDate.date], msg];
    @synchronized (self.buffer) {
        [self.buffer addObject:line];
        while (self.buffer.count > 300) [self.buffer removeObjectAtIndex:0];
    }
    if (forceNSLog || [SettingsManager shared].debugLogging) NSLog(@"[YTNico] %@", msg);
}

- (void)log:(NSString *)format, ... {
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (![SettingsManager shared].debugLogging) return;
    [self appendMessage:msg forceNSLog:YES];
}

- (void)important:(NSString *)format, ... {
    va_list args; va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self appendMessage:msg forceNSLog:NO];
}

- (NSArray<NSString *> *)recentLogs {
    @synchronized (self.buffer) { return [self.buffer copy]; }
}

- (NSString *)recentLogText {
    return [[self recentLogs] componentsJoinedByString:@"\n"] ?: @"";
}

- (void)clearLogs {
    @synchronized (self.buffer) { [self.buffer removeAllObjects]; }
    [self important:@"debug log cleared"];
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

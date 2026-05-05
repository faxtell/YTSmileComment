#import "YouTubeChatAdapter.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSHashTable<YouTubeChatAdapter *> *gAdapters;
static dispatch_queue_t gParseQueue;

@interface YouTubeChatAdapter ()
@property (nonatomic, weak) UIView *root;
@property (nonatomic, strong) NSTimer *mockTimer;
@property (nonatomic, strong) NicoMessageLRUCache *cache;
@end

@implementation YouTubeChatAdapter

+ (void)initialize {
    if (self == YouTubeChatAdapter.class) {
        gAdapters = [NSHashTable weakObjectsHashTable];
        gParseQueue = dispatch_queue_create("com.example.ytnico.parse", DISPATCH_QUEUE_SERIAL);
    }
}

- (instancetype)init {
    if ((self = [super init])) _cache = [[NicoMessageLRUCache alloc] initWithCapacity:4000];
    return self;
}

- (void)startObservingInRootView:(UIView *)rootView {
    self.root = rootView;
    @synchronized (gAdapters) { [gAdapters addObject:self]; }
    [self refreshMockTimer];
}

- (void)stopObserving {
    @synchronized (gAdapters) { [gAdapters removeObject:self]; }
    [self.mockTimer invalidate];
    self.mockTimer = nil;
}

- (void)refreshMockTimer {
    BOOL wantsMock = [SettingsManager shared].mockMode;
    if (wantsMock && !self.mockTimer) self.mockTimer = [NSTimer scheduledTimerWithTimeInterval:1.4 target:self selector:@selector(emitMock) userInfo:nil repeats:YES];
    if (!wantsMock && self.mockTimer) { [self.mockTimer invalidate]; self.mockTimer = nil; }
}

+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *adapters = nil;
        @synchronized (gAdapters) { adapters = gAdapters.allObjects; }
        for (YouTubeChatAdapter *adapter in adapters) {
            [adapter emitAuthor:author text:text messageId:messageId];
        }
    });
}

+ (void)ingestPotentialInnertubeData:(NSData *)data request:(NSURLRequest *)request {
    if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > 20000000) return;
    dispatch_async(gParseQueue, ^{
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (obj) [self ingestPotentialJSONObject:obj];
    });
}

+ (void)ingestPotentialJSONObject:(id)object {
    if (!object) return;
    dispatch_async(gParseQueue, ^{
        NSMutableArray<NSDictionary *> *messages = [NSMutableArray array];
        [self collect:object into:messages depth:0];
        if (messages.count == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray *adapters = nil;
            @synchronized (gAdapters) { adapters = gAdapters.allObjects; }
            for (NSDictionary *m in messages) {
                for (YouTubeChatAdapter *adapter in adapters) {
                    [adapter emitAuthor:m[@"a"] text:m[@"t"] messageId:m[@"i"]];
                }
            }
        });
    });
}

+ (void)collect:(id)obj into:(NSMutableArray<NSDictionary *> *)messages depth:(NSInteger)depth {
    if (!obj || depth > 80 || messages.count > 600) return;
    if ([obj isKindOfClass:NSArray.class]) {
        for (id x in (NSArray *)obj) [self collect:x into:messages depth:depth + 1];
        return;
    }
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = (NSDictionary *)obj;

    NSDictionary *c = d[@"commentRenderer"];
    if ([c isKindOfClass:NSDictionary.class]) [self addComment:c into:messages];

    NSArray *keys = @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatPaidStickerRenderer", @"liveChatMembershipItemRenderer"];
    for (NSString *k in keys) {
        NSDictionary *r = d[k];
        if ([r isKindOfClass:NSDictionary.class]) [self addLive:r key:k into:messages];
    }

    for (id v in d.allValues) [self collect:v into:messages depth:depth + 1];
}

+ (void)addComment:(NSDictionary *)r into:(NSMutableArray<NSDictionary *> *)messages {
    NSString *a = [self norm:[self text:r[@"authorText"]]];
    NSString *t = [self norm:[self text:r[@"contentText"]]];
    NSString *i = [self norm:r[@"commentId"]];
    if (a.length == 0) a = @"comment";
    [self addAuthor:a text:t mid:i into:messages];
}

+ (void)addLive:(NSDictionary *)r key:(NSString *)key into:(NSMutableArray<NSDictionary *> *)messages {
    NSString *a = [self norm:[self text:r[@"authorName"]]];
    NSString *t = [self norm:[self text:r[@"message"]]];
    NSString *amount = [self norm:[self text:r[@"purchaseAmountText"]]];
    NSString *i = [self norm:r[@"id"]];
    if (amount.length && t.length) t = [NSString stringWithFormat:@"%@ %@", amount, t];
    if (t.length == 0) t = amount;
    if (a.length == 0) a = @"live";
    [self addAuthor:a text:t mid:i into:messages];
}

+ (void)addAuthor:(NSString *)a text:(NSString *)t mid:(NSString *)i into:(NSMutableArray<NSDictionary *> *)messages {
    a = [self norm:a]; t = [self norm:t]; i = [self norm:i];
    if (t.length == 0) return;
    if (i.length == 0) i = [NSString stringWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@", a, t] hash]];
    for (NSDictionary *m in messages) if ([m[@"i"] isEqualToString:i]) return;
    [messages addObject:@{@"a": a ?: @"", @"t": t, @"i": i}];
}

+ (NSString *)text:(id)o {
    if ([o isKindOfClass:NSString.class]) return o;
    if ([o isKindOfClass:NSNumber.class]) return [(NSNumber *)o stringValue];
    if ([o isKindOfClass:NSArray.class]) {
        NSMutableString *s = [NSMutableString string];
        for (id x in (NSArray *)o) [s appendString:[self text:x] ?: @""];
        return s;
    }
    if (![o isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *d = (NSDictionary *)o;
    if ([d[@"simpleText"] isKindOfClass:NSString.class]) return d[@"simpleText"];
    if ([d[@"text"] isKindOfClass:NSString.class]) return d[@"text"];
    if ([d[@"runs"] isKindOfClass:NSArray.class]) return [self text:d[@"runs"]];
    if ([d[@"label"] isKindOfClass:NSString.class]) return d[@"label"];
    return [self text:d[@"accessibilityData"]];
}

+ (NSString *)norm:(id)o {
    if (![o isKindOfClass:NSString.class]) return @"";
    NSString *s = [(NSString *)o stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    s = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s rangeOfString:@"  "].location != NSNotFound) s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return s;
}

- (void)emitAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    if (![SettingsManager shared].enabled) return;
    NSString *a = [YouTubeChatAdapter norm:author];
    NSString *t = [YouTubeChatAdapter norm:text];
    NSString *mid = [YouTubeChatAdapter norm:messageId];
    if (t.length == 0) return;
    if (mid.length == 0) mid = [NSString stringWithFormat:@"%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@", a, t] hash]];
    if ([self.cache containsMessageId:mid]) return;
    [self.cache addMessageId:mid];
    [[DebugInspector shared] log:@"emit renderer author=%@ text=%@", a, t];
    NicoChatMessage *msg = [[NicoChatMessage alloc] initWithId:mid authorName:a text:t timestamp:NSDate.date];
    [self.delegate chatAdapterDidReceiveMessage:msg];
}

- (void)emitMock {
    if (![SettingsManager shared].mockMode) return;
    NSArray *samples = @[@"テストコメント", @"ライブありがとう！", @"888888", @"初見です", @"ナイス配信"];
    NSString *text = samples[arc4random_uniform((uint32_t)samples.count)];
    [self emitAuthor:@"mock" text:text messageId:NSUUID.UUID.UUIDString];
}
@end

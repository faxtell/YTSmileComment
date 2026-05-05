#import "YouTubeChatAdapter.h"
#import "NicoChatMessage.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

NSString * const kYTNicoClearOverlayNotification = @"com.example.ytnico.clearOverlay";
NSString * const kYTNicoCurrentVideoChangedNotification = @"com.example.ytnico.videoChanged";

static NSHashTable<YouTubeChatAdapter *> *gAdapters;
static dispatch_queue_t gParseQueue;
static NSMutableArray<NSDictionary *> *gPendingMessages;
static NSMutableSet<NSString *> *gPendingIds;
static NSTimer *gDrainTimer;
static NSString *gCurrentVideoId;
static NSUInteger gGeneration;

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
        gPendingMessages = [NSMutableArray array];
        gPendingIds = [NSMutableSet set];
        gCurrentVideoId = @"";
        gGeneration = 0;
    }
}

- (instancetype)init {
    if ((self = [super init])) _cache = [[NicoMessageLRUCache alloc] initWithCapacity:6000];
    return self;
}

- (void)startObservingInRootView:(UIView *)rootView {
    self.root = rootView;
    @synchronized (gAdapters) { [gAdapters addObject:self]; }
    [self refreshMockTimer];
    [YouTubeChatAdapter ytnico_ensureDrainTimer];
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

#pragma mark - Video reset / generation

+ (void)resetForVideoId:(NSString *)videoId {
    videoId = [self norm:videoId];
    if (videoId.length != 11) return;
    BOOL changed = NO;
    @synchronized (self) {
        changed = ![gCurrentVideoId isEqualToString:videoId];
        if (!changed) return;
        gCurrentVideoId = [videoId copy];
        gGeneration++;
    }
    @synchronized (gPendingMessages) {
        [gPendingMessages removeAllObjects];
        [gPendingIds removeAllObjects];
    }
    [gDrainTimer invalidate];
    gDrainTimer = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoClearOverlayNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoCurrentVideoChangedNotification object:nil userInfo:@{@"videoId": videoId}];
    });
    [[DebugInspector shared] log:@"reset for videoId=%@ generation=%lu", videoId, (unsigned long)gGeneration];
}

+ (NSString *)currentVideoId { @synchronized (self) { return [gCurrentVideoId copy] ?: @""; } }
+ (NSUInteger)currentGeneration { @synchronized (self) { return gGeneration; } }

#pragma mark - Adaptive pacing buffer

+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    author = [self norm:author];
    text = [self norm:text];
    messageId = [self norm:messageId];
    if (text.length == 0) return;
    if (messageId.length == 0) messageId = [NSString stringWithFormat:@"direct-%lu", (unsigned long)[[NSString stringWithFormat:@"%@|%@", author, text] hash]];

    if ([author isEqualToString:@"YTNico"]) {
        [self emitNowAuthor:author text:text messageId:messageId];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (gPendingMessages) {
            if ([gPendingIds containsObject:messageId]) return;
            [gPendingIds addObject:messageId];
            [gPendingMessages addObject:@{@"a":author ?: @"", @"t":text, @"i":messageId}];
            if (gPendingMessages.count > 1800) {
                NSUInteger removeCount = MIN((NSUInteger)300, gPendingMessages.count);
                for (NSUInteger i = 0; i < removeCount; i++) {
                    NSDictionary *old = gPendingMessages.firstObject;
                    if (old[@"i"]) [gPendingIds removeObject:old[@"i"]];
                    [gPendingMessages removeObjectAtIndex:0];
                }
            }
        }
        [self ytnico_ensureDrainTimer];
    });
}

+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    [self ytnico_emitAuthorNow:author text:text messageId:messageId];
}

+ (void)ytnico_emitAuthorNow:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *adapters = nil;
        @synchronized (gAdapters) { adapters = gAdapters.allObjects; }
        for (YouTubeChatAdapter *adapter in adapters) {
            [adapter emitAuthor:author text:text messageId:messageId];
        }
    });
}

+ (NSTimeInterval)ytnico_intervalForPendingCount:(NSUInteger)count {
    SettingsManager *s = SettingsManager.shared;
    CGFloat density = MAX(0.1, MIN(1.0, s.commentDensity));
    CGFloat longevity = MAX(0.1, MIN(1.0, s.longevity));
    NSTimeInterval base = 6.5;
    if (count >= 700) base = 0.7;
    else if (count >= 500) base = 0.9;
    else if (count >= 250) base = 1.25;
    else if (count >= 120) base = 1.75;
    else if (count >= 60) base = 2.5;
    else if (count >= 25) base = 3.6;
    else if (count >= 8) base = 5.0;
    NSTimeInterval densityFactor = 1.35 - density * 0.65;
    NSTimeInterval longevityFactor = 0.65 + longevity * 0.95;
    return MAX(0.45, MIN(9.0, base * densityFactor * longevityFactor));
}

+ (void)ytnico_ensureDrainTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gDrainTimer && gDrainTimer.valid) return;
        gDrainTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(ytnico_drainTick) userInfo:nil repeats:NO];
    });
}

+ (void)ytnico_scheduleNextDrain {
    @synchronized (gPendingMessages) {
        if (gPendingMessages.count == 0) {
            [gDrainTimer invalidate];
            gDrainTimer = nil;
            return;
        }
    }
    NSTimeInterval interval = 3.0;
    @synchronized (gPendingMessages) { interval = [self ytnico_intervalForPendingCount:gPendingMessages.count]; }
    [gDrainTimer invalidate];
    gDrainTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(ytnico_drainTick) userInfo:nil repeats:NO];
}

+ (void)ytnico_drainTick {
    NSMutableArray<NSDictionary *> *batch = [NSMutableArray array];
    @synchronized (gPendingMessages) {
        NSUInteger count = gPendingMessages.count;
        CGFloat density = MAX(0.1, MIN(1.0, SettingsManager.shared.commentDensity));
        NSUInteger burst = 1;
        if (count >= 700 && density > 0.72) burst = 4;
        else if (count >= 450 && density > 0.58) burst = 3;
        else if (count >= 180 && density > 0.48) burst = 2;
        for (NSUInteger i = 0; i < burst && gPendingMessages.count > 0; i++) {
            NSDictionary *m = gPendingMessages.firstObject;
            [batch addObject:m];
            if (m[@"i"]) [gPendingIds removeObject:m[@"i"]];
            [gPendingMessages removeObjectAtIndex:0];
        }
    }

    for (NSDictionary *m in batch) [self ytnico_emitAuthorNow:m[@"a"] text:m[@"t"] messageId:m[@"i"]];
    [self ytnico_scheduleNextDrain];
}

+ (NSUInteger)pendingMessageCount { @synchronized (gPendingMessages) { return gPendingMessages.count; } }

#pragma mark - Legacy JSON parser entrypoints

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
        for (NSDictionary *m in messages) [self broadcastAuthor:m[@"a"] text:m[@"t"] messageId:m[@"i"]];
    });
}

+ (void)collect:(id)obj into:(NSMutableArray<NSDictionary *> *)messages depth:(NSInteger)depth {
    if (!obj || depth > 80 || messages.count > 600) return;
    if ([obj isKindOfClass:NSArray.class]) { for (id x in (NSArray *)obj) [self collect:x into:messages depth:depth + 1]; return; }
    if (![obj isKindOfClass:NSDictionary.class]) return;
    NSDictionary *d = (NSDictionary *)obj;
    NSDictionary *c = d[@"commentRenderer"];
    if ([c isKindOfClass:NSDictionary.class]) [self addComment:c into:messages];
    NSArray *keys = @[@"liveChatTextMessageRenderer", @"liveChatPaidMessageRenderer", @"liveChatPaidStickerRenderer", @"liveChatMembershipItemRenderer"];
    for (NSString *k in keys) { NSDictionary *r = d[k]; if ([r isKindOfClass:NSDictionary.class]) [self addLive:r key:k into:messages]; }
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
    if ([o isKindOfClass:NSArray.class]) { NSMutableString *s = [NSMutableString string]; for (id x in (NSArray *)o) [s appendString:[self text:x] ?: @""]; return s; }
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

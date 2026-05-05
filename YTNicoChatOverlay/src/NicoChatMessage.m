#import "NicoChatMessage.h"

@implementation NicoChatMessage
- (instancetype)initWithId:(NSString *)messageId
                authorName:(NSString *)authorName
                      text:(NSString *)text
                 timestamp:(NSDate *)timestamp {
    self = [super init];
    if (self) {
        _messageId = [messageId copy];
        _authorName = [authorName copy];
        _text = [text copy];
        _timestamp = timestamp;
    }
    return self;
}
@end

@interface NicoMessageLRUCache ()
@property (nonatomic, assign) NSUInteger capacity;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@property (nonatomic, strong) NSMutableSet<NSString *> *set;
@end

@implementation NicoMessageLRUCache
- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _capacity = MAX(10, capacity);
        _order = [NSMutableArray array];
        _set = [NSMutableSet set];
    }
    return self;
}

- (BOOL)containsMessageId:(NSString *)messageId {
    if (messageId.length == 0) { return NO; }
    return [self.set containsObject:messageId];
}

- (void)addMessageId:(NSString *)messageId {
    if (messageId.length == 0) { return; }
    if ([self.set containsObject:messageId]) {
        [self.order removeObject:messageId];
        [self.order addObject:messageId];
        return;
    }
    [self.set addObject:messageId];
    [self.order addObject:messageId];
    if (self.order.count > self.capacity) {
        NSString *oldest = self.order.firstObject;
        if (oldest) {
            [self.set removeObject:oldest];
            [self.order removeObjectAtIndex:0];
        }
    }
}
@end

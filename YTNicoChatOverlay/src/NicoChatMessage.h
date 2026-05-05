#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NicoChatMessage : NSObject
@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong, nullable) UIColor *colorHint;
@property (nonatomic, assign) BOOL isOwner;
@property (nonatomic, assign) BOOL isModerator;
@property (nonatomic, assign) BOOL isMember;
@property (nonatomic, assign) BOOL isSuperChatLike;

- (instancetype)initWithId:(NSString *)messageId
                authorName:(NSString *)authorName
                      text:(NSString *)text
                 timestamp:(NSDate *)timestamp;
@end

@interface NicoMessageLRUCache : NSObject
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (BOOL)containsMessageId:(NSString *)messageId;
- (void)addMessageId:(NSString *)messageId;
@end

NS_ASSUME_NONNULL_END

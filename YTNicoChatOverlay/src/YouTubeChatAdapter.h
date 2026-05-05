#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class NicoChatMessage;

FOUNDATION_EXTERN NSString * const kYTNicoClearOverlayNotification;
FOUNDATION_EXTERN NSString * const kYTNicoCurrentVideoChangedNotification;

@protocol YouTubeChatAdapterDelegate <NSObject>
- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message;
@end

@interface YouTubeChatAdapter : NSObject
@property (nonatomic, weak) id<YouTubeChatAdapterDelegate> delegate;
- (void)startObservingInRootView:(UIView *)rootView;
- (void)stopObserving;
+ (void)ingestPotentialInnertubeData:(NSData *)data request:(NSURLRequest *)request;
+ (void)ingestPotentialJSONObject:(id)object;
+ (void)broadcastAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId;
+ (void)emitNowAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId;
+ (void)resetForVideoId:(NSString *)videoId;
+ (NSString *)currentVideoId;
+ (NSUInteger)currentGeneration;
@end

@interface YouTubeChatAdapter (Replay)
+ (void)observePotentialRequest:(NSURLRequest *)request bodyData:(NSData *)bodyData;
@end

@interface YouTubeChatAdapter (DirectFetch)
+ (NSString *)extractVideoIdFromString:(NSString *)input;
+ (void)fetchCommentsForVideoId:(NSString *)videoId;
@end

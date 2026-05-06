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
+ (void)queueTimedReplayAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId offsetMilliseconds:(unsigned long long)offsetMilliseconds generation:(NSUInteger)generation;
+ (void)updateCurrentPlaybackSeconds:(double)seconds;
+ (double)currentPlaybackSeconds;
+ (void)noteDetectedVideoId:(NSString *)videoId source:(NSString *)source;
+ (NSString *)recentDetectedVideoId;
+ (void)resetForVideoId:(NSString *)videoId;
+ (void)forceResetForVideoId:(NSString *)videoId;
+ (void)clearCurrentVideoAndComments;
+ (NSString *)currentVideoId;
+ (NSUInteger)currentGeneration;
+ (NSUInteger)pendingMessageCount;
+ (NSTimeInterval)secondsSinceLastMessage;
+ (void)watchdogKick;
@end

@interface YouTubeChatAdapter (Replay)
+ (void)observePotentialRequest:(NSURLRequest *)request bodyData:(NSData *)bodyData;
@end

@interface YouTubeChatAdapter (DirectFetch)
+ (NSString *)extractVideoIdFromString:(NSString *)input;
+ (void)fetchCommentsForVideoId:(NSString *)videoId;
@end

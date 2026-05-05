#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class NicoChatMessage;

@protocol YouTubeChatAdapterDelegate <NSObject>
- (void)chatAdapterDidReceiveMessage:(NicoChatMessage *)message;
@end

@interface YouTubeChatAdapter : NSObject
@property (nonatomic, weak) id<YouTubeChatAdapterDelegate> delegate;
- (void)startObservingInRootView:(UIView *)rootView;
- (void)stopObserving;
+ (void)ingestPotentialInnertubeData:(NSData *)data request:(NSURLRequest *)request;
+ (void)ingestPotentialJSONObject:(id)object;
@end

@interface YouTubeChatAdapter (Replay)
+ (void)observePotentialRequest:(NSURLRequest *)request bodyData:(NSData *)bodyData;
@end

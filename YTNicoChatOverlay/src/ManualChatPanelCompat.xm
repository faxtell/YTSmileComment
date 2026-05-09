#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoManualCompatFetch)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId;
@end

extern "C" NSUInteger YTNicoManualScanVisibleChatPanel(void) {
    // Manual UI scanning was reverted because it could pick up unrelated YouTube UI.
    // Keep the symbol for Tweak.xm compatibility, but do not scan the screen.
    return 0;
}

extern "C" void YTNicoStartManualChatPanelWatch(NSString *videoId) {
    // Compatibility path: if the bubble button asks for the old manual watcher,
    // start the stable video-ID based fetch instead.
    if (videoId.length == 11 && [YouTubeChatAdapter respondsToSelector:@selector(ytnico_fetchCommentsForVideoIdIgnoringThrottle:)]) {
        [[DebugInspector shared] important:@"manual scanner compat: fetch by videoId=%@", videoId];
        [YouTubeChatAdapter ytnico_fetchCommentsForVideoIdIgnoringThrottle:videoId];
    }
}

extern "C" void YTNicoStopManualChatPanelWatch(void) {
    // No-op. Manual UI watcher is disabled.
}

extern "C" BOOL YTNicoManualChatPanelWatchIsActive(void) {
    return NO;
}

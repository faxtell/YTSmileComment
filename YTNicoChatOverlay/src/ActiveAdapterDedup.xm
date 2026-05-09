#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static __weak YouTubeChatAdapter *YTNicoActiveAdapter;
static NSMutableDictionary<NSString *, NSDate *> *YTNicoRecentTextKeys;

static NSString *YTNicoDedupKey(NSString *author, NSString *text) {
    author = [author isKindOfClass:NSString.class] ? author : @"";
    text = [text isKindOfClass:NSString.class] ? text : @"";
    NSString *key = [NSString stringWithFormat:@"%@|%@", author.lowercaseString, text.lowercaseString];
    if (key.length > 240) key = [key substringToIndex:240];
    return key;
}

static void YTNicoClearVisibleDedupCache(void) {
    if (!YTNicoRecentTextKeys) return;
    @synchronized (YTNicoRecentTextKeys) {
        [YTNicoRecentTextKeys removeAllObjects];
    }
    [[DebugInspector shared] log:@"visible dedup cache cleared"];
}

%hook YouTubeChatAdapter

- (void)startObservingInRootView:(UIView *)rootView {
    %orig(rootView);
    if (rootView.window && !rootView.window.hidden && rootView.window.alpha > 0.05) {
        YTNicoActiveAdapter = self;
        if (!YTNicoRecentTextKeys) YTNicoRecentTextKeys = [NSMutableDictionary dictionary];
        [[DebugInspector shared] log:@"active adapter updated %@", self];
    }
}

- (void)emitAuthor:(NSString *)author text:(NSString *)text messageId:(NSString *)messageId {
    YouTubeChatAdapter *active = YTNicoActiveAdapter;
    if (active && active != self) return;

    if (!YTNicoRecentTextKeys) YTNicoRecentTextKeys = [NSMutableDictionary dictionary];
    NSString *key = YTNicoDedupKey(author, text);
    NSDate *now = NSDate.date;
    @synchronized (YTNicoRecentTextKeys) {
        NSDate *last = YTNicoRecentTextKeys[key];
        if (last && [now timeIntervalSinceDate:last] < 3.0) {
            [[DebugInspector shared] log:@"skip duplicate visible comment %@", key];
            return;
        }
        YTNicoRecentTextKeys[key] = now;
        if (YTNicoRecentTextKeys.count > 800) {
            NSArray *keys = YTNicoRecentTextKeys.allKeys;
            for (NSUInteger i = 0; i < MIN((NSUInteger)200, keys.count); i++) [YTNicoRecentTextKeys removeObjectForKey:keys[i]];
        }
    }
    %orig(author, text, messageId);
}

+ (void)resetForVideoId:(NSString *)videoId {
    YTNicoClearVisibleDedupCache();
    %orig(videoId);
}

+ (void)forceResetForVideoId:(NSString *)videoId {
    YTNicoClearVisibleDedupCache();
    %orig(videoId);
}

+ (void)clearCurrentVideoAndComments {
    YTNicoClearVisibleDedupCache();
    %orig;
}

%end

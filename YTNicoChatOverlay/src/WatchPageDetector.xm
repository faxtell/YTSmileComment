#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "YouTubeChatAdapter.h"
#import "SettingsManager.h"
#import "DebugInspector.h"

@interface YouTubeChatAdapter (YTNicoWatchDetectorFetch)
+ (void)ytnico_fetchCommentsForVideoIdIgnoringThrottle:(NSString *)videoId;
@end

static NSString *YTNicoDetectorLastVideoId;
static NSDate *YTNicoDetectorLastDate;

static BOOL YTNicoLooksLikeVideoId(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length != 11) return NO;
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"] invertedSet];
    return [s rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSString *YTNicoFirstMatch(NSString *s, NSArray<NSString *> *patterns) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges >= 2) return [s substringWithRange:[m rangeAtIndex:1]];
    }
    return @"";
}

static NSString *YTNicoVideoIdFromString(NSString *s) {
    if (![s isKindOfClass:NSString.class] || s.length == 0) return @"";
    NSString *direct = [YouTubeChatAdapter extractVideoIdFromString:s];
    if (direct.length == 11) return direct;
    if (YTNicoLooksLikeVideoId(s)) return s;
    return YTNicoFirstMatch(s, @[
        @"videoId[=:]([A-Za-z0-9_-]{11})",
        @"video_id[=:]([A-Za-z0-9_-]{11})",
        @"watch\\?v=([A-Za-z0-9_-]{11})",
        @"/shorts/([A-Za-z0-9_-]{11})",
        @"/live/([A-Za-z0-9_-]{11})",
        @"\\\"videoId\\\"\\s*:\\s*\\\"([A-Za-z0-9_-]{11})\\\"",
        @"\"videoId\"\\s*:\\s*\"([A-Za-z0-9_-]{11})\""
    ]);
}

static BOOL YTNicoShouldInspectProperty(NSString *name) {
    NSString *lower = name.lowercaseString ?: @"";
    return [lower containsString:@"video"] ||
           [lower containsString:@"watch"] ||
           [lower containsString:@"endpoint"] ||
           [lower containsString:@"identifier"] ||
           [lower containsString:@"player"] ||
           [lower containsString:@"content"] ||
           [lower containsString:@"model"];
}

static NSString *YTNicoScanObject(id obj, NSInteger depth, NSMutableSet<NSValue *> *visited);

static NSString *YTNicoScanArray(NSArray *array, NSInteger depth, NSMutableSet<NSValue *> *visited) {
    if (![array isKindOfClass:NSArray.class] || depth > 5) return @"";
    NSInteger limit = MIN((NSInteger)array.count, 28);
    for (NSInteger i = 0; i < limit; i++) {
        NSString *found = YTNicoScanObject(array[i], depth + 1, visited);
        if (found.length == 11) return found;
    }
    return @"";
}

static NSString *YTNicoScanDictionary(NSDictionary *dict, NSInteger depth, NSMutableSet<NSValue *> *visited) {
    if (![dict isKindOfClass:NSDictionary.class] || depth > 5) return @"";
    NSArray *keys = dict.allKeys;
    NSInteger limit = MIN((NSInteger)keys.count, 60);
    for (NSInteger i = 0; i < limit; i++) {
        id key = keys[i];
        id value = dict[key];
        if ([key isKindOfClass:NSString.class] && YTNicoShouldInspectProperty(key)) {
            NSString *found = YTNicoScanObject(value, depth + 1, visited);
            if (found.length == 11) return found;
        }
    }
    for (NSInteger i = 0; i < limit; i++) {
        NSString *found = YTNicoScanObject(dict[keys[i]], depth + 1, visited);
        if (found.length == 11) return found;
    }
    return @"";
}

static NSString *YTNicoScanObject(id obj, NSInteger depth, NSMutableSet<NSValue *> *visited) {
    if (!obj || depth > 5) return @"";
    if ([obj isKindOfClass:NSString.class]) return YTNicoVideoIdFromString(obj);
    if ([obj isKindOfClass:NSNumber.class] || [obj isKindOfClass:NSDate.class]) return @"";
    if ([obj isKindOfClass:NSArray.class]) return YTNicoScanArray(obj, depth, visited);
    if ([obj isKindOfClass:NSDictionary.class]) return YTNicoScanDictionary(obj, depth, visited);

    NSValue *ptr = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptr]) return @"";
    [visited addObject:ptr];
    if (visited.count > 280) return @"";

    if ([obj isKindOfClass:UIView.class]) {
        UIView *view = (UIView *)obj;
        NSString *v = YTNicoVideoIdFromString(view.accessibilityIdentifier ?: @"");
        if (v.length == 11) return v;
        v = YTNicoVideoIdFromString(view.accessibilityLabel ?: @"");
        if (v.length == 11) return v;
    }

    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList([obj class], &count);
    if (!props) return @"";
    NSString *result = @"";
    unsigned int limit = MIN(count, 80u);
    for (unsigned int i = 0; i < limit; i++) {
        const char *nameC = property_getName(props[i]);
        if (!nameC) continue;
        NSString *name = [NSString stringWithUTF8String:nameC];
        if (!YTNicoShouldInspectProperty(name)) continue;
        @try {
            id value = [obj valueForKey:name];
            result = YTNicoScanObject(value, depth + 1, visited);
            if (result.length == 11) break;
        } @catch (__unused NSException *e) {}
    }
    free(props);
    return result ?: @"";
}

static NSString *YTNicoDetectVideoIdFromController(UIViewController *vc) {
    if (!vc) return @"";
    NSString *className = NSStringFromClass(vc.class).lowercaseString;
    BOOL likelyWatch = [className containsString:@"watch"] || [className containsString:@"player"] || [className containsString:@"video"];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    NSString *videoId = YTNicoScanObject(vc, likelyWatch ? 0 : 1, visited);
    if (videoId.length == 11) return videoId;
    visited = [NSMutableSet set];
    videoId = YTNicoScanObject(vc.view, 0, visited);
    return videoId.length == 11 ? videoId : @"";
}

static void YTNicoStartFetchFromDetectedVideoId(NSString *videoId, NSString *source) {
    if (videoId.length != 11) return;
    NSDate *now = NSDate.date;
    @synchronized ([YouTubeChatAdapter class]) {
        BOOL sameRecent = [YTNicoDetectorLastVideoId isEqualToString:videoId] && YTNicoDetectorLastDate && [now timeIntervalSinceDate:YTNicoDetectorLastDate] < 7.0;
        if (sameRecent) return;
        YTNicoDetectorLastVideoId = [videoId copy];
        YTNicoDetectorLastDate = now;
    }

    [[DebugInspector shared] important:@"watch page detector videoId=%@ source=%@", videoId, source ?: @"ui"];
    [YouTubeChatAdapter forceResetForVideoId:videoId];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![[YouTubeChatAdapter currentVideoId] isEqualToString:videoId]) return;
        [YouTubeChatAdapter emitNowAuthor:@"YTNico" text:[NSString stringWithFormat:@"自動コメント取得開始: %@", videoId] messageId:NSUUID.UUID.UUIDString];
        [YouTubeChatAdapter ytnico_fetchCommentsForVideoIdIgnoringThrottle:videoId];
    });
}

static void YTNicoInspectViewControllerLater(UIViewController *vc, NSString *source) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) return;
    if (!SettingsManager.shared.enabled || !SettingsManager.shared.autoFetch) return;
    if (!vc.view.window) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!vc.view.window) return;
        NSString *videoId = YTNicoDetectVideoIdFromController(vc);
        if (videoId.length == 11) YTNicoStartFetchFromDetectedVideoId(videoId, source);
        else [[DebugInspector shared] log:@"watch page detector no videoId vc=%@", NSStringFromClass(vc.class)];
    });
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    YTNicoInspectViewControllerLater(self, NSStringFromClass(self.class));
}

- (void)viewDidLayoutSubviews {
    %orig;
    NSString *className = NSStringFromClass(self.class).lowercaseString;
    if ([className containsString:@"watch"] || [className containsString:@"player"] || [className containsString:@"video"]) {
        YTNicoInspectViewControllerLater(self, NSStringFromClass(self.class));
    }
}
%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
        [[DebugInspector shared] important:@"YTNico watch page detector loaded"];
    }
}

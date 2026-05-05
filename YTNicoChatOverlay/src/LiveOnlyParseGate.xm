#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

%hook YouTubeChatAdapter

+ (NSInteger)ytv2_parseNormal:(NSString *)text max:(NSInteger)max live:(BOOL)live generation:(NSUInteger)generation {
    if (!live) {
        [[DebugInspector shared] important:@"live-only mode: normal comments disabled"];
        return 0;
    }
    return %orig(text, max, live, generation);
}

+ (NSInteger)ytv2_parseReplay:(NSString *)text max:(NSInteger)max generation:(NSUInteger)generation {
    [[DebugInspector shared] important:@"live-only mode: replay disabled"];
    return 0;
}

%end

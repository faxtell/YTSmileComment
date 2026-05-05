#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSInteger YTNicoAutoLaneCountForView(UIView *view) {
    CGFloat height = MAX(1.0, view.bounds.size.height);
    CGFloat fontSize = MAX(10.0, SettingsManager.shared.fontSize);
    CGFloat lineHeight = ceil(fontSize * 1.38);
    CGFloat usableHeight = MAX(1.0, height - 8.0);
    NSInteger count = (NSInteger)floor(usableHeight / MAX(14.0, lineHeight));
    return MAX(3, MIN(32, count));
}

static BOOL YTNicoSetIntegerIvar(id obj, const char *name, NSInteger value) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) ivar = class_getInstanceVariable(class_getSuperclass(object_getClass(obj)), name);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    uint8_t *bytes = (__bridge void *)obj;
    NSInteger *slot = (NSInteger *)(bytes + offset);
    if (*slot == value) return YES;
    *slot = value;
    return YES;
}

static BOOL YTNicoResizeMutableArrayIvar(id obj, const char *name, NSInteger count) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) ivar = class_getInstanceVariable(class_getSuperclass(object_getClass(obj)), name);
    if (!ivar) return NO;
    id current = object_getIvar(obj, ivar);
    if (![current isKindOfClass:NSMutableArray.class]) return NO;
    NSMutableArray *array = (NSMutableArray *)current;
    if (array.count == (NSUInteger)count) return YES;
    [array removeAllObjects];
    for (NSInteger i = 0; i < count; i++) [array addObject:@0];
    return YES;
}

static void YTNicoApplyAutoLaneCapacity(id obj) {
    if (![obj isKindOfClass:UIView.class]) return;
    UIView *view = (UIView *)obj;
    NSInteger lanes = YTNicoAutoLaneCountForView(view);

    BOOL changed = NO;
    const char *intNames[] = {"_laneCount", "_maxLanes", "_numberOfLanes", "laneCount", "maxLanes", "numberOfLanes"};
    for (int i = 0; i < 6; i++) changed |= YTNicoSetIntegerIvar(obj, intNames[i], lanes);

    const char *arrayNames[] = {"_laneFreeTimes", "_laneFreeAt", "_laneAvailableTimes", "_laneEndTimes", "_laneHeights"};
    for (int i = 0; i < 5; i++) changed |= YTNicoResizeMutableArrayIvar(obj, arrayNames[i], lanes);

    if (changed) [[DebugInspector shared] log:@"auto lanes applied count=%ld height=%.1f font=%.1f", (long)lanes, view.bounds.size.height, SettingsManager.shared.fontSize];
}

%hook NicoChatOverlayView

- (void)layoutSubviews {
    %orig;
    YTNicoApplyAutoLaneCapacity(self);
}

- (void)didMoveToWindow {
    %orig;
    YTNicoApplyAutoLaneCapacity(self);
}

%end

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "DebugInspector.h"

static NSInteger YTNicoAutoLaneCountForView(UIView *view) {
    CGFloat height = MAX(1.0, view.bounds.size.height);
    CGFloat width = MAX(1.0, view.bounds.size.width);
    BOOL landscape = width > height;
    CGFloat fontSize = MAX(10.0, SettingsManager.shared.fontSize);

    // Previous lane height was intentionally conservative. In landscape/fullscreen,
    // there is usually enough visual room to pack a few more Nico-style lanes.
    CGFloat multiplier = landscape ? 1.12 : 1.28;
    CGFloat lineHeight = ceil(fontSize * multiplier);
    CGFloat minimumLaneHeight = landscape ? 12.0 : 14.0;
    CGFloat usableHeight = MAX(1.0, height - (landscape ? 2.0 : 8.0));

    NSInteger count = (NSInteger)floor(usableHeight / MAX(minimumLaneHeight, lineHeight));
    if (landscape) count += 4;

    // Allow a little more density now that landscape is packed tighter.
    return MAX(3, MIN(40, count));
}

static BOOL YTNicoSetIntegerIvar(id obj, const char *name, NSInteger value) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) ivar = class_getInstanceVariable(class_getSuperclass(object_getClass(obj)), name);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    uint8_t *bytes = (uint8_t *)(__bridge void *)obj;
    NSInteger *slot = (NSInteger *)(bytes + offset);
    if (*slot == value) return YES;
    *slot = value;
    return YES;
}

static BOOL YTNicoSetCGFloatIvar(id obj, const char *name, CGFloat value) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) ivar = class_getInstanceVariable(class_getSuperclass(object_getClass(obj)), name);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    uint8_t *bytes = (uint8_t *)(__bridge void *)obj;
    CGFloat *slot = (CGFloat *)(bytes + offset);
    if (fabs(*slot - value) < 0.1) return YES;
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
    CGFloat width = MAX(1.0, view.bounds.size.width);
    CGFloat height = MAX(1.0, view.bounds.size.height);
    BOOL landscape = width > height;
    CGFloat laneHeight = ceil(MAX(10.0, SettingsManager.shared.fontSize) * (landscape ? 1.12 : 1.28));

    BOOL changed = NO;
    const char *intNames[] = {"_laneCount", "_maxLanes", "_numberOfLanes", "laneCount", "maxLanes", "numberOfLanes"};
    for (int i = 0; i < 6; i++) changed |= YTNicoSetIntegerIvar(obj, intNames[i], lanes);

    const char *floatNames[] = {"_laneHeight", "_commentLaneHeight", "laneHeight", "commentLaneHeight"};
    for (int i = 0; i < 4; i++) changed |= YTNicoSetCGFloatIvar(obj, floatNames[i], MAX(12.0, laneHeight));

    const char *arrayNames[] = {"_laneFreeTimes", "_laneFreeAt", "_laneAvailableTimes", "_laneEndTimes", "_laneHeights"};
    for (int i = 0; i < 5; i++) changed |= YTNicoResizeMutableArrayIvar(obj, arrayNames[i], lanes);

    if (changed) [[DebugInspector shared] log:@"auto lanes applied count=%ld height=%.1f width=%.1f font=%.1f landscape=%d", (long)lanes, view.bounds.size.height, view.bounds.size.width, SettingsManager.shared.fontSize, landscape];
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

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "SettingsManager.h"
#import "YTNicoSettingsViewController.h"

static NSString * const YTGStore = @"com.example.yt-nico-chat-overlay";
static NSString * const YTGFlag = @"ready.v1";
static const void *YTGShown = &YTGShown;

static BOOL YTGReady(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:YTGStore] ?: NSUserDefaults.standardUserDefaults;
    return [d boolForKey:YTGFlag];
}

static BOOL YTGMatch(NSString *s) {
    NSString *trim = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSData *a = [trim dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    NSData *b = [[NSData alloc] initWithBase64EncodedString:@"8J+NjA==" options:0] ?: [NSData data];
    return [a isEqualToData:b];
}

static void YTGSetReady(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:YTGStore] ?: NSUserDefaults.standardUserDefaults;
    [d setBool:YES forKey:YTGFlag];
    [d setBool:YES forKey:@"enabled"];
    [d synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kYTNicoSettingsChangedNotification object:nil];
}

%hook SettingsManager
- (BOOL)enabled { return YTGReady() ? %orig : NO; }
- (void)setEnabled:(BOOL)value { if (value && !YTGReady()) { %orig(NO); return; } %orig(value); }
- (BOOL)autoFetch { return YTGReady() ? %orig : NO; }
- (BOOL)mockMode { return YTGReady() ? %orig : NO; }
%end

%hook YTNicoSettingsViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (YTGReady()) return;
    if ([objc_getAssociatedObject(self, YTGShown) boolValue]) return;
    objc_setAssociatedObject(self, YTGShown, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"利用開始" message:@"コードを入力してください。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.placeholder = @"Code"; }];
    __weak typeof(self) w = self;
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){
        if (YTGMatch(a.textFields.firstObject.text ?: @"")) {
            YTGSetReady();
            UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"OK" message:@"利用可能になりました。" preferredStyle:UIAlertControllerStyleAlert];
            [ok addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [w presentViewController:ok animated:YES completion:nil];
        } else {
            objc_setAssociatedObject(w, YTGShown, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
%end

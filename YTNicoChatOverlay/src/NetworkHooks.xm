#import <Foundation/Foundation.h>
#import "YouTubeChatAdapter.h"
#import "DebugInspector.h"

static BOOL YTNicoIsOwnRequest(NSURLRequest *request) {
    if (![request isKindOfClass:NSURLRequest.class]) return NO;
    if ([request valueForHTTPHeaderField:@"X-YTNico-Replay"].length > 0) return YES;
    if ([request valueForHTTPHeaderField:@"X-YTNico-DirectFetch"].length > 0) return YES;
    return NO;
}

static BOOL YTNicoShouldInspectURL(NSURL *url) {
    NSString *s = url.absoluteString.lowercaseString ?: @"";
    if (s.length == 0) return NO;
    return [s containsString:@"youtube"] ||
           [s containsString:@"youtubei"] ||
           [s containsString:@"googleapis"];
}

%hook NSURLSessionTask

- (void)resume {
    NSURLRequest *req = self.currentRequest ?: self.originalRequest;
    if (req && !YTNicoIsOwnRequest(req)) {
        [YouTubeChatAdapter observePotentialRequest:req bodyData:req.HTTPBody];
    }
    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (!YTNicoIsOwnRequest(request)) [YouTubeChatAdapter observePotentialRequest:request bodyData:request.HTTPBody];
    return %orig(request);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    if (!YTNicoIsOwnRequest(req)) [YouTubeChatAdapter observePotentialRequest:req bodyData:nil];
    return %orig(url);
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    BOOL own = YTNicoIsOwnRequest(request);
    if (!own) [YouTubeChatAdapter observePotentialRequest:request bodyData:request.HTTPBody];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!own && data.length > 0 && YTNicoShouldInspectURL(request.URL)) [YouTubeChatAdapter ingestPotentialInnertubeData:data request:request];
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLRequest *req = [NSURLRequest requestWithURL:url];
    if (!YTNicoIsOwnRequest(req)) [YouTubeChatAdapter observePotentialRequest:req bodyData:nil];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (data.length > 0 && YTNicoShouldInspectURL(url)) [YouTubeChatAdapter ingestPotentialInnertubeData:data request:req];
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(url, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(NSData *)bodyData
                                completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    BOOL own = YTNicoIsOwnRequest(request);
    if (!own) [YouTubeChatAdapter observePotentialRequest:request bodyData:bodyData ?: request.HTTPBody];
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!own && data.length > 0 && YTNicoShouldInspectURL(request.URL)) [YouTubeChatAdapter ingestPotentialInnertubeData:data request:request];
        if (completionHandler) completionHandler(data, response, error);
    };
    return %orig(request, bodyData, wrapped);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    if (!YTNicoIsOwnRequest(request)) [YouTubeChatAdapter observePotentialRequest:request bodyData:bodyData ?: request.HTTPBody];
    return %orig(request, bodyData);
}

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    if (!YTNicoIsOwnRequest(request)) [YouTubeChatAdapter observePotentialRequest:request bodyData:request.HTTPBody];
    return %orig(request);
}

%end

%ctor {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]) {
        [[DebugInspector shared] log:@"YTNico network hooks loaded"];
    }
}

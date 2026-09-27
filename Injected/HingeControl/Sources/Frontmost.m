/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * Adapted from facebook/idb, SimulatorFrameworkBridge/Runtime/AccessibilityRuntime.m
 * (1c5c81f6cbe3a31986eda66349fd22a2f9b47858), under the MIT license.
 * See LICENSE.idb in this directory.
 */
#import "Frontmost.h"
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>

@interface NSObject (FrontmostTranslation)
+ (id)sharediOSInstance;
- (id)frontmostApplicationWithDisplayId:(unsigned int)displayID bridgeDelegateToken:(NSString *)token;
- (id)processTranslatorRequest:(id)request;
@end

@interface FrontmostDelegate : NSObject
@property (nonatomic, weak) NSObject *translator;
@end

@implementation FrontmostDelegate
- (id (^)(id))accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token {
  NSObject *translator = self.translator;
  return ^id(id request) { return [translator processTranslatorRequest:request]; };
}
- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token { return rect; }
- (id)accessibilityTranslationRootParentWithToken:(NSString *)token { return nil; }
@end

int printFrontmostApplication(void) {
  dispatch_semaphore_t complete = dispatch_semaphore_create(0);
  __block NSNumber *pid;
  __block NSString *failure;
  // The guest AX runtime asserts that its first query is off the main queue.
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    @autoreleasepool {
      @try {
        if (!dlopen("/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation", RTLD_NOW)) {
          failure = [NSString stringWithUTF8String:dlerror()];
        } else {
          Class translatorClass = objc_lookUpClass("AXPTranslator");
          if (![translatorClass respondsToSelector:@selector(sharediOSInstance)]) {
            failure = @"AXPTranslator.sharediOSInstance is unavailable";
          } else {
            NSObject *translator = [translatorClass sharediOSInstance];
            FrontmostDelegate * __attribute__((objc_precise_lifetime)) delegate = [FrontmostDelegate new];
            delegate.translator = translator;
            [translator setValue:delegate forKey:@"bridgeTokenDelegate"];
            [translator setValue:@YES forKey:@"supportsDelegateTokens"];
            id application = [translator frontmostApplicationWithDisplayId:0 bridgeDelegateToken:@"frontmost"];
            pid = [application valueForKey:@"pid"];
            if (![pid isKindOfClass:NSNumber.class] || pid.intValue <= 0) {
              failure = @"the guest window server returned no frontmost application";
            }
          }
        }
      } @catch (NSException *exception) {
        failure = exception.reason ?: exception.name;
      }
      dispatch_semaphore_signal(complete);
    }
  });
  if (dispatch_semaphore_wait(complete, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) != 0) {
    fprintf(stderr, "frontmost query timed out after 4 seconds\n");
    return 1;
  }
  if (failure) {
    fprintf(stderr, "frontmost query failed: %s\n", failure.UTF8String);
    return 1;
  }
  printf("{\"pid\":%d}\n", pid.intValue);
  return 0;
}

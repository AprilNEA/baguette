#pragma once
#import <Foundation/Foundation.h>

// Native enum values consumed by the simulator's orientation-picker-control.
static BOOL isHingeOrientation(NSString *value) {
  return [@[@"portrait", @"pud", @"landscape-left", @"landscape-right"] containsObject:value];
}

// Shared by one-shot and serving commands: usage error 2, dispatch error 1.
static int dispatchHingeOrientation(NSString *value, BOOL (^send)(const char *)) {
  if (!isHingeOrientation(value)) return 2;
  return send(value.UTF8String) ? 0 : 1;
}

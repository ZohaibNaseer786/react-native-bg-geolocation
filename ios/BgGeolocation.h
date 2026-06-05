//
//  BgGeolocation.h
//
//  ObjC++ TurboModule wrapper.
//  The location engine is compiled from Swift source (ios/engine/*.swift).
//  No binary dependency — zero billing, works in DEBUG and RELEASE.
//
//  NOTE: BgGeolocationSpec.h (C++) is imported only in the .mm, not here,
//  so this public header stays C-safe for Swift module scanning.
//
#import <React/RCTEventEmitter.h>

@interface BgGeolocation : RCTEventEmitter
@end

//
//  BgGeolocation.mm
//
//  ObjC++ TurboModule — delegates to our Swift engine (ios/engine/).
//  No binary dependency, no billing, works in DEBUG and RELEASE.
//
#import "BgGeolocation.h"
// Spec import MUST be in the .mm (C++), not in the .h (which Swift module scan reads as plain C).
#import <BgGeolocationSpec/BgGeolocationSpec.h>
#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
// These must come BEFORE BgGeolocation-Swift.h so the generated header
// can reference MFMailCompose and UNUserNotification types.
#import <MessageUI/MessageUI.h>
#import <UserNotifications/UserNotifications.h>
#import <AudioToolbox/AudioToolbox.h>

// Auto-generated ObjC bridge for all @objc Swift classes in this pod.
#import "BgGeolocation-Swift.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTBridge+Private.h>
#import <React/RCTUtils.h>
using namespace facebook;
using namespace facebook::react;
#endif

// Declare NativeBgGeolocationSpec conformance here so it stays out of the header.
@interface BgGeolocation () <NativeBgGeolocationSpec>
@end

// ─── Event name constants (match src/events.ts) ──────────────────────────────
static NSString *const EVENT_LOCATION           = @"location";
static NSString *const EVENT_WATCHPOSITION      = @"watchposition";
static NSString *const EVENT_PROVIDERCHANGE     = @"providerchange";
static NSString *const EVENT_MOTIONCHANGE       = @"motionchange";
static NSString *const EVENT_ACTIVITYCHANGE     = @"activitychange";
static NSString *const EVENT_GEOFENCESCHANGE    = @"geofenceschange";
static NSString *const EVENT_HTTP               = @"http";
static NSString *const EVENT_SCHEDULE           = @"schedule";
static NSString *const EVENT_GEOFENCE           = @"geofence";
static NSString *const EVENT_HEARTBEAT          = @"heartbeat";
static NSString *const EVENT_POWERSAVECHANGE    = @"powersavechange";
static NSString *const EVENT_CONNECTIVITYCHANGE = @"connectivitychange";
static NSString *const EVENT_ENABLEDCHANGE      = @"enabledchange";
static NSString *const EVENT_NOTIFICATIONACTION = @"notificationaction";
static NSString *const EVENT_AUTHORIZATION      = @"authorization";

@implementation BgGeolocation {
  BOOL   _ready;
  NSInteger _watchId;
  TSLocationManager *_engine;   // our Swift engine instance
}

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup { return YES; }

- (instancetype)init {
  self = [super init];
  if (self) {
    _ready  = NO;
    _watchId = -1;
    _engine = [TSLocationManager sharedInstance];
  }
  return self;
}

- (NSArray<NSString *> *)supportedEvents {
  return @[
    EVENT_LOCATION, EVENT_WATCHPOSITION, EVENT_PROVIDERCHANGE, EVENT_MOTIONCHANGE,
    EVENT_ACTIVITYCHANGE, EVENT_GEOFENCESCHANGE, EVENT_HTTP, EVENT_SCHEDULE,
    EVENT_GEOFENCE, EVENT_HEARTBEAT, EVENT_POWERSAVECHANGE, EVENT_CONNECTIVITYCHANGE,
    EVENT_ENABLEDCHANGE, EVENT_NOTIFICATIONACTION, EVENT_AUTHORIZATION,
  ];
}

// ─── Event listeners ──────────────────────────────────────────────────────────

- (void)registerEventListeners {
  __typeof(self) __weak me = self;

  [_engine onLocation:^(TSLocation *location) {
    [me sendEventWithName:EVENT_LOCATION body:[location toDictionary]];
  } failure:^(NSError *error) {
    [me sendEventWithName:EVENT_LOCATION body:@{@"error": @(error.code)}];
  }];

  [_engine onMotionChange:^(TSLocation *location) {
    [me sendEventWithName:EVENT_MOTIONCHANGE body:@{
      @"isMoving": @(location.isMoving),
      @"location": [location toDictionary]
    }];
  } failure:nil];

  [_engine onActivityChange:^(TSMotionActivity *activity) {
    [me sendEventWithName:EVENT_ACTIVITYCHANGE body:@{
      @"activity":   activity.name ?: @"unknown",
      @"confidence": @(activity.confidence)
    }];
  }];

  [_engine onHeartbeat:^(TSHeartbeatEvent *event) {
    [me sendEventWithName:EVENT_HEARTBEAT body:[event toDictionary]];
  }];

  [_engine onGeofence:^(TSGeofenceEvent *event) {
    [me sendEventWithName:EVENT_GEOFENCE body:[event toDictionary]];
  }];

  [_engine onHttp:^(NSDictionary *response) {
    [me sendEventWithName:EVENT_HTTP body:response];
  }];

  [_engine onProviderChange:^(TSProviderChangeEvent *event) {
    [me sendEventWithName:EVENT_PROVIDERCHANGE body:[event toDictionary]];
  }];

  [_engine onSchedule:^(TSScheduleEvent *event) {
    // TSScheduleEvent.state is Any? — safely cast to dict or send an empty marker
    NSDictionary *body = [event.state isKindOfClass:[NSDictionary class]]
      ? (NSDictionary *)event.state : @{};
    [me sendEventWithName:EVENT_SCHEDULE body:body];
  }];

  [_engine onPowerSaveChange:^(BOOL isPowerSave) {
    [me sendEventWithName:EVENT_POWERSAVECHANGE body:@(isPowerSave)];
  }];

  [_engine onConnectivityChange:^(BOOL connected) {
    [me sendEventWithName:EVENT_CONNECTIVITYCHANGE body:@{@"connected": @(connected)}];
  }];

  [_engine onEnabledChange:^(BOOL enabled) {
    [me sendEventWithName:EVENT_ENABLEDCHANGE body:@(enabled)];
  }];

  [_engine onAuthorization:^(TSAuthorizationEvent *event) {
    [me sendEventWithName:EVENT_AUTHORIZATION body:[event toDictionary]];
  }];
}

#pragma mark - Core

- (void)ready:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  if (_ready) {
    BOOL resetFlag = config[@"reset"] ? [config[@"reset"] boolValue] : YES;
    if (resetFlag) [[TSConfig sharedInstance] updateWithDictionary:config];
    success(@[[TSConfig sharedInstance].toDictionary]);
    return;
  }
  _ready = YES;

  dispatch_async(dispatch_get_main_queue(), ^{
    // Set view controller now that RN window is ready
    UIViewController *root =
      [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    if (root) { self->_engine.viewController = root; }

    @try {
      TSConfig *cfg = [TSConfig sharedInstance];
      BOOL resetFlag = config[@"reset"] ? [config[@"reset"] boolValue] : YES;

      if (cfg.isFirstBoot) {
        [cfg updateWithDictionary:config];
      } else if (resetFlag) {
        [cfg resetConfig:@{}];
        [cfg updateWithDictionary:config];
      } else {
        [cfg updateWithDictionary:config];
      }

      [self registerEventListeners];
      [self->_engine ready];
      success(@[cfg.toDictionary]);
    } @catch (NSException *e) {
      failure(@[e.reason ?: @"ready_error"]);
    }
  });
}

- (void)configure:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [self ready:config success:success failure:failure];
}

- (void)reset:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  TSConfig *cfg = [TSConfig sharedInstance];
  @try {
    if (config.count > 0) { [cfg resetConfig:@{}]; [cfg updateWithDictionary:config]; }
    else { [cfg reset]; }
    success(@[cfg.toDictionary]);
  } @catch (NSException *e) { failure(@[e.reason ?: @"reset_error"]); }
}

- (void)setConfig:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [[TSConfig sharedInstance] updateWithDictionary:config];
  success(@[[TSConfig sharedInstance].toDictionary]);
}

- (void)getState:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[[_engine getState]]);
}

#pragma mark - Lifecycle

- (void)start:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_engine start];
    success(@[[self->_engine getState]]);
  });
}

- (void)stop:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine stop];
  success(@[[_engine getState]]);
}

- (void)startSchedule:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_engine startSchedule];
    success(@[[self->_engine getState]]);
  });
}

- (void)stopSchedule:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_engine stopSchedule];
    success(@[[self->_engine getState]]);
  });
}

- (void)startGeofences:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_engine startGeofences];
    success(@[[TSConfig sharedInstance].toDictionary]);
  });
}

#pragma mark - Background task

- (void)beginBackgroundTask:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@([_engine createBackgroundTask])]);
}

- (void)finish:(double)taskId success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine stopBackgroundTask:(NSUInteger)taskId];
  success(@[@(taskId)]);
}

#pragma mark - Motion / Location

- (void)changePace:(BOOL)isMoving success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine changePace:isMoving];
  success(@[]);
}

- (void)getCurrentPosition:(NSDictionary *)options success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  TSCurrentPositionRequest *request = [TSCurrentPositionRequest requestWithSuccess:^(id location) {
    success(@[[(TSLocation *)location toDictionary]]);
  } failure:^(NSInteger code) {
    failure(@[@(code)]);
  }];
  if (options[@"timeout"])         request.timeout = [options[@"timeout"] doubleValue];
  if (options[@"maximumAge"])      request.maximumAge = [options[@"maximumAge"] doubleValue];
  if (options[@"persist"])         request.persist = [options[@"persist"] boolValue];
  if (options[@"samples"])         request.samples = [options[@"samples"] intValue];
  if (options[@"desiredAccuracy"]) request.desiredAccuracy = [options[@"desiredAccuracy"] doubleValue];
  if (options[@"extras"])          request.extras = options[@"extras"];
  [_engine getCurrentPosition:request];
}

- (void)watchPosition:(NSDictionary *)options success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  // interval is private(set) — use the factory that accepts it up front
  double interval = options[@"interval"] ? [options[@"interval"] doubleValue] : 60000.0;
  TSWatchPositionRequest *request = [TSWatchPositionRequest requestWithInterval:interval
    success:^(id location) {
      [self sendEventWithName:EVENT_WATCHPOSITION body:[(TSLocation *)location toDictionary]];
    } failure:^(NSInteger code) {}];
  if (options[@"desiredAccuracy"]) request.desiredAccuracy = [options[@"desiredAccuracy"] doubleValue];
  if (options[@"persist"])         request.persist = [options[@"persist"] boolValue];
  if (options[@"extras"])          request.extras = options[@"extras"];
  if (options[@"timeout"])         request.timeout = [options[@"timeout"] doubleValue];
  [_engine watchPosition:request]; _watchId = 0;
  success(@[]);
}

- (void)stopWatchPosition:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  if (_watchId >= 0) { [_engine stopWatchPosition:_watchId]; _watchId = -1; }
  success(@[]);
}

#pragma mark - Permissions

- (void)requestPermission:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  __typeof(self) __weak weakSelf = self;
  [_engine requestPermission:^{
    __typeof(self) __strong strongSelf = weakSelf;
    NSDictionary *state = [strongSelf->_engine getProviderState];
    success(@[state[@"status"] ?: @(3)]);
  } failure:^(NSError *error) {
    failure(@[@(error.code)]);
  }];
}

- (void)requestTemporaryFullAccuracy:(NSString *)purpose success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine requestTemporaryFullAccuracy:purpose success:^{
    success(@[@(2)]);   // 2 = full accuracy
  } failure:^(NSError *error) {
    failure(@[error.localizedDescription ?: @"accuracy_error"]);
  }];
}

- (void)getProviderState:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[[_engine getProviderState]]);
}

#pragma mark - HTTP & Persistence

- (void)getLocations:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine getLocations:^(NSArray *records) { success(@[records]); }
               failure:^(NSError *error)   { failure(@[error.localizedDescription ?: @"get_locations_error"]); }];
}

- (void)getCount:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@([_engine getCount])]);
}

- (void)destroyLocations:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine destroyLocations];
  success(@[]);
}

- (void)destroyLocation:(NSString *)uuid success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine destroyLocation:uuid success:^{ success(@[]); }
                   failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"destroy_error"]); }];
}

- (void)insertLocation:(NSDictionary *)location success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  NSDictionary *coords = location[@"coords"] ?: @{};
  CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(
    [coords[@"latitude"] doubleValue], [coords[@"longitude"] doubleValue]);
  CLLocation *cl = [[CLLocation alloc] initWithCoordinate:coord
    altitude:[coords[@"altitude"] doubleValue]
    horizontalAccuracy:[coords[@"accuracy"] doubleValue]
    verticalAccuracy:[coords[@"altitudeAccuracy"] doubleValue]
    timestamp:[NSDate date]];
  TSLocation *loc = [[TSLocation alloc] initWithLocation:cl type:@"manual" extras:location[@"extras"]];
  [_engine insertLocation:loc success:^(TSLocation *l) { success(@[[l uuid]]); }
                  failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"insert_error"]); }];
}

- (void)sync:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine sync:^(NSArray *records) { success(@[records]); }
        failure:^(NSError *error)   { failure(@[error.localizedDescription ?: @"sync_error"]); }];
}

#pragma mark - Odometer

- (void)getOdometer:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@([_engine getOdometer])]);
}

- (void)setOdometer:(double)value success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  TSCurrentPositionRequest *request = [TSCurrentPositionRequest requestWithSuccess:^(id location) {
    success(@[[(TSLocation *)location toDictionary]]);
  } failure:^(NSInteger code) {
    failure(@[@(code)]);
  }];
  [_engine setOdometer:value request:request];
}

#pragma mark - Geofences

- (void)addGeofence:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  TSGeofence *gf = [self buildGeofence:config];
  if (!gf) { failure(@[@"Invalid geofence data"]); return; }
  [_engine addGeofence:gf success:^{ success(@[]); }
              failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"geofence_error"]); }];
}

- (void)addGeofences:(NSArray *)geofences success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  NSMutableArray *list = [NSMutableArray new];
  for (NSDictionary *params in geofences) {
    TSGeofence *gf = [self buildGeofence:params];
    if (!gf) { failure(@[@"Invalid geofence data"]); return; }
    [list addObject:gf];
  }
  [_engine addGeofences:list success:^{ success(@[]); }
               failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"geofences_error"]); }];
}

- (TSGeofence *)buildGeofence:(NSDictionary *)params {
  if (!params[@"identifier"]) return nil;
  return [TSGeofence circleWithIdentifier:params[@"identifier"]
                                    radius:[params[@"radius"] doubleValue]
                                  latitude:[params[@"latitude"] doubleValue]
                                 longitude:[params[@"longitude"] doubleValue]
                             notifyOnEntry:params[@"notifyOnEntry"] ? [params[@"notifyOnEntry"] boolValue] : YES
                              notifyOnExit:params[@"notifyOnExit"]  ? [params[@"notifyOnExit"] boolValue]  : YES
                             notifyOnDwell:params[@"notifyOnDwell"] ? [params[@"notifyOnDwell"] boolValue] : NO
                            loiteringDelay:params[@"loiteringDelay"] ? [params[@"loiteringDelay"] doubleValue] : 0
                                    extras:params[@"extras"]];
}

- (void)removeGeofence:(NSString *)identifier success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine removeGeofence:identifier success:^{ success(@[]); }
                 failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"remove_geofence_error"]); }];
}

- (void)removeGeofences:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine removeGeofences:@[] success:^{ success(@[]); }
                  failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"remove_geofences_error"]); }];
}

- (void)getGeofences:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine getGeofences:^(NSArray *geofences) {
    NSMutableArray *result = [NSMutableArray new];
    for (TSGeofence *g in geofences) [result addObject:[g toDictionary]];
    success(@[result]);
  } failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"get_geofences_error"]); }];
}

- (void)getGeofence:(NSString *)identifier success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine getGeofence:identifier success:^(TSGeofence *g) { success(@[[g toDictionary]]); }
              failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"get_geofence_error"]); }];
}

- (void)geofenceExists:(NSString *)identifier callback:(RCTResponseSenderBlock)callback {
  [_engine geofenceExists:identifier callback:^(BOOL exists) { callback(@[@(exists)]); }];
}

#pragma mark - Logging

- (void)log:(NSString *)level message:(NSString *)message {
  [_engine log:level message:message];
}

- (void)setLogLevel:(double)value success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [[TSConfig sharedInstance] updateWithDictionary:@{@"logLevel": @(value)}];
  success(@[[TSConfig sharedInstance].toDictionary]);
}

- (void)getLog:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  LogQuery *query = [[LogQuery alloc] init];
  [_engine getLog:query success:^(NSDictionary *result) {
    // Convert log entries array to JSON string for JS compatibility
    NSArray *entries = result[@"log"] ?: @[];
    NSData *data = [NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
    NSString *json = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"[]";
    success(@[json]);
  } failure:^(NSError *error) {
    failure(@[error.localizedDescription ?: @"get_log_error"]);
  }];
}

- (void)destroyLog:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine destroyLog];
  success(@[]);
}

- (void)emailLog:(NSString *)email success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine emailLog:email success:^{ success(@[]); }
            failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"email_log_error"]); }];
}

#pragma mark - Utility

- (void)isPowerSaveMode:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@([_engine isPowerSaveMode])]);
}

- (void)getSensors:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@{
    @"platform":       @"ios",
    @"accelerometer":  @([_engine isAccelerometerAvailable]),
    @"gyroscope":      @([_engine isGyroAvailable]),
    @"magnetometer":   @([_engine isMagnetometerAvailable]),
    @"motionHardware": @([_engine isMotionHardwareAvailable]),
  }]);
}

- (void)getDeviceInfo:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  success(@[@{
    @"platform":      @"ios",
    @"manufacturer":  @"Apple",
    @"model":         [[UIDevice currentDevice] model],
    @"version":       [[UIDevice currentDevice] systemVersion],
    @"framework":     @"react-native",
  }]);
}

- (void)playSound:(double)soundId {
  [_engine playSound:(SystemSoundID)soundId];
}

#pragma mark - Lifecycle

- (void)dealloc {
  [_engine removeListeners];
  _engine = nil;
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeBgGeolocationSpecJSI>(params);
}
#endif

@end

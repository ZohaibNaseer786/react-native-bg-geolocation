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
static NSString *const EVENT_LOCATIONPUSH       = @"locationpush";

// Bridges the app's background-push handler (AppDelegate) to JS and back.
// AppDelegate posts BACKGROUND with userInfo {requestId, locationQueryId};
// the module emits the JS "locationpush" event. When JS calls
// finishLocationPush(requestId) the module posts FINISHED so AppDelegate can
// invoke the stored UIBackgroundFetchResult completion handler.
static NSString *const NOTIF_LOCATIONPUSH_BACKGROUND = @"BGLocationPushBackground";
static NSString *const NOTIF_LOCATIONPUSH_FINISHED   = @"BGLocationPushFinished";

@implementation BgGeolocation {
  BOOL   _ready;
  NSInteger _watchId;
  BGLocationManager *_engine;   // our Swift engine instance
}

RCT_EXPORT_MODULE();

+ (BOOL)requiresMainQueueSetup { return YES; }

- (instancetype)init {
  self = [super init];
  if (self) {
    _ready  = NO;
    _watchId = -1;
    _engine = [BGLocationManager sharedInstance];
  }
  return self;
}

- (NSArray<NSString *> *)supportedEvents {
  return @[
    EVENT_LOCATION, EVENT_WATCHPOSITION, EVENT_PROVIDERCHANGE, EVENT_MOTIONCHANGE,
    EVENT_ACTIVITYCHANGE, EVENT_GEOFENCESCHANGE, EVENT_HTTP, EVENT_SCHEDULE,
    EVENT_GEOFENCE, EVENT_HEARTBEAT, EVENT_POWERSAVECHANGE, EVENT_CONNECTIVITYCHANGE,
    EVENT_ENABLEDCHANGE, EVENT_NOTIFICATIONACTION, EVENT_AUTHORIZATION,
    EVENT_LOCATIONPUSH,
  ];
}

// ─── Event listeners ──────────────────────────────────────────────────────────

- (void)registerEventListeners {
  __typeof(self) __weak me = self;

  [_engine onLocation:^(BGLocation *location) {
    [me sendEventWithName:EVENT_LOCATION body:[location toDictionary]];
  } failure:^(NSError *error) {
    [me sendEventWithName:EVENT_LOCATION body:@{@"error": @(error.code)}];
  }];

  [_engine onMotionChange:^(BGLocation *location) {
    [me sendEventWithName:EVENT_MOTIONCHANGE body:@{
      @"isMoving": @(location.isMoving),
      @"location": [location toDictionary]
    }];
  } failure:nil];

  [_engine onActivityChange:^(BGMotionActivity *activity) {
    [me sendEventWithName:EVENT_ACTIVITYCHANGE body:@{
      @"activity":   activity.name ?: @"unknown",
      @"confidence": @(activity.confidence)
    }];
  }];

  [_engine onHeartbeat:^(BGHeartbeatEvent *event) {
    [me sendEventWithName:EVENT_HEARTBEAT body:[event toDictionary]];
  }];

  [_engine onGeofence:^(BGGeofenceEvent *event) {
    [me sendEventWithName:EVENT_GEOFENCE body:[event toDictionary]];
  }];

  [_engine onHttp:^(NSDictionary *response) {
    [me sendEventWithName:EVENT_HTTP body:response];
  }];

  [_engine onProviderChange:^(BGProviderChangeEvent *event) {
    [me sendEventWithName:EVENT_PROVIDERCHANGE body:[event toDictionary]];
  }];

  [_engine onSchedule:^(BGScheduleEvent *event) {
    // BGScheduleEvent.state is Any? — safely cast to dict or send an empty marker
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

  [_engine onAuthorization:^(BGAuthorizationEvent *event) {
    [me sendEventWithName:EVENT_AUTHORIZATION body:[event toDictionary]];
  }];

  // Relay AppDelegate background location-pushes to JS. Registered once.
  // Native captures the location with our engine, then hands it to JS — JS owns
  // delivery (socket/REST). Only runs while the app process is alive; kill-state
  // pushes are handled entirely by the LocationPushExtension.
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [[NSNotificationCenter defaultCenter]
        addObserverForName:NOTIF_LOCATIONPUSH_BACKGROUND
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
      __strong __typeof(me) strongMe = me;
      if (!strongMe) return;
      NSString *requestId = note.userInfo[@"requestId"] ?: @"";
      id queryId          = note.userInfo[@"locationQueryId"] ?: [NSNull null];

      BGCurrentPositionRequest *request =
        [BGCurrentPositionRequest requestWithSuccess:^(id locationObj) {
          BGLocation *tsLocation = (BGLocation *)locationObj;
          CLLocation *loc = tsLocation.location;
          NSDictionary *dict = [tsLocation toDictionary];

          // Deliver NATIVELY (socket → REST) so it works even when the RN bridge
          // isn't alive on a background/kill-state wake. JS is notified after,
          // with delivered=YES so the host app does NOT re-send.
          void (^afterDeliver)(BOOL) = ^(BOOL delivered) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [strongMe sendEventWithName:EVENT_LOCATIONPUSH body:@{
                @"requestId":       requestId,
                @"locationQueryId": queryId,
                @"location":        dict ?: [NSNull null],
                @"delivered":       @(delivered),
              }];
              // Release the app without depending on JS calling finishLocationPush.
              [[NSNotificationCenter defaultCenter]
                  postNotificationName:NOTIF_LOCATIONPUSH_FINISHED
                                object:nil
                              userInfo:@{@"requestId": requestId}];
            });
          };

          if (loc != nil) {
            CLLocationCoordinate2D c = loc.coordinate;
            NSString *ts = [strongMe iso8601StringFromDate:loc.timestamp];
            [BGLocationPushDeliverer deliverWithLatitude:c.latitude
                                               longitude:c.longitude
                                                accuracy:MAX(loc.horizontalAccuracy, 0)
                                                   speed:loc.speed
                                                 heading:loc.course
                                                altitude:loc.altitude
                                            timestampISO:ts
                                                 queryId:(queryId == [NSNull null] ? @"" : queryId)
                                              completion:^(BOOL ok) { afterDeliver(ok); }];
          } else {
            afterDeliver(NO);
          }
        } failure:^(NSInteger code) {
          [strongMe sendEventWithName:EVENT_LOCATIONPUSH body:@{
            @"requestId":       requestId,
            @"locationQueryId": queryId,
            @"error":           @(code),
            @"delivered":       @(NO),
          }];
          [[NSNotificationCenter defaultCenter]
              postNotificationName:NOTIF_LOCATIONPUSH_FINISHED
                            object:nil
                          userInfo:@{@"requestId": requestId}];
        }];
      request.timeout         = 20;
      request.samples         = 1;
      request.desiredAccuracy = 10;
      request.persist         = NO;
      [strongMe->_engine getCurrentPosition:request];
    }];
  });
}

#pragma mark - Core

- (void)ready:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  if (_ready) {
    BOOL resetFlag = config[@"reset"] ? [config[@"reset"] boolValue] : YES;
    if (resetFlag) [[BGConfig sharedInstance] updateWithDictionary:config];
    success(@[[BGConfig sharedInstance].toDictionary]);
    return;
  }
  _ready = YES;

  dispatch_async(dispatch_get_main_queue(), ^{
    // Set view controller now that RN window is ready
    UIViewController *root =
      [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    if (root) { self->_engine.viewController = root; }

    @try {
      BGConfig *cfg = [BGConfig sharedInstance];
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
  BGConfig *cfg = [BGConfig sharedInstance];
  @try {
    if (config.count > 0) { [cfg resetConfig:@{}]; [cfg updateWithDictionary:config]; }
    else { [cfg reset]; }
    success(@[cfg.toDictionary]);
  } @catch (NSException *e) { failure(@[e.reason ?: @"reset_error"]); }
}

- (void)setConfig:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [[BGConfig sharedInstance] updateWithDictionary:config];
  success(@[[BGConfig sharedInstance].toDictionary]);
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
    success(@[[BGConfig sharedInstance].toDictionary]);
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
  BGCurrentPositionRequest *request = [BGCurrentPositionRequest requestWithSuccess:^(id location) {
    success(@[[(BGLocation *)location toDictionary]]);
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
  BGWatchPositionRequest *request = [BGWatchPositionRequest requestWithInterval:interval
    success:^(id location) {
      [self sendEventWithName:EVENT_WATCHPOSITION body:[(BGLocation *)location toDictionary]];
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

- (void)requestMotionPermission:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  CMMotionActivityManager *motionManager = [CMMotionActivityManager new];
  [motionManager queryActivityStartingFromDate:[NSDate date]
                                        toDate:[NSDate date]
                                       toQueue:NSOperationQueue.mainQueue
                                   withHandler:^(__unused NSArray<CMMotionActivity *> *activities, __unused NSError *error) {
    success(@[@([CMMotionActivityManager authorizationStatus])]);
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
  BGLocation *loc = [[BGLocation alloc] initWithLocation:cl type:@"manual" extras:location[@"extras"]];
  [_engine insertLocation:loc success:^(BGLocation *l) { success(@[[l uuid]]); }
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
  BGCurrentPositionRequest *request = [BGCurrentPositionRequest requestWithSuccess:^(id location) {
    success(@[[(BGLocation *)location toDictionary]]);
  } failure:^(NSInteger code) {
    failure(@[@(code)]);
  }];
  [_engine setOdometer:value request:request];
}

#pragma mark - Geofences

- (void)addGeofence:(NSDictionary *)config success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  BGGeofence *gf = [self buildGeofence:config];
  if (!gf) { failure(@[@"Invalid geofence data"]); return; }
  [_engine addGeofence:gf success:^{ success(@[]); }
              failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"geofence_error"]); }];
}

- (void)addGeofences:(NSArray *)geofences success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  NSMutableArray *list = [NSMutableArray new];
  for (NSDictionary *params in geofences) {
    BGGeofence *gf = [self buildGeofence:params];
    if (!gf) { failure(@[@"Invalid geofence data"]); return; }
    [list addObject:gf];
  }
  [_engine addGeofences:list success:^{ success(@[]); }
               failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"geofences_error"]); }];
}

- (BGGeofence *)buildGeofence:(NSDictionary *)params {
  if (!params[@"identifier"]) return nil;
  return [BGGeofence circleWithIdentifier:params[@"identifier"]
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
    for (BGGeofence *g in geofences) [result addObject:[g toDictionary]];
    success(@[result]);
  } failure:^(NSError *error) { failure(@[error.localizedDescription ?: @"get_geofences_error"]); }];
}

- (void)getGeofence:(NSString *)identifier success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  [_engine getGeofence:identifier success:^(BGGeofence *g) { success(@[[g toDictionary]]); }
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
  [[BGConfig sharedInstance] updateWithDictionary:@{@"logLevel": @(value)}];
  success(@[[BGConfig sharedInstance].toDictionary]);
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
    @"motionAuthorizationStatus": @([CMMotionActivityManager authorizationStatus]),
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

- (void)getLocationPushToken:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  NSString *token = [[NSUserDefaults standardUserDefaults]
                     stringForKey:@"TSLocationManager_locationPushToken"];
  success(@[token ?: [NSNull null]]);
}

- (void)getApnsDeviceToken:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure {
  NSString *token = [[NSUserDefaults standardUserDefaults]
                     stringForKey:@"TSLocationManager_apnsDeviceToken"];
  success(@[token ?: [NSNull null]]);
}

- (void)setLocationPushConfig:(NSDictionary *)config
                      success:(RCTResponseSenderBlock)success
                      failure:(RCTResponseSenderBlock)failure {
  [_engine setLocationPushConfig:(config ?: @{})];
  success(@[]);
}

- (NSString *)iso8601StringFromDate:(NSDate *)date {
  static NSISO8601DateFormatter *formatter;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                              NSISO8601DateFormatWithFractionalSeconds;
  });
  return [formatter stringFromDate:(date ?: [NSDate date])];
}

- (void)finishLocationPush:(NSString *)requestId
                   success:(RCTResponseSenderBlock)success
                   failure:(RCTResponseSenderBlock)failure {
  [[NSNotificationCenter defaultCenter]
      postNotificationName:NOTIF_LOCATIONPUSH_FINISHED
                    object:nil
                  userInfo:@{@"requestId": requestId ?: @""}];
  success(@[]);
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

// ─── Native kill-state / background launch bootstrap ─────────────────────────
// A TurboModule is instantiated LAZILY — only when JS first touches it. On an
// iOS location relaunch after system termination (significant-location-change
// or stationary-region exit), the OS launches the app in the background and expects the queued Core
// Location event to be delivered to a CLLocationManager that, at that instant,
// does not exist yet. Waiting for the React Native bridge + JS bundle to boot
// and import this module often loses the brief background wake window.
//
// This standalone class eagerly constructs the engine at class-load time and
// also observes UIApplicationDidFinishLaunchingNotification — recreating the
// CLLocationManager, installing the BGCLRouter delegate, and (via auto-resume)
// re-arming SLC/region + native HTTP delivery — independently of React Native.
// (It lives in its own class because BgGeolocation's +load is already provided
// by the RCT_EXPORT_MODULE() macro, so a second +load there would collide.)
@interface BGLaunchBootstrap : NSObject
@end

@implementation BGLaunchBootstrap

+ (void)bootstrapFromNotification:(NSNotification *)note phase:(NSString *)phase {
    BOOL launchedForLocation =
        note.userInfo[UIApplicationLaunchOptionsLocationKey] != nil;
    BOOL inBackground =
        [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
    if (launchedForLocation || inBackground) {
      [[NSUserDefaults standardUserDefaults] setBool:YES
                                              forKey:@"TSLocationManager_didLaunchInBackground"];
      [[NSUserDefaults standardUserDefaults] synchronize];
    }
    // Diagnostic marker — visible in the iOS unified log (`log show` /
    // `log collect`) even for a location-triggered kill-state relaunch with no JS.
    NSLog(@"[BGGEO] %@Launching: launchedForLocation=%d inBackground=%d",
          phase, launchedForLocation, inBackground);
    // Bootstrap the engine now, before/independent of the RN bridge. The
    // singleton's setupCoreLocation runs auto-resume when tracking was persisted
    // enabled; on a normal foreground launch with tracking disabled this just
    // creates + configures the (idle) manager, which is harmless.
    BGLocationManager *manager = [BGLocationManager sharedInstance];
    if (launchedForLocation || inBackground) {
      [manager ready];
    }
}

+ (void)load {
  // For a previously-enabled tracker, persisted config is enough to resume the
  // engine before React Native or the application delegate has finished booting.
  // CLLocationManager is created on the main thread by BGLocationManager.
  (void)[BGLocationManager sharedInstance];

  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                      object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(NSNotification *note) {
    [self bootstrapFromNotification:note phase:@"didFinish"];
  }];
}

@end

#import "include/device_screen_brightness/DeviceScreenBrightnessPlugin.h"
#import "device_screen_brightness_native.h"

static NSString *const DSBMethodChannelName = @"dev.arcas.device_screen_brightness/methods";
static NSString *const DSBEventChannelName = @"dev.arcas.device_screen_brightness/events";

@interface DeviceScreenBrightnessPlugin ()
@property(nonatomic, copy, nullable) FlutterEventSink eventSink;
@property(nonatomic, strong, nullable) NSTimer *pollTimer;
@property(nonatomic, strong) dispatch_queue_t workerQueue;
@property(nonatomic, strong, nullable) NSNumber *lastValue;
@property(nonatomic, assign) BOOL pollInFlight;
@end

@implementation DeviceScreenBrightnessPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  DeviceScreenBrightnessPlugin *instance = [[DeviceScreenBrightnessPlugin alloc] init];
  instance.workerQueue = dispatch_queue_create("dev.arcas.device_screen_brightness.macos", DISPATCH_QUEUE_SERIAL);
  FlutterMethodChannel *methods =
      [FlutterMethodChannel methodChannelWithName:DSBMethodChannelName
                                  binaryMessenger:registrar.messenger];
  FlutterEventChannel *events =
      [FlutterEventChannel eventChannelWithName:DSBEventChannelName
                                binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:instance channel:methods];
  [events setStreamHandler:instance];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"hasPermission"]) {
    result(@YES);
    return;
  }
  if ([call.method isEqualToString:@"requestPermission"]) {
    result(nil);
    return;
  }

  NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]]
                                ? call.arguments
                                : @{};
  dispatch_async(self.workerQueue, ^{
    DeviceScreenBrightnessResult nativeResult;
    BOOL hasNativeResult = YES;

    if ([call.method isEqualToString:@"getBrightness"]) {
      nativeResult = device_screen_brightness_get();
    } else if ([call.method isEqualToString:@"setBrightness"]) {
      NSNumber *value = arguments[@"value"];
      if (![value isKindOfClass:[NSNumber class]] || value.integerValue < 0 || value.integerValue > 100) {
        dispatch_async(dispatch_get_main_queue(), ^{
          result([FlutterError errorWithCode:@"invalid_brightness_value"
                                     message:@"Brightness must be between 0 and 100."
                                     details:@{ @"platform": @"macos", @"operation": call.method }]);
        });
        return;
      }
      nativeResult = device_screen_brightness_set((int32_t)value.intValue);
    } else if ([call.method isEqualToString:@"adjustBrightness"]) {
      NSString *direction = arguments[@"direction"];
      if ([direction isEqualToString:@"increase"]) {
        nativeResult = device_screen_brightness_increment();
      } else if ([direction isEqualToString:@"decrease"]) {
        nativeResult = device_screen_brightness_decrement();
      } else {
        dispatch_async(dispatch_get_main_queue(), ^{
          result([FlutterError errorWithCode:@"invalid_brightness_value"
                                     message:@"Invalid adjustment direction."
                                     details:@{ @"platform": @"macos", @"operation": call.method }]);
        });
        return;
      }
    } else if ([call.method isEqualToString:@"getCapabilities"]) {
      nativeResult = device_screen_brightness_get();
      hasNativeResult = NO;
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{ result(FlutterMethodNotImplemented); });
      return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      if ([call.method isEqualToString:@"getCapabilities"]) {
        BOOL available = nativeResult.error_code == DSB_OK;
        result(@{
          @"canRead": @(available),
          @"canWrite": @(available),
          @"canObserve": @(available),
          @"writeSupport": available ? @"bestEffort" : @"unsupported",
          @"supportedModes": @[ @"system" ],
          @"requiresWriteSettingsPermission": @NO,
          @"backend": @"macos-display-services-or-ddc",
        });
      } else if (hasNativeResult && nativeResult.error_code == DSB_OK) {
        result(@{ @"value": @(nativeResult.value) });
      } else {
        result([self flutterErrorForResult:nativeResult operation:call.method]);
      }
    });
  });
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  self.eventSink = events;
  self.lastValue = nil;
  [self pollBrightness];
  self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                   target:self
                                                 selector:@selector(pollBrightness)
                                                 userInfo:nil
                                                  repeats:YES];
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  [self.pollTimer invalidate];
  self.pollTimer = nil;
  self.eventSink = nil;
  self.lastValue = nil;
  return nil;
}

- (void)pollBrightness {
  if (!self.eventSink || self.pollInFlight) return;
  self.pollInFlight = YES;
  dispatch_async(self.workerQueue, ^{
    DeviceScreenBrightnessResult nativeResult = device_screen_brightness_get();
    dispatch_async(dispatch_get_main_queue(), ^{
      self.pollInFlight = NO;
      if (!self.eventSink) return;
      if (nativeResult.error_code != DSB_OK) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
        self.eventSink([self flutterErrorForResult:nativeResult operation:@"streamBrightness"]);
        return;
      }
      NSNumber *value = @(nativeResult.value);
      if (![value isEqualToNumber:self.lastValue]) {
        self.lastValue = value;
        self.eventSink(@{ @"value": value, @"mode": @"system" });
      }
    });
  });
}

- (FlutterError *)flutterErrorForResult:(DeviceScreenBrightnessResult)nativeResult
                              operation:(NSString *)operation {
  NSString *code = @"native_backend_failure";
  NSString *message = @"The macOS brightness backend failed.";
  switch (nativeResult.error_code) {
    case DSB_UNSUPPORTED_OPERATION:
      code = @"unsupported_operation";
      message = @"This brightness operation is unsupported.";
      break;
    case DSB_PERMISSION_DENIED:
      code = @"permission_denied";
      message = @"macOS denied the brightness operation.";
      break;
    case DSB_INVALID_VALUE:
      code = @"invalid_brightness_value";
      message = @"Brightness must be between 0 and 100.";
      break;
    case DSB_BACKEND_NOT_AVAILABLE:
      code = @"backend_not_available";
      message = @"No compatible macOS display brightness backend is available.";
      break;
    default:
      break;
  }
  return [FlutterError errorWithCode:code
                             message:message
                             details:@{
                               @"platform": @"macos",
                               @"operation": operation,
                               @"nativeCode": @(nativeResult.error_code),
                             }];
}

@end

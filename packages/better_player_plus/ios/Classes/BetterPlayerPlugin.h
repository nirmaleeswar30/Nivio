#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

@interface BetterPlayerPlugin : NSObject<FlutterPlugin>
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar;
@end

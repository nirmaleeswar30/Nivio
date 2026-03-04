#import "BetterPlayerPlugin.h"
#if __has_include(<better_player_plus/better_player_plus-Swift.h>)
#import <better_player_plus/better_player_plus-Swift.h>
#else
#import "better_player_plus-Swift.h"
#endif

@implementation BetterPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftBetterPlayerPlugin registerWithRegistrar:registrar];
}
@end

Pod::Spec.new do |s|
  s.name             = 'device_screen_brightness'
  s.version          = '2.0.0'
  s.summary          = 'Control and observe screen brightness through Flutter channels.'
  s.description      = <<-DESC
Flutter plugin for macOS display brightness using DisplayServices for Apple
displays and IOAVService DDC/CI for compatible external displays.
                       DESC
  s.homepage         = 'https://github.com/arcas0803/device_screen_brightness'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ArcasHH' => 'alvaroarcasgarcia@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'device_screen_brightness/Sources/device_screen_brightness/**/*.{h,m}'
  s.public_header_files = 'device_screen_brightness/Sources/device_screen_brightness/include/device_screen_brightness/DeviceScreenBrightnessPlugin.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.frameworks = 'CoreGraphics', 'IOKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end

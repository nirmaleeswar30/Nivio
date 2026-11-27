Pod::Spec.new do |s|
  s.name             = 'device_screen_brightness'
  s.version          = '2.0.0'
  s.summary          = 'Control and observe screen brightness through Flutter channels.'
  s.description      = <<-DESC
Flutter plugin for reading, writing, and observing iOS screen brightness using
UIScreen and Flutter platform channels.
                       DESC
  s.homepage         = 'https://github.com/arcas0803/device_screen_brightness'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ArcasHH' => 'alvaroarcasgarcia@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'device_screen_brightness/Sources/device_screen_brightness/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'UIKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end

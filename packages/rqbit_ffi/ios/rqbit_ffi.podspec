# rqbit_ffi for iOS: vendors rqbit_ffi.xcframework, a dynamic framework
# wrapping the Rust cdylib (librqbit). Build it with build_xcframework.sh
# (the Nivio Podfile does that automatically when it is missing). Dart loads
# it with DynamicLibrary.open('rqbit_ffi.framework/rqbit_ffi').
Pod::Spec.new do |s|
  s.name             = 'rqbit_ffi'
  s.version          = '0.1.0'
  s.summary          = 'Embedded rqbit BitTorrent streaming engine for Nivio.'
  s.description      = 'Thin C-ABI wrapper around librqbit, booting its HTTP API on localhost.'
  s.homepage         = 'https://github.com/ikatson/rqbit'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Nivio' => 'nivio@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/rqbit_ffi.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end

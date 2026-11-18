# Vendors CurlImpersonate.xcframework (libcurl-impersonate as a dynamic
# framework), built by build_curl_framework.sh. The Nivio Podfile builds it when
# it is missing. Dart opens CurlImpersonate.framework/CurlImpersonate.
Pod::Spec.new do |s|
  s.name             = 'nivio_curl'
  s.version          = '0.1.0'
  s.summary          = 'libcurl-impersonate for Nivio on iOS.'
  s.description      = 'Browser-fingerprinted HTTP for package:http on iOS.'
  s.homepage         = 'https://github.com/lexiforest/curl-impersonate'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Nivio' => 'nivio@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/CurlImpersonate.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end

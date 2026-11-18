# Nivio's media_kit_libs_ios_video: vendors Frameworks/Mpv.xcframework, built by
# build_mpv_framework.sh from edde746/mpv-build's static iOS libraries (libmpv
# with vo=avfoundation, FFmpeg with Dolby Vision patches, libass, libplacebo...)
# linked into one dynamic framework that exports the mpv_* API. media_kit opens
# it as Mpv.framework/Mpv; media_kit_video links it through
# Frameworks/.symlinks/mpv/ios (see its podspec).
Pod::Spec.new do |s|
  s.name             = 'media_kit_libs_ios_video'
  s.version          = '1.1.4'
  s.summary          = 'libmpv for Nivio on iOS (edde746/mpv-build).'
  s.description      = 'libmpv with the AVFoundation video output, as Mpv.framework.'
  s.homepage         = 'https://github.com/edde746/mpv-build'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'Nivio' => 'nivio@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/Mpv.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
  s.swift_version = '5.0'
end

#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rust_lib_sableen.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rust_lib_sableen'
  s.version          = '1.0.1'
  s.summary          = 'Rust catalog, watch history and recommendations for Sableen.'
  s.homepage         = 'https://github.com/blueokanna/Sableen'
  s.license          = { :type => 'PolyForm Noncommercial 1.0.0', :file => '../../LICENSE' }
  s.author           = 'Sableen contributors'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => '/bin/bash "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust_lib_sableen',
    :execution_position => :before_compile,
    :always_out_of_date => '1',
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${BUILT_PRODUCTS_DIR}/librust_lib_sableen.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${BUILT_PRODUCTS_DIR}/librust_lib_sableen.a"',
  }
end

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'web_video_stub.dart'
    if (dart.library.js_interop) 'web_video.dart'
    as browser;

const displayChannel = OptionalMethodChannel('sableen/display');
bool get androidVideo =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<bool> supportsSmallWindow() async => kIsWeb
    ? browser.supportsPictureInPicture == true
    : androidVideo &&
          await displayChannel.invokeMethod<bool>('supportsPip') == true;

Future<bool> enterSmallWindow(double ratio) async => kIsWeb
    ? browser.enterPictureInPicture()
    : androidVideo &&
          await displayChannel.invokeMethod<bool>('enterPip', ratio) == true;

void Function() observeBrowserPipExit(void Function() update) =>
    browser.onExitPictureInPicture(update);

Future<bool> videoInSmallWindow() async {
  if (kIsWeb) return browser.inPictureInPicture;
  return androidVideo &&
      await displayChannel.invokeMethod<bool>('isPip') == true;
}

Future<void> setTheaterFullscreen(bool enabled) async {
  if (!kIsWeb &&
      (androidVideo || defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  } else if (enabled) {
    await defaultEnterNativeFullscreen();
  } else {
    await defaultExitNativeFullscreen();
  }
}

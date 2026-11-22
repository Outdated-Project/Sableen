import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show BuildContext, View;
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

Future<void> _macWindowChange = Future<void>.value();

bool playbackOnPhone(BuildContext context) {
  if (kIsWeb ||
      !(androidVideo || defaultTargetPlatform == TargetPlatform.iOS)) {
    return false;
  }
  final display = View.of(context).display;
  return display.size.shortestSide / display.devicePixelRatio < 600;
}

enum PhoneOrientation { automatic, landscape, portrait }

Future<void> setPhoneOrientation(PhoneOrientation orientation) async {
  try {
    if (androidVideo) {
      await displayChannel.invokeMethod<void>(
        'setPlaybackOrientation',
        orientation.name,
      );
      return;
    }
    await SystemChrome.setPreferredOrientations(switch (orientation) {
      PhoneOrientation.automatic => [],
      PhoneOrientation.landscape => [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      PhoneOrientation.portrait => [DeviceOrientation.portraitUp],
    });
  } on PlatformException catch (error) {
    debugPrint('Device orientation request declined: ${error.code}');
  }
}

Future<void> setTheaterFullscreen(bool enabled) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    // A second card can open while the first window is still leaving fullscreen.
    _macWindowChange = _macWindowChange.then((_) async {
      try {
        await const MethodChannel('sableen/video')
            .invokeMethod<bool>('setFullscreen', enabled);
      } on PlatformException catch (error) {
        debugPrint('macOS fullscreen request failed: $error');
      }
    });
    return _macWindowChange;
  }
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

import 'dart:js_interop';

@JS('document.pictureInPictureElement')
external JSObject? get _pictureInPictureElement;

bool get inPictureInPicture => _pictureInPictureElement != null;

@JS('document.pictureInPictureEnabled')
external bool? get supportsPictureInPicture;

extension type _Video(JSObject _) implements JSObject {
  external JSPromise<JSObject> requestPictureInPicture();
}

@JS('document.querySelector')
external _Video? _element(String selector);

@JS('document.addEventListener')
external void _addListener(String name, JSFunction callback, bool capture);

@JS('document.removeEventListener')
external void _removeListener(String name, JSFunction callback, bool capture);

void Function() onExitPictureInPicture(void Function() update) {
  final listener = ((JSObject event) => update()).toJS;
  _addListener('leavepictureinpicture', listener, true);
  return () => _removeListener('leavepictureinpicture', listener, true);
}

Future<bool> enterPictureInPicture() async {
  final video = _element('video');
  if (video == null) return false;
  try {
    await video.requestPictureInPicture().toDart;
    return true;
  } catch (_) {
    return false;
  }
}

import 'dart:js_interop';

@JS('document.pictureInPictureElement')
external JSObject? get _pictureInPictureElement;

bool get inPictureInPicture => _pictureInPictureElement != null;

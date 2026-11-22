import 'src/rust/api/library.dart';

extension EpisodeMedia on Episode {
  bool get isFullLength =>
      listedMs != null &&
      listedMs! > 0 &&
      durationMs != null &&
      (durationMs! - listedMs!).abs() <= 1000;
  bool get isPreview =>
      durationMs != null && listedMs != null && listedMs! > 0 && !isFullLength;

  Episode withEncoding(VideoEncoding file) => Episode(
    id: id,
    title: title,
    url: file.url,
    page: page,
    bytes: file.bytes,
    sha256: file.sha256,
    durationMs: durationMs,
    listedMs: listedMs,
    encodings: encodings,
    adBreaks: adBreaks,
    mirrors: file.sha256 == sha256 ? mirrors : null,
  );

  Iterable<Episode> get files sync* {
    yield this;
    for (final file in encodings ?? const <VideoEncoding>[]) {
      if (file.sha256 != sha256) yield withEncoding(file);
    }
  }
}

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

  Episode withPlaybackRenditions(Map<String, dynamic> renditions) {
    final primary = renditions[sha256];
    if (primary == null &&
        !(encodings?.any((f) => renditions.containsKey(f.sha256)) ?? false)) {
      return this;
    }
    ({String url, String hash, int bytes}) asset(dynamic record) {
      if (record case {'sha256': final String hash, 'bytes': final int bytes}
          when RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) && bytes > 0) {
        return (
          url: 'asset:///assets/renditions/$hash.mp4',
          hash: hash,
          bytes: bytes,
        );
      }
      throw const FormatException('Invalid playback rendition');
    }

    final main = primary == null ? null : asset(primary);
    return Episode(
      id: id,
      title: title,
      page: page,
      adBreaks: adBreaks,
      durationMs: durationMs,
      listedMs: listedMs,
      url: main?.url ?? url,
      sha256: main?.hash ?? sha256,
      bytes: main?.bytes ?? bytes,
      mirrors: main == null ? mirrors : null,
      encodings: encodings
          ?.map((f) {
            final record = renditions[f.sha256];
            if (record == null) return f;
            final converted = asset(record);
            return VideoEncoding(
              width: f.width,
              height: f.height,
              url: converted.url,
              bytes: converted.bytes,
              sha256: converted.hash,
            );
          })
          .toList(growable: false),
    );
  }

  Iterable<Episode> get files sync* {
    yield this;
    for (final file in encodings ?? const <VideoEncoding>[]) {
      if (file.sha256 != sha256) yield withEncoding(file);
    }
  }
}

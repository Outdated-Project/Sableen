import 'src/rust/api/library.dart';

extension DramaPlayback on Drama {
  Drama forPlayback(Map<String, dynamic> renditions) {
    final order = publishedIds ?? [for (final episode in episodes) episode.id];
    final full = {
      for (final e in episodes)
        if (e.isFullLength && e.sha256 != null && (e.bytes ?? 0) > 0) e.id: e,
    };
    return Drama(
      id: id,
      title: title,
      tags: tags,
      cover: cover,
      episodeCount: episodeCount,
      publishedIds: order,
      episodes: [
        for (final id in order)
          if (full[id] case final episode?)
            episode.withPlaybackRenditions(renditions),
      ],
    );
  }

  int? nextEpisodeIndex(int current) {
    final ids = publishedIds;
    if (ids == null) {
      final next = current + 1;
      return next < episodes.length && episodes[next].isFullLength
          ? next
          : null;
    }
    final position = ids.indexOf(episodes[current].id);
    if (position < 0 || position + 1 == ids.length) return null;
    final next = episodes.indexWhere(
      (e) => e.id == ids[position + 1] && e.isFullLength,
    );
    return next < 0 ? null : next;
  }

  int? startingIndex({String? selectedId, Progress? last}) {
    final index = episodes.indexWhere(
      (e) => e.id == (selectedId ?? last?.episode),
    );
    if (index >= 0 && episodes[index].isFullLength) {
      if (selectedId == null &&
          last != null &&
          last.completed &&
          !episodes[index].replacesShorterCut(last)) {
        return nextEpisodeIndex(index) ?? index;
      }
      return index;
    }
    if (selectedId != null) return null;
    final firstFull = episodes.indexWhere((e) => e.isFullLength);
    return firstFull >= 0 ? firstFull : null;
  }
}

extension EpisodeMedia on Episode {
  bool get isFullLength =>
      listedMs != null &&
      listedMs! > 0 &&
      durationMs != null &&
      durationMs! > 0 &&
      (durationMs! - listedMs!).abs() <= 1000;

  bool replacesShorterCut(Progress prior) =>
      isFullLength &&
      prior.episode == id &&
      prior.durationMs > 0 &&
      prior.durationMs + 1000 < durationMs!;

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

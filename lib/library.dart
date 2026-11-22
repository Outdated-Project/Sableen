import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'src/rust/api/library.dart';

enum Publisher { hongguo, comic }

class Library extends ChangeNotifier {
  Library(this.disk);

  final SharedPreferencesAsync disk;
  // Preserve progress for Hongguo titles carried over from version 1.0.0.
  static const _historyKey = 'history.v1.builtin.public.v1';
  List<Drama> dramas = const [];
  List<Progress> history = const [];
  Map<String, Drama> byId = const {};
  Map<String, Publisher> publishers = const {};
  bool historyDamaged = false;
  bool writeFailed = false;
  Future<void> _writes = Future.value();
  Future<void> get pendingWrites => _writes;

  Future<void> restore() async {
    final titles = <String, Drama>{};
    final origins = <String, Publisher>{};
    final catalogs = <List<Drama>>[];
    final renditions = jsonDecode(
      await rootBundle.loadString('assets/renditions/index.json'),
    ) as Map<String, dynamic>;
    for (final category in Publisher.values) {
      final data = await rootBundle.load(
        'assets/catalogs/${category.name}.json',
      );
      final source = await parseCatalog(bytes: Uint8List.sublistView(data));
      final items = [
        for (final drama in source) _withRenditions(drama, renditions),
      ];
      if (items.isEmpty) throw const FormatException('Empty Hongguo category');
      catalogs.add(items);
      for (final drama in items) {
        if (titles.containsKey(drama.id)) {
          throw const FormatException('Duplicate title ID');
        }
        titles[drama.id] = drama;
        origins[drama.id] = category;
      }
    }
    byId = titles;
    // Alternate chart entries without disturbing either publisher's ranking.
    dramas = [
      for (var rank = 0; catalogs.any((items) => rank < items.length); rank++)
        for (final items in catalogs)
          if (rank < items.length) items[rank],
    ];
    publishers = origins;
    await _writes;
    try {
      final encoded = await disk.getString(_historyKey);
      if (encoded != null) {
        if (encoded.length > 2 << 20) throw const FormatException();
        final stored = await unpackHistory(bytes: base64Decode(encoded));
        history = stored
            .where(
              (p) =>
                  titles[p.drama]?.episodes.any((e) => e.id == p.episode) ==
                  true,
            )
            .toList();
      }
    } catch (_) {
      historyDamaged = true;
    }
  }

  Drama _withRenditions(Drama drama, Map<String, dynamic> renditions) {
    if (!drama.episodes.any((e) => renditions.containsKey(e.sha256))) {
      return drama;
    }
    Episode playbackFile(Episode e) {
      final record = renditions[e.sha256];
      if (record == null) return e;
      final hash = record['sha256'] as String;
      final size = record['bytes'] as int;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) || size <= 0) {
        throw const FormatException('Invalid playback rendition');
      }
      return Episode(
        id: e.id,
        title: e.title,
        page: e.page,
        adBreaks: e.adBreaks,
        url: 'asset:///assets/renditions/$hash.mp4',
        sha256: hash,
        bytes: size,
      );
    }

    return Drama(
      id: drama.id,
      title: drama.title,
      tags: drama.tags,
      cover: drama.cover,
      episodes: drama.episodes.map(playbackFile).toList(growable: false),
    );
  }

  Progress? latest(String id, [String? episode]) => history
      .where((p) => p.drama == id && (episode == null || episode == p.episode))
      .firstOrNull;

  Future<List<Drama>> ranked() async {
    final ids = await recommendations(
      candidates: [for (final d in dramas) Candidate(id: d.id, tags: d.tags)],
      entries: history,
      now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    return [for (final id in ids) ?byId[id]];
  }

  Future<void> _persist() {
    final snapshot = history;
    _writes = _writes.then((_) async {
      try {
        final data = await packHistory(entries: snapshot);
        await disk.setString(_historyKey, base64Encode(data));
        if (writeFailed) {
          writeFailed = false;
          notifyListeners();
        }
      } catch (_) {
        writeFailed = true;
        notifyListeners();
      }
    });
    return _writes;
  }

  void record(Progress entry) {
    if (historyDamaged) return;
    history = [
      entry,
      ...history
          .where((p) => p.drama != entry.drama || p.episode != entry.episode)
          .take(511),
    ];
    scheduleMicrotask(notifyListeners);
    unawaited(_persist());
  }

  Future<void> clearHistory() async {
    history = [];
    historyDamaged = false;
    notifyListeners();
    await _persist();
  }
}

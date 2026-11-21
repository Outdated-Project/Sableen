import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'src/rust/api/library.dart';

const catalogLimit = 1024 * 1024;
const defaultFeed = String.fromEnvironment('SABLEEN_CATALOG_URL');
const publicCatalog = 'builtin.public.v1';

enum Publisher { cctv, guangzhou, hongguo }

class Library extends ChangeNotifier {
  final SharedPreferencesAsync disk;
  String source = '';
  List<Drama> dramas = const [];
  List<Progress> history = const [];
  Map<String, Drama> byId = const {};
  Map<String, Publisher> publishers = const {};
  bool historyDamaged = false;
  bool writeFailed = false;
  bool busy = false;
  bool sourceFailed = false;
  Future<void> _writes = Future.value();
  Future<void> get pendingWrites => _writes;

  Library(this.disk);

  String _historyKey(String address) => 'history.v1.$address';

  Future<List<Progress>> _readHistory(String address) async {
    final encoded = await disk.getString(_historyKey(address));
    if (encoded == null) return [];
    if (encoded.length > catalogLimit * 2) throw const FormatException();
    return unpackHistory(bytes: base64Decode(encoded));
  }

  Future<void> restore() async {
    final snapshot = await disk.getString('catalog.v1');
    if (snapshot == publicCatalog ||
        (snapshot == null && defaultFeed.isEmpty)) {
      await _loadPublicCatalog();
    } else if (snapshot != null) {
      try {
        if (snapshot.length > 2 * catalogLimit) throw const FormatException();
        final record = jsonDecode(snapshot) as List;
        final address = record[0] as String;
        final next = await parseCatalog(
          bytes: base64Decode(record[1] as String),
        );
        _applySource(address, next, await _loadHistory(address));
      } catch (_) {
        await _loadPublicCatalog();
        sourceFailed = true;
      }
    } else if (defaultFeed.isNotEmpty) {
      try {
        await loadFeed(defaultFeed);
      } catch (_) {
        await _loadPublicCatalog();
        sourceFailed = true;
      }
    }
  }

  Future<void> usePublicCatalog() =>
      _change(() => _loadPublicCatalog(select: true));

  Future<void> _loadPublicCatalog({bool select = false}) async {
    final next = <Drama>[];
    final origins = <String, Publisher>{};
    for (final publisher in Publisher.values) {
      final data = await rootBundle.load(
        'assets/catalogs/${publisher.name}.json',
      );
      final items = await parseCatalog(bytes: Uint8List.sublistView(data));
      next.addAll(items);
      for (final drama in items) {
        origins[drama.id] = publisher;
      }
    }
    await _writes;
    final stored = await _loadHistory(publicCatalog);
    if (select) await disk.setString('catalog.v1', publicCatalog);
    _applySource(publicCatalog, next, stored);
    publishers = origins;
  }

  void _setCatalog(List<Drama> value) {
    dramas = value;
    byId = {for (final d in dramas) d.id: d};
  }

  Future<void> _activate(String address, Uint8List bytes) async {
    final next = await parseCatalog(bytes: bytes);
    await _writes;
    final stored = await _loadHistory(address);
    await disk.setString(
      'catalog.v1',
      jsonEncode([address, base64Encode(bytes)]),
    );
    _applySource(address, next, stored);
  }

  Future<List<Progress>?> _loadHistory(String address) async {
    try {
      return await _readHistory(address);
    } catch (_) {
      return null;
    }
  }

  void _applySource(String address, List<Drama> next, List<Progress>? stored) {
    source = address;
    publishers = const {};
    sourceFailed = false;
    _setCatalog(next);
    history = stored ?? [];
    historyDamaged = stored == null;
  }

  Future<void> _change(Future<void> Function() change) async {
    if (busy) throw StateError('busy');
    busy = true;
    notifyListeners();
    try {
      await change();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> loadFeed(String address) => _change(() async {
    if (!await validAddress(address: address)) throw const FormatException();
    final client = http.Client();
    try {
      final bytes = await _download(
        client,
        Uri.parse(address),
      ).timeout(const Duration(seconds: 20));
      await _activate(address, bytes);
    } finally {
      client.close();
    }
  });

  Future<Uint8List> _download(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client.send(request);
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > catalogLimit) {
      throw const FormatException();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.stream) {
      if (bytes.length + part.length > catalogLimit) {
        throw const FormatException();
      }
      bytes.add(part);
    }
    return bytes.takeBytes();
  }

  Future<void> addVideo(String title, String tag, String url) => _change(
    () async {
      final local = await disk.getString('direct.v1');
      final items = local == null
          ? <dynamic>[]
          : (jsonDecode(local) as Map)['dramas'] as List;
      final existing = items.indexWhere((d) => d['episodes'][0]['url'] == url);
      final id = existing < 0
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : items[existing]['id'];
      final drama = {
        'id': id,
        'title': title,
        'tags': [tag],
        'cover': null,
        'episodes': [
          {'id': '1', 'title': title, 'url': url},
        ],
      };
      if (existing >= 0) items.removeAt(existing);
      items.insert(0, drama);
      final text = jsonEncode({'version': 1, 'dramas': items});
      final bytes = utf8.encode(text);
      await parseCatalog(bytes: bytes);
      await disk.setString('direct.v1', text);
      await _activate('', bytes);
    },
  );

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
    final key = _historyKey(source);
    _writes = _writes.then((_) async {
      try {
        final data = await packHistory(entries: snapshot);
        await disk.setString(key, base64Encode(data));
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
    if (historyDamaged || busy) return;
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

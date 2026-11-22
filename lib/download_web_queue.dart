import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'download_status.dart';
import 'episode_media.dart';
import 'src/rust/api/library.dart';

String mediaUrl(Episode episode) {
  if (episode.sha256 != null &&
      !episode.url.startsWith('asset:') &&
      web.document.querySelector('meta[name="sableen-offline-worker"]') !=
          null) {
    return Uri.parse(web.document.baseURI)
        .resolve('media/${episode.sha256}.mp4')
        .toString();
  }
  return episode.url;
}

class EpisodeDownload {
  EpisodeDownload(this.title, this.episode);
  final String title;
  final Episode episode;
  DownloadState state = DownloadState.queued;
  int received = 0;
  bool busy = false;
  String error = '';
  web.AbortController? request;
}

class DownloadQueue extends ChangeNotifier {
  final jobs = <String, EpisodeDownload>{};
  final _waiting = <EpisodeDownload>[];
  bool paused = false;
  int _running = 0;
  static const chunkSize = 2 * 1024 * 1024;
  Future<web.Cache> get _cache =>
      web.window.caches.open('sableen-episodes-v1').toDart;
  String _key(Episode e) =>
      Uri.parse(web.document.baseURI)
          .resolve('media/${e.sha256}.mp4')
          .toString();

  Future<bool> _valid(web.Blob data, Episode episode) async {
    if (data.size != episode.bytes) return false;
    Stream<List<int>> chunks() async* {
      for (var pos = 0; pos < data.size; pos += chunkSize) {
        yield (await data.slice(pos, pos + chunkSize).arrayBuffer().toDart)
            .toDart
            .asUint8List();
      }
    }

    return (await sha256.bind(chunks()).first).toString() == episode.sha256;
  }

  Future<String?> localPath(Episode episode) async {
    if (episode.sha256 == null) return null;
    final cache = await _cache;
    final key = _key(episode).toJS;
    final response = await cache.match(key).toDart;
    if (response == null) return null;
    final blob = await response.blob().toDart;
    if (await _valid(blob, episode)) return web.URL.createObjectURL(blob);
    await cache.delete(key).toDart;
    return null;
  }

  void releasePath(String? path) {
    if (path != null) web.URL.revokeObjectURL(path);
  }

  Future<void> restore(List<Drama> catalog) async {
    final cache = await _cache;
    final keys = (await cache.keys().toDart).toDart.map((r) => r.url).toSet();
    for (final drama in catalog) {
      for (final e in drama.episodes.expand((episode) => episode.files)) {
        if (e.sha256 == null) continue;
        final key = _key(e);
        final old = jobs[e.sha256];
        if (old != null && old.state != DownloadState.saved) continue;
        if (keys.contains(key)) {
          jobs[e.sha256!] = EpisodeDownload(drama.title, e)
            ..state = DownloadState.saved
            ..received = e.bytes!;
        } else if (keys.contains('$key?offset=0')) {
          jobs[e.sha256!] = EpisodeDownload(drama.title, e)
            ..state = DownloadState.paused;
        } else if (old != null) {
          jobs.remove(e.sha256);
        }
      }
    }
    notifyListeners();
  }

  void add(String title, Episode e) {
    if (e.sha256 == null || e.bytes == null) return;
    final job = jobs.putIfAbsent(e.sha256!, () => EpisodeDownload(title, e));
    if (job.busy ||
        job.state == DownloadState.saved ||
        _waiting.contains(job)) {
      return;
    }
    job.state = paused ? DownloadState.paused : DownloadState.queued;
    job.error = '';
    _waiting.add(job);
    _pump();
    notifyListeners();
  }

  void setPaused(bool value) {
    paused = value;
    for (final job in jobs.values) {
      final shouldChange = value
          ? job.state == DownloadState.queued ||
                job.state == DownloadState.fetching
          : job.state == DownloadState.paused;
      if (!shouldChange) {
        continue;
      }
      job.state = value ? DownloadState.paused : DownloadState.queued;
      if (value) job.request?.abort();
      if (!_waiting.contains(job)) _waiting.add(job);
    }
    _pump();
    notifyListeners();
  }

  void _pump() {
    while (!paused &&
        _running < 2 &&
        _waiting.isNotEmpty &&
        !_waiting.first.busy) {
      final job = _waiting.removeAt(0);
      job.busy = true;
      job.state = DownloadState.fetching;
      _running++;
      unawaited(_run(job));
    }
  }

  Future<void> _clearParts(web.Cache cache, Episode e) async {
    final key = _key(e);
    for (var pos = 0; pos < e.bytes!; pos += chunkSize) {
      await cache.delete('$key?offset=$pos'.toJS).toDart;
    }
  }

  Future<void> remove(EpisodeDownload job) async {
    if (job.busy) return;
    job.busy = true;
    _waiting.remove(job);
    try {
      final cache = await _cache;
      await cache.delete(_key(job.episode).toJS).toDart;
      await _clearParts(cache, job.episode);
      jobs.remove(job.episode.sha256);
    } finally {
      job.busy = false;
      _waiting.remove(job);
      _pump();
      notifyListeners();
    }
  }

  Future<void> _prepareOfflineApp() async {
    final filename = web.document
        .querySelector('meta[name="sableen-offline-worker"]')
        ?.getAttribute('content');
    if (filename == null) return;
    final script = Uri.parse(web.document.baseURI).resolve(filename);
    final registration = await web.window.navigator.serviceWorker
        .register(script.toString().toJS)
        .toDart;
    if (registration.active?.scriptURL == script.toString()) return;
    final worker = registration.installing ?? registration.waiting;
    if (worker == null) throw StateError('Offline installation unavailable');
    final ready = Completer<void>();
    void changed(web.Event? _) {
      if (ready.isCompleted) return;
      if (worker.state == 'activated') ready.complete();
      if (worker.state == 'redundant') {
        ready.completeError(StateError('Offline installation failed'));
      }
    }

    final listener = changed.toJS;
    worker.addEventListener('statechange', listener);
    try {
      changed(null);
      await ready.future.timeout(const Duration(minutes: 3));
    } finally {
      worker.removeEventListener('statechange', listener);
    }
  }

  Future<void> _run(EpisodeDownload job) async {
    final e = job.episode, size = e.bytes!, key = _key(e);
    try {
      await _prepareOfflineApp();
      final cache = await _cache;
      final parts = <web.Blob>[];
      job.received = 0;
      for (var pos = 0; pos < size; pos += chunkSize) {
        if (job.state != DownloadState.fetching) return;
        final end = math.min(pos + chunkSize, size);
        final partKey = '$key?offset=$pos'.toJS;
        final stored = await cache.match(partKey).toDart;
        var part = await stored?.blob().toDart;
        if (part == null || part.size != end - pos) {
          part = await _fetchPart(job, key, pos, end);
          if (part.size == size) {
            parts
              ..clear()
              ..add(part);
            job.received = size;
            break;
          }
          await cache.put(partKey, web.Response(part)).toDart;
        }
        parts.add(part);
        job.received = end;
        notifyListeners();
      }
      if (job.state != DownloadState.fetching) return;
      job.state = DownloadState.verifying;
      notifyListeners();
      final data = web.Blob(parts.toJS, web.BlobPropertyBag(type: 'video/mp4'));
      if (!await _valid(data, e)) {
        await _clearParts(cache, e);
        throw const FormatException('SHA-256');
      }
      await cache.put(key.toJS, web.Response(data)).toDart;
      job.state = DownloadState.saved;
      await _clearParts(cache, e);
    } catch (error) {
      if (job.state == DownloadState.fetching ||
          job.state == DownloadState.verifying) {
        job.state = DownloadState.failed;
        job.error = '$error';
      }
    } finally {
      job.request = null;
      job.busy = false;
      _running--;
      _pump();
      notifyListeners();
    }
  }

  Future<web.Blob> _fetchPart(
    EpisodeDownload job,
    String key,
    int pos,
    int end,
  ) async {
    final e = job.episode;
    final sources = e.url.startsWith('asset:///assets/renditions/')
        ? [
            Uri.parse(web.document.baseURI)
                .resolve('assets/assets/renditions/${e.sha256}.mp4')
                .toString(),
          ]
        : [key, e.url, ...?e.mirrors];
    for (final url in sources) {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (job.state != DownloadState.fetching) throw StateError('Paused');
        final controller = job.request = web.AbortController();
        final timeout = Timer(
          const Duration(seconds: 45),
          () => controller.abort(),
        );
        try {
          final headers = web.Headers();
          if (end - pos != e.bytes) {
            headers.set('Range', 'bytes=$pos-${end - 1}');
          }
          final res = await web.window
              .fetch(
                url.toJS,
                web.RequestInit(
                  headers: headers,
                  signal: controller.signal,
                  credentials: 'omit',
                ),
              )
              .toDart;
          if (res.status == 404 && url != sources.last) break;
          if (res.status != 200 &&
              (res.status != 206 ||
                  res.headers.get('Content-Range') !=
                      'bytes $pos-${end - 1}/${e.bytes}')) {
            throw StateError('HTTP ${res.status}');
          }
          final blob = await res.blob().toDart;
          if (blob.size != (res.status == 206 ? end - pos : e.bytes)) {
            throw const FormatException('Content length');
          }
          return blob;
        } catch (_) {
          if (attempt == 2 && url == sources.last) rethrow;
          if (job.state != DownloadState.fetching) rethrow;
          if (attempt < 2) {
            await Future<void>.delayed(Duration(milliseconds: 300 << attempt));
          }
        } finally {
          timeout.cancel();
          controller.abort();
          job.request = null;
        }
      }
    }
    throw StateError('Media unavailable');
  }
}

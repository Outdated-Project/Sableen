import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' show Media;
import 'package:native_proxy_resolver/native_proxy_resolver.dart';
import 'package:path_provider/path_provider.dart';

import 'src/rust/api/library.dart';
import 'download_status.dart';
import 'episode_media.dart';
export 'download_status.dart';

String mediaUrl(Episode episode) => episode.url;

class EpisodeDownload {
  EpisodeDownload(this.title, this.episode);
  final String title;
  final Episode episode;
  DownloadState state = DownloadState.queued;
  int received = 0;
  HttpClient? client;
  Directory? parts;
  bool single = false;
  int generation = 0;
  bool busy = false;
  bool removing = false;
  String error = '';
}

class _RangeIgnored implements Exception {}

class _BadResponse implements Exception {
  _BadResponse(this.status);
  final int status;
  @override
  String toString() => 'HTTP $status';
}

class DownloadQueue extends ChangeNotifier {
  DownloadQueue({
    this.directory = getApplicationSupportDirectory,
    this.route = _systemRoute,
  });
  final Future<Directory> Function() directory;
  final Future<String> Function(Uri) route;
  final jobs = <String, EpisodeDownload>{};
  final _waiting = <EpisodeDownload>[];
  final _verified = <String, (DateTime, DateTime, Future<bool>)>{};
  int _fetching = 0;
  bool paused = false;
  Future<void> _verification = Future.value();
  Timer? _update;

  static Future<String> _systemRoute(Uri url) async {
    final result = await SystemProxy.resolveDetailed(url);
    // A failed WPAD lookup can still return a manual proxy or a direct route.
    if (result.error != null &&
        result.entries.every((e) => e.isDirect) &&
        (result.source == ProxySource.unknown ||
            result.source == ProxySource.pac ||
            result.pacUrl != null && result.source != ProxySource.manual)) {
      throw HttpException('System proxy unavailable (${result.source.name})');
    }
    if (!result.entries.any((e) => e.isSupportedByDartIo)) {
      throw const HttpException('Unsupported system proxy');
    }
    return result.toFindProxyString();
  }

  Future<File> _target(Episode episode) async {
    final hash = episode.sha256!;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('SHA-256');
    }
    final root = await directory();
    return File('${root.path}/episodes/$hash.mp4');
  }

  Future<String?> localPath(Episode episode) async {
    if (episode.bytes == null || episode.sha256 == null) return null;
    final file = await _target(episode);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size != episode.bytes) {
      _verified.remove(file.path);
      return null;
    }
    var record = _verified[file.path];
    if (record == null ||
        record.$1 != stat.modified ||
        record.$2 != stat.changed) {
      final check = compute(_matchesHash, (file, episode.sha256!));
      record = (stat.modified, stat.changed, check);
      _verified[file.path] = record;
    }
    try {
      return await record.$3 ? file.path : null;
    } catch (_) {
      if (_verified[file.path] == record) _verified.remove(file.path);
      rethrow;
    }
  }

  void releasePath(String? path) {}

  static Future<bool> _matchesHash((File, String) input) async =>
      (await sha256.bind(input.$1.openRead()).first).toString() == input.$2;

  Future<void> restore(List<Drama> catalog) async {
    final root = Directory('${(await directory()).path}/episodes');
    final byHash = {
      for (final drama in catalog)
        for (final e in drama.episodes.expand((episode) => episode.files))
          if (e.sha256 != null) e.sha256!: (drama.title, e),
    };
    final found = <String>{};
    final files = await root.exists()
        ? root.list(followLinks: false)
        : const Stream<FileSystemEntity>.empty();
    await for (final file in files) {
      final name = file.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final item = byHash[name.split('.').first];
      if (item == null) continue;
      final (title, episode) = item;
      final hash = episode.sha256!;
      if (file is Directory && name == '$hash.parts') {
        jobs.putIfAbsent(
          hash,
          () => EpisodeDownload(title, episode)
            ..state = DownloadState.paused
            ..parts = file,
        );
      } else if (file is File &&
          name == '$hash.mp4' &&
          await localPath(episode) != null) {
        found.add(hash);
        final job = jobs.putIfAbsent(
          hash,
          () => EpisodeDownload(title, episode),
        );
        if (!job.busy) {
          job.state = DownloadState.saved;
          job.received = episode.bytes!;
          _waiting.remove(job);
        }
      }
    }
    // Recheck any earlier entries if the OS or the user removed a saved file.
    for (final job in jobs.values.toList()) {
      final hash = job.episode.sha256!;
      if (job.state == DownloadState.saved &&
          !found.contains(hash) &&
          await localPath(job.episode) == null) {
        if (!job.busy) jobs.remove(hash);
      }
    }
    notifyListeners();
  }

  Future<void> remove(EpisodeDownload job) async {
    if (job.busy ||
        ![
          DownloadState.failed,
          DownloadState.saved,
          DownloadState.paused,
        ].contains(job.state)) {
      return;
    }
    _waiting.remove(job);
    job.busy = true;
    job.removing = true;
    try {
      final file = await _target(job.episode);
      final lock = await _lock(file);
      try {
        if (job.state == DownloadState.saved && await file.exists()) {
          await file.delete();
        }
        if (job.parts != null && await job.parts!.exists()) {
          await job.parts!.delete(recursive: true);
        }
        jobs.remove(job.episode.sha256);
      } finally {
        await lock.close();
      }
    } finally {
      job.busy = false;
      job.removing = false;
      _pump();
      notifyListeners();
    }
  }

  void add(String title, Episode episode) {
    final hash = episode.sha256;
    if (hash == null || episode.bytes == null) return;
    final job = jobs.putIfAbsent(hash, () => EpisodeDownload(title, episode));
    if (job.busy ||
        _waiting.contains(job) ||
        job.state == DownloadState.saved) {
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
      if (job.removing) continue;
      if (value &&
          job.state != DownloadState.saved &&
          job.state != DownloadState.failed) {
        job.generation++;
        job.client?.close(force: true);
        job.state = DownloadState.paused;
        if (!_waiting.contains(job)) _waiting.add(job);
      } else if (!value && job.state == DownloadState.paused) {
        job.state = DownloadState.queued;
        if (!_waiting.contains(job)) _waiting.add(job);
      }
    }
    _pump();
    notifyListeners();
  }

  void _pump() {
    while (!paused && _fetching < 2 && _waiting.isNotEmpty) {
      final job = _waiting.first;
      if (job.busy) return;
      _waiting.removeAt(0);
      job.busy = true;
      job.state = DownloadState.fetching;
      _fetching++;
      unawaited(_run(job, job.generation));
    }
  }

  void _changed() {
    _update ??= Timer(const Duration(milliseconds: 250), () {
      _update = null;
      notifyListeners();
    });
  }

  void _active(EpisodeDownload job, int generation) {
    if (job.generation != generation) throw const HttpException('Paused');
  }

  Future<RandomAccessFile> _lock(File target) async {
    await target.parent.create(recursive: true);
    final handle = await File('${target.path}.lock')
        .open(mode: FileMode.append);
    try {
      return await handle.lock(FileLock.exclusive);
    } catch (_) {
      await handle.close();
      rethrow;
    }
  }

  Future<void> _run(EpisodeDownload job, int generation) async {
    var transferSlot = true;
    RandomAccessFile? lock;
    final episode = job.episode;
    try {
      final target = await _target(episode);
      lock = await _lock(target);
      _active(job, generation);
      if (await localPath(episode) == null) {
        job.parts = await Directory(
          '${target.parent.path}/${episode.sha256}.parts',
        ).create();
        job.single = await File('${job.parts!.path}/0-${episode.bytes}.part')
            .exists();
        final files = await _transfer(job, generation);
        _active(job, generation);
        transferSlot = false;
        _fetching--;
        job.state = DownloadState.verifying;
        _changed();
        final previous = _verification;
        final release = Completer<void>();
        _verification = release.future;
        _pump();
        try {
          await previous;
          _active(job, generation);
          final work = job.parts!;
          final hash = episode.sha256!;
          final checked = await compute(_assemble, (work, files, hash));
          _active(job, generation);
          await checked.rename(target.path);
        } finally {
          release.complete();
        }
      }
      job.state = DownloadState.saved;
      _waiting.remove(job);
      job.received = episode.bytes!;
    } catch (e) {
      if (e is FormatException && lock != null && job.parts != null) {
        await _cleanup(job.parts!);
        job.parts = null;
      }
      if (job.generation == generation) {
        job.state = DownloadState.failed;
        job.error = e is FileSystemException
            ? e.osError?.message ?? e.message
            : '$e';
      }
    } finally {
      job.client?.close(force: true);
      job.client = null;
      if (transferSlot) _fetching--;
      if (lock != null && job.state == DownloadState.saved) {
        final work = job.parts;
        job.parts = null;
        if (work != null) await _cleanup(work);
      }
      await lock?.close();
      job.busy = false;
      _pump();
      _changed();
    }
  }

  Future<List<File>> _transfer(EpisodeDownload job, int generation) async {
    if (job.episode.url.startsWith('asset:///assets/renditions/')) {
      final asset = File(Media.normalizeURI(job.episode.url));
      if (await asset.length() != job.episode.bytes) {
        throw const FormatException('Asset size');
      }
      return [await asset.copy('${job.parts!.path}/rendition.mp4')];
    }
    final urls = [job.episode.url, ...?job.episode.mirrors];
    for (var i = 0; i < urls.length; i++) {
      _active(job, generation);
      final url = Uri.parse(urls[i]);
      final proxy = await route(url).timeout(const Duration(seconds: 12));
      _active(job, generation);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..autoUncompress = false
        ..findProxy = (_) => proxy;
      job.client = client;
      try {
        try {
          return await _fetch(job, generation, client, url);
        } on _RangeIgnored {
          _active(job, generation);
          job.single = true;
          return await _fetch(job, generation, client, url);
        }
      } catch (e) {
        if (i + 1 == urls.length ||
            !(_transient(e) ||
                e is _BadResponse && [404, 410].contains(e.status))) {
          rethrow;
        }
      } finally {
        client.close(force: true);
        job.client = null;
      }
    }
    throw StateError('Missing episode URL');
  }

  static bool _transient(Object error) =>
      error is HttpException ||
      error is SocketException ||
      error is TimeoutException ||
      error is _BadResponse && [500, 502, 503, 504].contains(error.status);

  Future<List<File>> _fetch(
    EpisodeDownload job,
    int generation,
    HttpClient client,
    Uri url,
  ) async {
    final size = job.episode.bytes!;
    final split = !job.single && size >= 1024 * 1024;
    final ranges = split ? [(0, size ~/ 2), (size ~/ 2, size)] : [(0, size)];
    job.received = 0;
    return Future.wait([
      for (final (start, end) in ranges)
        _part(job, generation, client, url, start, end, split),
    ], eagerError: false);
  }

  Future<File> _part(
    EpisodeDownload job,
    int generation,
    HttpClient client,
    Uri url,
    int start,
    int end,
    bool split,
  ) async {
    final file = File('${job.parts!.path}/$start-$end.part');
    var count = await file.exists() ? await file.length() : 0;
    final length = end - start;
    if (count > length) throw const FormatException('Invalid partial length');
    job.received += count;
    const timeout = Duration(seconds: 15);
    for (var attempt = 0; count < length; attempt++) {
      _active(job, generation);
      HttpClientRequest? request;
      HttpClientResponse? unread;
      try {
        request = await client.getUrl(url).timeout(timeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final range = split || count > 0;
        if (range) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=${start + count}-${end - 1}',
          );
        }
        final response = unread = await request.close().timeout(timeout);
        if (response.statusCode == 200 && split) throw _RangeIgnored();
        if (response.statusCode == 200 && count > 0) {
          job.received -= count;
          count = 0;
        } else if (response.statusCode == 206 && range) {
          final expected =
              'bytes ${start + count}-${end - 1}/${job.episode.bytes}';
          if (response.headers.value(HttpHeaders.contentRangeHeader) !=
              expected) {
            throw const FormatException('Content-Range');
          }
        } else if (response.statusCode != 200) {
          throw _BadResponse(response.statusCode);
        }
        if (response.contentLength >= 0 &&
            response.contentLength != length - count) {
          throw const HttpException('Incomplete response');
        }
        final output = await file.open(
          mode: count == 0 ? FileMode.write : FileMode.append,
        );
        try {
          unread = null;
          await for (final chunk in response.timeout(timeout)) {
            _active(job, generation);
            if (count + chunk.length > length) {
              throw const FormatException('Excess media data');
            }
            await output.writeFrom(chunk);
            count += chunk.length;
            job.received += chunk.length;
            _changed();
          }
        } finally {
          await output.close();
        }
        if (count < length) throw const HttpException('Incomplete response');
      } catch (e) {
        _active(job, generation);
        if (!_transient(e) || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 300 << attempt));
      } finally {
        request?.abort();
        if (unread != null) await unread.listen(null).cancel();
      }
    }
    return file;
  }

  static Future<File> _assemble((Directory, List<File>, String) input) async {
    final (work, files, hash) = input;
    final output = files.length == 1
        ? files.single
        : File('${work.path}/verified.mp4');
    Stream<List<int>> assemble() async* {
      final sink = await output.open(mode: FileMode.write);
      try {
        for (final part in files) {
          await for (final chunk in part.openRead()) {
            await sink.writeFrom(chunk);
            yield chunk;
          }
        }
      } finally {
        await sink.close();
      }
    }

    final stream = files.length == 1 ? output.openRead() : assemble();
    if ((await sha256.bind(stream).first).toString() != hash) {
      throw const FormatException('SHA-256');
    }
    return output;
  }

  static Future<void> _cleanup(Directory work) async {
    try {
      await work.delete(recursive: true);
    } on FileSystemException {
      // A locked scratch directory cannot hold a transfer or verification slot.
    }
  }
}

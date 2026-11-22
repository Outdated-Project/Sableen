import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sableen/download_queue.dart';
import 'package:sableen/src/rust/api/library.dart';

Future<void> until(bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed.inSeconds > 15) fail('Download did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
}

void main() {
  test('Range transfers recover from empty data and rapid pause/resume, then restore offline', () async {
    final root = await Directory.systemTemp.createTemp(
      'sableen-download-test-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    final data = Uint8List.fromList(List.generate(1200000, (i) => i % 251));
    final hash = sha256.convert(data).toString();
    final episode = Episode(
      id: 'a',
      title: 'A',
      url: 'http://127.0.0.1:${server.port}/episode',
      bytes: data.length,
      sha256: hash,
    );
    final queue = DownloadQueue(
      directory: () async => root,
      route: (_) async => 'DIRECT',
    );
    var empty = true;
    final ranges = <String>[];
    server.listen((request) async {
      final res = request.response;
      final range = request.headers.value('range')!;
      ranges.add(range);
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
      final start = int.parse(match[1]!), end = int.parse(match[2]!);
      res.statusCode = 206;
      res.headers.set('Content-Range', 'bytes $start-$end/${data.length}');
      if (empty) {
        empty = false;
      } else {
        res.contentLength = end - start + 1;
        try {
          for (var i = start; i <= end; i += 32768) {
            res.add(
              Uint8List.sublistView(data, i, (i + 32768).clamp(0, end + 1)),
            );
            await res.flush();
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
        } on IOException {
          /* Client paused. */
        }
      }
      try {
        await res.close();
      } on IOException {
        /* Client paused. */
      }
    });
    queue.add('title', episode);
    queue.add('title', episode);
    final job = queue.jobs[hash]!;
    await until(() => job.received > 0);
    for (var i = 0; i < 5; i++) {
      queue.setPaused(true);
      queue.setPaused(false);
    }
    await until(() => !job.busy && job.state != DownloadState.queued);
    expect(job.error, isEmpty);
    expect(job.state, DownloadState.saved);
    expect(job.received, data.length);
    expect(ranges.length, greaterThan(2));
    final saved = File((await queue.localPath(episode))!);
    expect(await sha256.bind(saved.openRead()).first, sha256.convert(data));
    final restarted = DownloadQueue(directory: () async => root);
    await restarted.restore([
      Drama(id: 'series', title: 'title', tags: [], episodes: [episode]),
    ]);
    expect(restarted.jobs[hash]!.state, DownloadState.saved);
    await restarted.remove(restarted.jobs[hash]!);
    expect(await queue.localPath(episode), isNull);
  });

  test(
    'A rejected digest releases the verification slot for the next file',
    () async {
      final root = await Directory.systemTemp.createTemp('sableen-hash-test-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        await root.delete(recursive: true);
      });
      final data = [1, 2, 3];
      server.listen((req) {
        req.response.add(data);
        unawaited(req.response.close());
      });
      final queue = DownloadQueue(
        directory: () async => root,
        route: (_) async => 'DIRECT',
      );
      for (final bytes in [
        [4, 5, 6],
        data,
      ]) {
        final hash = sha256.convert(bytes).toString();
        queue.add(
          hash,
          Episode(
            id: hash,
            title: hash,
            bytes: 3,
            sha256: hash,
            url: 'http://127.0.0.1:${server.port}/$hash',
          ),
        );
      }
      await until(() => queue.jobs.values.every((j) => !j.busy));
      expect(queue.jobs.values.map((j) => j.state), [
        DownloadState.failed,
        DownloadState.saved,
      ]);
      expect(await queue.localPath(queue.jobs.values.first.episode), isNull);
    },
  );

  test('Uses the published mirror after a missing file and handles whole-file HTTP 200', () async {
    final root = await Directory.systemTemp.createTemp('sableen-mirror-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    final data = Uint8List(1100000);
    final hash = sha256.convert(data).toString();
    var whole = 0;
    server.listen((req) async {
      if (req.uri.path == '/gone') {
        req.response.statusCode = 404;
      } else {
        if (req.headers.value('range') == null) whole++;
        req.response.add(data);
      }
      try {
        await req.response.close();
      } on IOException {
        /* Discarded range response. */
      }
    });
    final base = 'http://127.0.0.1:${server.port}';
    final episode = Episode(
      id: 'mirror',
      title: 'Mirror',
      bytes: data.length,
      sha256: hash,
      url: '$base/gone',
      mirrors: ['$base/copy'],
    );
    final queue = DownloadQueue(
      directory: () async => root,
      route: (_) async => 'DIRECT',
    );
    queue.add('title', episode);
    await until(() => !queue.jobs[hash]!.busy);
    expect(queue.jobs[hash]!.error, isEmpty);
    expect(whole, 1);
    final file = File((await queue.localPath(episode))!);
    data[0] = 1;
    await file.writeAsBytes(data, flush: true);
    expect(await queue.localPath(episode), isNull);
  });
}

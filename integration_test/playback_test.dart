import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sableen/design.dart';
import 'package:sableen/home.dart';
import 'package:sableen/library.dart';
import 'package:sableen/offline.dart';
import 'package:sableen/playback.dart';
import 'package:sableen/preferences.dart';
import 'package:sableen/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPreferences extends SharedPreferencesAsync {
  final keys = <String>{};
  final prefix = 'playback-test.${DateTime.now().microsecondsSinceEpoch}.';
  @override
  Future<String?> getString(String key) => super.getString('$prefix$key');
  @override
  Future<void> setString(String key, String value) {
    keys.add('$prefix$key');
    return super.setString('$prefix$key', value);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.isWindows) {
      // Let Windows create its native accessibility tree before Flutter sends
      // the home screen. A Dart-only override can leave the engine without a root.
      final policy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      try {
        runApp(const SizedBox.shrink());
        await binding.waitUntilFirstFrameRasterized.timeout(
          const Duration(seconds: 10),
        );
        final request = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '''
          Add-Type -AssemblyName UIAutomationClient
          \$window = [System.Windows.Automation.AutomationElement]::FromHandle((Get-Process -Id $pid).MainWindowHandle)
          \$null = \$window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        ''',
        ]);
        expect(request.exitCode, 0, reason: request.stderr.toString());
        final deadline = Stopwatch()..start();
        while (!binding.platformDispatcher.semanticsEnabled &&
            deadline.elapsed < const Duration(seconds: 5)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(
          binding.platformDispatcher.semanticsEnabled,
          isTrue,
          reason: 'Windows did not request accessibility',
        );
      } finally {
        binding.framePolicy = policy;
      }
    } else {
      binding.platformDispatcher.semanticsEnabledTestValue = true;
    }
    await RustLib.init();
    await initializePlayback();
  });
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  testWidgets('Hongguo video, center tap, visibility, seek and resume', (
    tester,
  ) async {
    final disk = _TestPreferences();
    addTearDown(() => disk.clear(allowList: disk.keys));
    final library = Library(disk);
    await library.restore();
    final center = find.byKey(const ValueKey('center-playback'));
    Player player() =>
        tester.widget<Video>(find.byType(Video)).controller.player;
    Future<void> until(String description, bool Function() predicate) async {
      final time = Stopwatch()..start();
      while (!predicate()) {
        if (time.elapsed > const Duration(seconds: 45)) {
          fail(
            '$description: ${player().state.position}, ${player().state.duration}, playing ${player().state.playing}, buffering ${player().state.buffering}, lifecycle ${WidgetsBinding.instance.lifecycleState}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(Library source, String id) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: hans,
          supportedLocales: const [hans, hant],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: theaterTheme(Brightness.light, null, Palette.monet),
          home: Home(library: source, preferences: Preferences(disk)),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.widgetWithText(
        ChoiceChip,
        source.publishers[id] == Publisher.comic ? '红果漫剧' : '红果短剧',
      );
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final title = find.text(source.byId[id]!.title);
      final card = find
          .ancestor(of: title, matching: find.byType(InkWell))
          .first;
      await Scrollable.ensureVisible(tester.element(card), alignment: .35);
      await tester.pumpAndSettle();
      await tester.tap(card);
      final deadline = Stopwatch()..start();
      while (find.byType(Video).evaluate().isEmpty &&
          deadline.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        find.byType(Video),
        findsOneWidget,
        reason: 'Card did not open ${source.byId[id]!.title}',
      );
    }

    Future<void> close() async {
      Navigator.of(tester.element(find.byType(Theater))).pop();
      await tester.pumpAndSettle();
    }

    for (final category in Publisher.values) {
      final id = library.publishers.entries
          .firstWhere((e) => e.value == category)
          .key;
      await open(library, id);
      await until(
        'Missing decoded video',
        () =>
            player().state.position.inMilliseconds >= 1200 &&
            (player().state.width ?? 0) > 0,
      );
      await until(
        'Fullscreen controls did not hide',
        () => find.byType(Slider).evaluate().isEmpty,
      );
      await tester.tap(center);
      await until('Center tap failed to pause', () => !player().state.playing);
      await tester.tap(center);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await until(
        'Unfocused video stalled',
        () =>
            player().state.playing &&
            player().state.position.inMilliseconds >= 3900,
      );
      final paused = player().stream.playing.firstWhere((playing) => !playing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      // Hidden views do not schedule Flutter frames. Observe the native player
      // directly so that this check also works when no frame can be pumped.
      try {
        await paused.timeout(const Duration(seconds: 10));
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pump();
      await until(
        'Pause did not expose download controls',
        () =>
            !player().state.playing &&
            find.byTooltip('离线下载').hitTestable().evaluate().isNotEmpty,
      );
      final episode = library.byId[id]!.episodes.first;
      final ids = library.byId[id]!.publishedIds!;
      await tester.tap(find.byTooltip('选集'));
      await tester.pumpAndSettle();
      final list = find
          .ancestor(
            of: find.text(episode.title).last,
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = library.byId[id]!.episodes
          .where((e) => e.id == ids.last)
          .firstOrNull;
      final lastTile = find.widgetWithText(
        ListTile,
        last?.title ?? '第${ids.length}集',
      );
      expect(tester.widget<ListTile>(lastTile).enabled, last != null);
      Navigator.of(tester.element(lastTile)).pop();
      await tester.pumpAndSettle();
      final hadCopy = await offlinePath(episode) != null;
      final selectedFile = episode.encodings
          ?.where((file) => file.sha256 == episode.sha256)
          .firstOrNull;
      final downloadTitle = [
        library.byId[id]!.title,
        episode.title,
        if (selectedFile != null)
          '${selectedFile.width}×${selectedFile.height}',
      ].join(' · ');
      if (!hadCopy) {
        addTearDown(() async {
          final path = await offlinePath(episode);
          if (path != null) await File(path).delete();
        });
      }
      await tester.tap(find.byTooltip('离线下载').hitTestable().last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载 ${episode.title}'));
      await until('Verified download failed', () {
        final errors = find.textContaining('下载失败');
        if (errors.evaluate().isNotEmpty) {
          fail(tester.widget<Text>(errors.first).data!);
        }
        return find.text('已保存').evaluate().isNotEmpty &&
            find
                .widgetWithText(ListTile, downloadTitle)
                .evaluate()
                .any(
                  (e) =>
                      ((e.widget as ListTile).subtitle as Text?)?.data == '已保存',
                );
      });
      Navigator.of(tester.element(find.text('下载 ${episode.title}'))).pop();
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      // Leave time to measure playback after restoring even a short preview.
      final target = (slider.max * .65).round();
      slider.onChangeEnd!(target.toDouble());
      await until(
        'Seek failed',
        () => (player().state.position.inMilliseconds - target).abs() < 600,
      );
      // Resume long enough to persist real post-seek evidence.
      await tester.tap(center);
      await until(
        'Post-seek playback stalled',
        () => player().state.position.inMilliseconds >= target + 500,
      );
      await close();
      await library.pendingWrites;
      final restored = Library(disk);
      await restored.restore();
      final progress = restored.latest(id)!;
      expect(progress.positionMs, greaterThanOrEqualTo(target));
      expect(progress.watchedMs, inExclusiveRange(0, target));
      await open(restored, id);
      await until(
        'Missing restored frame',
        () => player().state.position.inMilliseconds > 0,
      );
      final firstPosition = player().state.position.inMilliseconds;
      expect(
        player().state.playlist.medias.single.uri,
        endsWith('${episode.sha256}.mp4'),
      );
      expect(
        firstPosition,
        closeTo(progress.positionMs, 900),
        reason: 'First position after restoring ${progress.positionMs} ms',
      );
      final resumeStart = progress.positionMs;
      await until(
        'Resume failed',
        () => player().state.position.inMilliseconds >= resumeStart + 500,
      );
      await close();
      await restored.pendingWrites;
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

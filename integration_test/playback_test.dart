import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sableen/design.dart';
import 'package:sableen/home.dart';
import 'package:sableen/library.dart';
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
    // Keep the platform's accessibility request stable while native fullscreen
    // windows gain and lose focus. Exercise the accessible controls throughout.
    binding.platformDispatcher.semanticsEnabledTestValue = true;
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
      final filter = find.text(
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
      final slider = tester.widget<Slider>(find.byType(Slider));
      final target = (slider.max * .75).round();
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
        'Resume failed',
        () =>
            player().state.position.inMilliseconds >= progress.positionMs &&
            player().state.playing,
      );
      await close();
      await restored.pendingWrites;
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

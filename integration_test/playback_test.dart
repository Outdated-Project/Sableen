import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sableen/design.dart';
import 'package:sableen/library.dart';
import 'package:sableen/playback.dart';
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Hongguo video, center tap, visibility, seek and resume', (
    tester,
  ) async {
    await RustLib.init();
    await initializePlayback();
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

    Future<void> open(Library library, String id) => tester.pumpWidget(
      MaterialApp(
        locale: hans,
        supportedLocales: const [hans, hant],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theaterTheme(Brightness.light, null, Palette.monet),
        home: Theater(library: library, drama: library.byId[id]!, initial: 0),
      ),
    );
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
      await tester.tap(center);
      await until('Center tap failed to pause', () => !player().state.playing);
      await tester.tap(center);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await until(
        'Unfocused video stalled',
        () =>
            player().state.playing &&
            player().state.position.inMilliseconds >= 2300,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await until(
        'Background video still playing',
        () => !player().state.playing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final slider = tester.widget<Slider>(find.byType(Slider));
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
      await tester.pumpWidget(const SizedBox());
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
      await tester.pumpWidget(const SizedBox());
      await restored.pendingWrites;
    }
  });
}

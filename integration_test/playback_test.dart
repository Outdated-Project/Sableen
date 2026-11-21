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
  testWidgets('Playback advances and a new library restores the saved episode', (
    tester,
  ) async {
    await RustLib.init();
    await initializePlayback();
    const url = String.fromEnvironment(
      'TEST_MEDIA_URL',
      defaultValue: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    );
    final disk = _TestPreferences();
    addTearDown(() => disk.clear(allowList: disk.keys));
    final library = Library(disk);
    await library.restore();
    expect(library.source, publicCatalog);
    expect(library.publishers.values.toSet(), Publisher.values.toSet());
    final series = library.dramas.firstWhere(
      (d) =>
          library.publishers[d.id] == Publisher.guangzhou &&
          d.episodes.length >= 2,
    );
    await library.addVideo('播放测试', '自然', url);
    Future<void> open(Library source, {String? id}) => tester.pumpWidget(
      MaterialApp(
        locale: hans,
        supportedLocales: const [hans, hant],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theaterTheme(Brightness.light, null, Palette.monet),
        home: Theater(
          library: source,
          drama: id == null ? source.dramas.single : source.byId[id]!,
          initial: 0,
        ),
      ),
    );
    Future<void> waitForPosition(int minimum) async {
      final timeout = Stopwatch()..start();
      while (timeout.elapsed < const Duration(seconds: 35)) {
        await tester.pump(const Duration(milliseconds: 150));
        if (tester.widget<Slider>(find.byType(Slider)).value >= minimum) {
          return;
        }
      }
      final player = tester.widget<Video>(find.byType(Video)).controller.player;
      fail(
        'Playback did not reach $minimum ms. Position ${player.state.position}, '
        'duration ${player.state.duration}, playing ${player.state.playing}, '
        'buffering ${player.state.buffering}, lifecycle ${WidgetsBinding.instance.lifecycleState}',
      );
    }

    await open(library);
    await waitForPosition(1500);
    final platform = tester
        .widget<Video>(find.byType(Video))
        .controller
        .player
        .platform;
    if (platform is NativePlayer) {
      final decoder = await platform.getProperty('hwdec-current');
      final fps = await platform.getProperty('container-fps');
      debugPrint('Test playback decoder=$decoder, source FPS=$fps');
    }
    await tester.pumpWidget(const SizedBox());
    await library.pendingWrites;
    final restored = Library(disk);
    await restored.restore();
    final entry = restored.history.single;
    expect(entry.positionMs, greaterThanOrEqualTo(1500));
    expect(entry.watchedMs, greaterThan(0));
    expect(entry.completed, isFalse);
    expect(await restored.ranked(), isEmpty);
    await open(restored);
    await waitForPosition(entry.positionMs + 500);
    await tester.pumpWidget(const SizedBox());
    await restored.pendingWrites;
    await restored.usePublicCatalog();
    final clipId = restored.publishers.entries
        .firstWhere((e) => e.value == Publisher.hongguo)
        .key;
    await open(restored, id: clipId);
    await waitForPosition(1000);
    debugPrint('Hongguo public media advanced');
    await tester.pumpWidget(const SizedBox());
    await open(restored, id: series.id);
    await waitForPosition(1500);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, greaterThan(20000));
    slider.onChangeEnd!(15000);
    await waitForPosition(16000);
    await tester.tap(find.text(series.episodes[1].title));
    await tester.pump();
    final entryAfterSeek = restored.latest(
      series.id,
      series.episodes.first.id,
    )!;
    expect(entryAfterSeek.positionMs, greaterThanOrEqualTo(15000));
    expect(entryAfterSeek.watchedMs, lessThan(10000));
    await waitForPosition(1500);
    await tester.pumpWidget(const SizedBox());
    await restored.pendingWrites;
    final public = Library(disk);
    await public.restore();
    expect(public.source, publicCatalog);
    expect(public.latest(series.id)?.episode, series.episodes[1].id);
    expect(public.latest(clipId)?.watchedMs, greaterThan(0));
    final cctv = public.publishers.entries
        .firstWhere((e) => e.value == Publisher.cctv)
        .key;
    await open(public, id: cctv);
    await waitForPosition(1500);
    final episodeLength = tester.widget<Slider>(find.byType(Slider)).max;
    expect(episodeLength, greaterThan(500000));
    debugPrint('CCTV co-production played, duration $episodeLength ms');
    await tester.pumpWidget(const SizedBox());
    await public.pendingWrites;
  });
}

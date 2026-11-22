import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sableen/episode_media.dart';
import 'package:sableen/episode_picker.dart';
import 'package:sableen/src/rust/api/library.dart';

void main() {
  test(
    'A full episode is preferred to previews and replaces old preview progress',
    () {
      final show = Drama(
        id: 'show',
        title: 'Series',
        tags: const [],
        episodes: [
          for (final (id, time) in [('1', 10000), ('2', 171000), ('3', 171000)])
            Episode(
              id: id,
              title: id,
              url: 'https://example.org/$id.mp4',
              durationMs: time,
              listedMs: 171000,
            ),
        ],
      );
      Progress history(int duration) => Progress(
        drama: 'show',
        episode: '2',
        positionMs: duration,
        durationMs: duration,
        watchedMs: duration,
        updated: 0,
        completed: true,
      );
      expect(show.startingIndex(), 1);
      expect(show.startingIndex(selectedId: '1'), 0);
      expect(show.startingIndex(last: history(10000)), 1);
      expect(show.episodes[1].replacesShorterCut(history(10000)), isTrue);
      expect(show.startingIndex(last: history(171000)), 2);
      expect(show.startingIndex(selectedId: '2', last: history(171000)), 1);
    },
  );
  testWidgets('A sparse catalog opens the current published episode range', (
    tester,
  ) async {
    final ids = List.generate(785, (i) => 'id-${i + 1}');
    final drama = Drama(
      id: 'show',
      title: '剧集',
      tags: const [],
      episodeCount: 785,
      publishedIds: ids,
      episodes: [
        for (final number in [2, 785])
          Episode(
            id: ids[number - 1],
            title: '第$number集',
            url: 'https://example.org/$number.mp4',
          ),
      ],
    );
    expect(drama.nextEpisodeIndex(0), isNull);
    expect(drama.nextEpisodeIndex(1), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EpisodePicker(drama: drama, current: 1)),
      ),
    );
    expect(find.text('781–785'), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第785集')).selected,
      isTrue,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第784集')).enabled,
      isFalse,
    );
    await tester.tap(find.text('781–785'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '1–15'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '第2集')).enabled,
      isTrue,
    );
  });
  test('Offline playback uses the selected encoding’s verified bytes', () {
    final primary = VideoEncoding(
      width: 360,
      height: 640,
      url: 'https://example.org/360.mp4',
      sha256: 'a' * 64,
      bytes: 200,
    );
    final alternate = VideoEncoding(
      width: 1080,
      height: 1920,
      url: 'https://example.org/1080.mp4',
      sha256: 'b' * 64,
      bytes: 300,
    );
    final source = Episode(
      id: '2',
      title: '第2集',
      sha256: primary.sha256,
      bytes: primary.bytes,
      url: primary.url,
      encodings: [primary, alternate],
      mirrors: ['https://example.org/mirror.mp4'],
    );
    final hash = 'c' * 64;
    final playback = source.withPlaybackRenditions({
      alternate.sha256: {'sha256': hash, 'bytes': 450},
    });
    expect(playback.url, primary.url);
    expect(playback.mirrors, source.mirrors);
    final hd = playback.files.last;
    expect(
      (hd.id, hd.bytes, hd.sha256, hd.url, hd.mirrors),
      ('2', 450, hash, 'asset:///assets/renditions/$hash.mp4', null),
    );
    expect(hd.encodings!.last.height, 1920);
    final convertedDefault = source.withPlaybackRenditions({
      primary.sha256: {'sha256': hash, 'bytes': 450},
    });
    expect(convertedDefault.encodings!.first.url, convertedDefault.url);
    expect(convertedDefault.files.length, 2);
    expect(convertedDefault.mirrors, isNull);
  });
}

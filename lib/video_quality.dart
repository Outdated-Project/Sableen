import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'design.dart';
import 'player_sheet.dart';
import 'src/rust/api/library.dart';

class VideoQuality extends StatelessWidget {
  const VideoQuality({
    super.key,
    required this.player,
    required this.episode,
    required this.selectFile,
    required this.enabled,
    required this.rotated,
  });

  final Player player;
  final Episode episode;
  final ValueChanged<VideoEncoding> selectFile;
  final bool enabled;
  final bool rotated;

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    final files = episode.encodings ?? const <VideoEncoding>[];
    final width = state.width ?? 0, height = state.height ?? 0;
    final dimensions = width > 0 && height > 0 ? '$width×$height' : null;
    if (dimensions == null && files.isEmpty) return const SizedBox.shrink();
    final tracks = <(int, int), VideoTrack>{};
    if (!kIsWeb) {
      for (final track in state.tracks.video) {
        final w = track.w ?? 0, h = track.h ?? 0;
        if (track.image != true && track.albumart != true && w > 0 && h > 0) {
          tracks.putIfAbsent((w, h), () => track);
        }
      }
    }
    final label = context.zh('清晰度', '畫質');
    return TextButton.icon(
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Text(dimensions ?? label),
      onPressed: !enabled
          ? null
          : () async {
              final choices =
                  <
                    ({
                      String size,
                      bool selected,
                      VideoEncoding? file,
                      VideoTrack? track,
                    })
                  >[
                    for (final f in files)
                      (
                        size: '${f.width}×${f.height}',
                        selected: tracks.length > 1 && dimensions != null
                            ? (f.width, f.height) == (width, height)
                            : f.sha256 == episode.sha256,
                        file: f,
                        track: f.sha256 == episode.sha256
                            ? tracks[(f.width, f.height)]
                            : null,
                      ),
                    for (final entry in tracks.entries)
                      if (!files.any((f) => (f.width, f.height) == entry.key))
                        (
                          size: '${entry.key.$1}×${entry.key.$2}',
                          selected: entry.key == (width, height),
                          file: null,
                          track: entry.value,
                        ),
                  ];
              final result = await showPlayerSheet<int>(
                context: context,
                rotated: rotated,
                builder: (ctx) => ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text(label),
                      subtitle: Text(
                        choices.length < 2
                            ? ctx.zh(
                                '当前可用 ${dimensions ?? choices.first.size}',
                                '目前可用 ${dimensions ?? choices.first.size}',
                              )
                            : ctx.zh('选择播放分辨率', '選擇播放解析度'),
                      ),
                    ),
                    if (choices.length > 1)
                      for (final (i, choice) in choices.indexed)
                        ListTile(
                          title: Text(choice.size),
                          selected: choice.selected,
                          trailing: choice.selected
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(ctx, i),
                        ),
                  ],
                ),
              );
              if (result == null ||
                  !context.mounted ||
                  choices[result].selected) {
                return;
              }
              final choice = choices[result];
              if (choice.track case final track?) {
                if (!player.state.tracks.video.contains(track)) return;
                try {
                  await player.setVideoTrack(track);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.zh('分辨率切换失败', '解析度切換失敗'))),
                    );
                  }
                }
              } else if (choice.file case final file?) {
                selectFile(file);
              }
            },
    );
  }
}

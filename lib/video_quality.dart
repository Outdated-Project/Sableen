import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'design.dart';
import 'player_sheet.dart';

class VideoQuality extends StatelessWidget {
  const VideoQuality({
    super.key,
    required this.player,
    required this.enabled,
    required this.rotated,
  });

  final Player player;
  final bool enabled;
  final bool rotated;

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    final width = state.width ?? 0, height = state.height ?? 0;
    if (width <= 0 || height <= 0) return const SizedBox.shrink();
    final dimensions = Text(
      '$width×$height',
      style: Theme.of(context).textTheme.labelSmall,
    );
    if (kIsWeb) return dimensions;
    final tracks = state.tracks.video
        .where(
          (track) =>
              track.image != true &&
              track.albumart != true &&
              (track.w ?? 0) > 0 &&
              (track.h ?? 0) > 0,
        )
        .toList();
    if (tracks.map((track) => (track.w, track.h)).toSet().length < 2) {
      return dimensions;
    }
    return TextButton.icon(
      icon: const Icon(Icons.expand_more, size: 16),
      label: dimensions,
      onPressed: !enabled
          ? null
          : () async {
              final track = await showPlayerSheet<VideoTrack>(
                context: context,
                rotated: rotated,
                builder: (context) => ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(title: Text(context.zh('选择分辨率', '選擇解析度'))),
                    for (final item in tracks)
                      ListTile(
                        title: Text('${item.w}×${item.h}'),
                        selected: item == state.track.video,
                        onTap: () => Navigator.pop(context, item),
                      ),
                  ],
                ),
              );
              if (track == null ||
                  !context.mounted ||
                  !player.state.tracks.video.contains(track)) {
                return;
              }
              try {
                await player.setVideoTrack(track);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.zh('分辨率切换失败', '解析度切換失敗'))),
                  );
                }
              }
            },
    );
  }
}

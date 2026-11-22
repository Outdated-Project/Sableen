import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'episode_media.dart';
import 'download_web_queue.dart' if (dart.library.io) 'download_queue.dart';
import 'download_status.dart';
import 'player_sheet.dart';
import 'src/rust/api/library.dart';

final _downloads = DownloadQueue();

Widget downloadsPage(List<Drama> catalog, void Function(Drama, Episode) play) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: _DownloadSheet(catalog, null, null, play: play),
    );

Future<String?> offlinePath(Episode episode) async {
  try {
    return await _downloads.localPath(episode);
  } catch (_) {
    return null;
  }
}

void releaseOfflinePath(String? path) => _downloads.releasePath(path);

String playbackUrl(Episode episode) => mediaUrl(episode);

Widget downloadButton(
  List<Drama> catalog, {
  Drama? drama,
  Episode? episode,
  bool rotated = false,
}) => Builder(
  builder: (context) => IconButton.filledTonal(
    tooltip: context.zh('离线下载', '離線下載'),
    icon: const Icon(Icons.download_outlined),
    onPressed: () => showPlayerSheet<void>(
      context: context,
      rotated: rotated,
      builder: (_) => _DownloadSheet(catalog, drama, episode),
    ),
  ),
);

class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet(this.catalog, this.drama, this.episode, {this.play});
  final void Function(Drama, Episode)? play;
  final List<Drama> catalog;
  final Drama? drama;
  final Episode? episode;
  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  late final restored = _downloads.restore(widget.catalog);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _downloads,
    builder: (context, _) {
      final episode = widget.episode;
      final drama = widget.drama;
      final current = _downloads.jobs[episode?.sha256];
      final jobs = _downloads.jobs.values.toList();
      if (current != null && jobs.last != current) {
        jobs.remove(current);
        jobs.add(current);
      }
      final canResume =
          _downloads.paused || jobs.any((j) => j.state == DownloadState.paused);
      return Column(
        children: [
          ListTile(
            title: Text(context.zh('离线下载', '離線下載')),
            trailing:
                jobs.every(
                  (j) =>
                      j.state == DownloadState.saved ||
                      j.state == DownloadState.failed,
                )
                ? null
                : TextButton(
                    onPressed: () => _downloads.setPaused(!canResume),
                    child: Text(
                      canResume
                          ? context.zh('全部继续', '全部繼續')
                          : context.zh('全部暂停', '全部暫停'),
                    ),
                  ),
          ),
          if (drama != null && episode?.sha256 != null)
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _downloads.add(drama.title, episode),
                  icon: const Icon(Icons.download),
                  label: Text('${context.zh('下载', '下載')} ${episode!.title}'),
                ),
                if (drama.episodes.length > 1)
                  TextButton(
                    onPressed: () {
                      for (final e in drama.episodes) {
                        _downloads.add(drama.title, e);
                      }
                    },
                    child: Text(context.zh('下载全部', '下載全部')),
                  ),
              ],
            ),
          Expanded(
            child: FutureBuilder<void>(
              future: restored,
              builder: (context, snapshot) {
                if (snapshot.hasError && jobs.isEmpty) {
                  return Center(
                    child: Text(context.zh('无法读取下载目录', '無法讀取下載目錄')),
                  );
                }
                if (jobs.isEmpty) {
                  return Center(child: Text(context.zh('暂无下载', '暫無下載')));
                }
                return ListView.builder(
                  itemCount: jobs.length,
                  itemBuilder: (context, i) {
                    final job = jobs[jobs.length - 1 - i];
                    final label = switch (job.state) {
                      DownloadState.queued => context.zh('排队中', '排隊中'),
                      DownloadState.fetching =>
                        '${context.zh('下载中', '下載中')} ${(100 * job.received ~/ job.episode.bytes!).clamp(0, 99)}%',
                      DownloadState.verifying => context.zh('正在校验', '正在校驗'),
                      DownloadState.saved => context.zh('已保存', '已儲存'),
                      DownloadState.paused => context.zh('已暂停', '已暫停'),
                      DownloadState.failed =>
                        '${context.zh('下载失败', '下載失敗')} · ${job.error}',
                    };
                    return ListTile(
                      onTap:
                          job.state == DownloadState.saved &&
                              widget.play != null
                          ? () {
                              final drama = widget.catalog.firstWhere(
                                (d) => d.episodes
                                    .expand((episode) => episode.files)
                                    .any((e) => e.sha256 == job.episode.sha256),
                              );
                              widget.play!(drama, job.episode);
                            }
                          : null,
                      title: Text(
                        [
                          job.title,
                          job.episode.title,
                          if (job.episode.encodings
                                  ?.where((f) => f.sha256 == job.episode.sha256)
                                  .firstOrNull
                              case final file?)
                            '${file.width}×${file.height}',
                        ].join(' · '),
                      ),
                      subtitle: Text(label),
                      trailing: job.state == DownloadState.failed
                          ? IconButton(
                              tooltip: context.zh('重试', '重試'),
                              icon: const Icon(Icons.refresh),
                              onPressed: () =>
                                  _downloads.add(job.title, job.episode),
                            )
                          : [
                                  DownloadState.saved,
                                  DownloadState.paused,
                                ].contains(job.state) &&
                                !job.busy
                          ? IconButton(
                              tooltip: context.zh('移除下载', '移除下載'),
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await _downloads.remove(job);
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          context.zh(
                                            '文件正在使用或无法移除',
                                            '檔案正在使用或無法移除',
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

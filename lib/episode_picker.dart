import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'episode_media.dart';
import 'src/rust/api/library.dart';

class EpisodePicker extends StatefulWidget {
  const EpisodePicker({super.key, required this.drama, required this.current});

  final Drama drama;
  final int current;

  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  static const pageSize = 15;
  late final episodes = widget.drama.episodes;
  late final published =
      widget.drama.publishedIds ?? episodes.map((e) => e.id).toList();
  late final files = {for (final (i, e) in episodes.indexed) e.id: i};
  late int group =
      math.max(0, published.indexOf(episodes[widget.current].id)) ~/ pageSize;
  bool choosingGroup = false;

  String range(int i) =>
      '${i * pageSize + 1}–${math.min((i + 1) * pageSize, published.length)}';

  @override
  Widget build(BuildContext context) {
    final full = episodes.where((e) => e.isFullLength).length;
    final previews = episodes.where((e) => e.isPreview).length;
    final start = group * pageSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(
            widget.drama.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (widget.drama.episodeCount case final count?) '全 $count 集',
              '正片 $full 集',
              if (previews > 0) context.zh('片段 $previews 个', '片段 $previews 個'),
            ].join(' · '),
          ),
          trailing: published.length <= pageSize
              ? null
              : TextButton.icon(
                  onPressed: () =>
                      setState(() => choosingGroup = !choosingGroup),
                  iconAlignment: IconAlignment.end,
                  icon: Icon(
                    choosingGroup ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(range(group)),
                ),
        ),
        Flexible(
          child: choosingGroup
              ? GridView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisExtent: 48,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  shrinkWrap: true,
                  itemCount: (published.length + pageSize - 1) ~/ pageSize,
                  itemBuilder: (context, i) => OutlinedButton(
                    onPressed: () => setState(() {
                      group = i;
                      choosingGroup = false;
                    }),
                    child: Text(range(i)),
                  ),
                )
              : ListView.builder(
                  key: ValueKey(group),
                  shrinkWrap: true,
                  itemCount: math.min(pageSize, published.length - start),
                  itemBuilder: (context, row) {
                    final index = files[published[start + row]];
                    return ListTile(
                      enabled: index != null,
                      selected: index == widget.current,
                      leading: Icon(
                        index == null
                            ? Icons.list_alt_outlined
                            : index == widget.current
                            ? Icons.play_arrow_rounded
                            : Icons.play_circle_outline,
                      ),
                      title: Text(
                        index == null
                            ? '第${start + row + 1}集'
                            : episodes[index].title,
                      ),
                      trailing: index == null
                          ? Text(context.zh('本应用尚未收录', '本應用尚未收錄'))
                          : null,
                      onTap: index == null
                          ? null
                          : () => Navigator.pop(context, index),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

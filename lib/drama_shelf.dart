import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'episode_media.dart';
import 'library.dart';
import 'src/rust/api/library.dart';

class DramaShelf extends StatelessWidget {
  const DramaShelf({
    super.key,
    required this.library,
    required this.titles,
    required this.columns,
    required this.onOpen,
    required this.emptyText,
    this.history = false,
  });

  final Library library;
  final List<Drama> titles;
  final int columns;
  final void Function(Drama, ImageProvider, Episode?) onOpen;
  final String emptyText;
  final bool history;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 56),
          child: Center(child: Text(emptyText)),
        ),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final width =
            (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
        final horizontal = columns == 1 || width >= 340;
        final textScale = MediaQuery.textScalerOf(context);
        final extent = horizontal
            ? math.max(
                width >= 340 ? (width * .42).clamp(156.0, 222.0) : 138.0,
                36 + textScale.scale(18) * 3 + textScale.scale(13) * 2,
              )
            : width * 1.25 +
                  textScale.scale(16) * 3 +
                  textScale.scale(12) * 2 +
                  20;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: 18,
            mainAxisExtent: extent,
          ),
          itemCount: titles.length,
          itemBuilder: (context, index) {
            final drama = titles[index];
            final origin = library.publishers[drama.id]!;
            final last = library.latest(drama.id);
            final progress = history ? last : null;
            final ep =
                drama.episodes[drama.startingIndex(
                  last: last,
                  selectedId: progress?.episode,
                )];
            final category = origin == Publisher.comic
                ? context.zh('红果漫剧', '紅果漫劇')
                : context.zh('红果短剧', '紅果短劇');
            final colors = Theme.of(context).colorScheme;
            final posterWidth = horizontal
                ? math.min(width * .38, extent * .76)
                : width;
            final pixels =
                (posterWidth * MediaQuery.devicePixelRatioOf(context) / 32)
                    .ceil() *
                32;
            final image = ResizeImage(
              AssetImage(
                'assets/posters/${origin.name}-${drama.episodes.first.id}.webp',
              ),
              width: pixels.clamp(32, 560),
              policy: ResizeImagePolicy.fit,
            );
            final cover = ClipRRect(
              borderRadius: BorderRadius.circular(horizontal ? 0 : 12),
              child: Image(
                image: image,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.surfaceContainerHigh,
                  child: Icon(Icons.movie_outlined, color: colors.primary),
                ),
              ),
            );
            final poster = MediaQuery.disableAnimationsOf(context)
                ? cover
                : Hero(tag: drama.id, child: cover);
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: horizontal
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Text(
                  horizontal && drama.tags.isNotEmpty
                      ? '$category  ·  ${drama.tags.take(2).join(' / ')}'
                      : category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  drama.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (horizontal && width >= 340
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.titleMedium)
                          ?.copyWith(height: 1.24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  ep.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (progress != null && !ep.replacesShorterCut(progress))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      label:
                          '${context.zh('已观看', '已觀看')} ${100 * progress.positionMs ~/ math.max(1, progress.durationMs)}%',
                      excludeSemantics: true,
                      child: LinearProgressIndicator(
                        value:
                            progress.positionMs /
                            math.max(1, progress.durationMs),
                        minHeight: 2,
                      ),
                    ),
                  ),
              ],
            );
            return Card.filled(
              margin: EdgeInsets.zero,
              color: horizontal
                  ? colors.surfaceContainerLowest
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: horizontal
                    ? BorderSide(
                        color: colors.outlineVariant.withValues(alpha: .55),
                      )
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(drama, image, progress == null ? null : ep),
                child: horizontal
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: posterWidth, child: poster),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: details,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: width * 1.25, child: poster),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(2, 8, 2, 2),
                                child: details,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

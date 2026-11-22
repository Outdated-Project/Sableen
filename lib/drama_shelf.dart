import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'design.dart';
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
  final void Function(Drama, ImageProvider) onOpen;
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
                134.0,
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
            final progress = history ? library.latest(drama.id) : null;
            final ep =
                drama.episodes
                    .where((e) => e.id == progress?.episode)
                    .firstOrNull ??
                drama.episodes.first;
            final category = origin == Publisher.comic
                ? context.zh('漫剧', '漫劇')
                : context.zh('短剧', '短劇');
            final colors = Theme.of(context).colorScheme;
            final posterWidth = horizontal
                ? math.min(width * .34, extent * .72)
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
              borderRadius: BorderRadius.circular(16),
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
                  style: Theme.of(context).textTheme.titleMedium
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
                if (progress != null)
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
            return Material(
              color: horizontal
                  ? colors.surfaceContainerLow
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(drama, image),
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

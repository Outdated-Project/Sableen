import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'design.dart';

class TheaterNavigation extends StatelessWidget {
  const TheaterNavigation({
    super.key,
    required this.mode,
    required this.index,
    required this.select,
  });

  final Glass mode;
  final int index;
  final ValueChanged<int> select;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final opaque = mode == Glass.solid || MediaQuery.highContrastOf(context);
    final dark = colors.brightness == Brightness.dark;
    final aero = mode == Glass.aero;
    final liquid = mode == Glass.liquid;
    final tint = Color.alphaBlend(
      colors.primary.withValues(alpha: aero ? .14 : .025),
      colors.surface,
    );
    final fill = opaque
        ? colors.surfaceContainerHigh
        : tint.withValues(alpha: liquid ? (dark ? .70 : .65) : .72);
    final theme = NavigationBarThemeData(
      indicatorColor: colors.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.onPrimaryContainer
              : colors.onSurface,
        ),
      ),
    );
    final controls = DecoratedBox(
      decoration: BoxDecoration(
        color: (aero || liquid) && !opaque ? null : fill,
        gradient: (aero || liquid) && !opaque
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  if (aero)
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: dark ? .18 : .35),
                      tint,
                    ).withValues(alpha: .8)
                  else
                    fill,
                  fill,
                  tint.withValues(alpha: dark ? .82 : .74),
                ],
                stops: const [0, .48, .73],
              )
            : null,
      ),
      child: NavigationBarTheme(
        data: theme,
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          height: 66,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          animationDuration: motion(context),
          destinations: [
            for (final (title, icon, active) in [
              (
                context.zh('剧场', '劇場'),
                Icons.movie_outlined,
                Icons.movie_rounded,
              ),
              (
                context.zh('历史纪录', '歷史紀錄'),
                Icons.history_outlined,
                Icons.history_rounded,
              ),
              (
                context.zh('下载', '下載'),
                Icons.file_download_outlined,
                Icons.file_download_rounded,
              ),
              (
                context.zh('设置', '設定'),
                Icons.settings_outlined,
                Icons.settings_rounded,
              ),
            ])
              NavigationDestination(
                label: title,
                icon: Icon(icon),
                selectedIcon: Icon(active),
              ),
          ],
        ),
      ),
    );
    final blur = ImageFilterConfig.blur(
      sigmaX: liquid ? 10 : 12,
      sigmaY: liquid ? 10 : 12,
      bounded: true,
    );
    // Restore some chroma lost to the blur without changing neutral backgrounds.
    const saturation = ui.ColorFilter.matrix(<double>[
      1.16,
      -.14,
      -.02,
      0,
      0,
      -.04,
      1.06,
      -.02,
      0,
      0,
      -.04,
      -.14,
      1.18,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: CustomPaint(
          foregroundPainter: _GlassRim(
            opaque
                ? colors.outlineVariant
                : Colors.white.withValues(alpha: dark ? .56 : .9),
            opaque
                ? colors.outlineVariant
                : colors.shadow.withValues(alpha: dark ? .3 : .18),
          ),
          child: ClipPath(
            clipper: const ShapeBorderClipper(shape: StadiumBorder()),
            child: opaque
                ? controls
                : BackdropFilter(
                    filterConfig: liquid
                        ? ImageFilterConfig.compose(
                            inner: blur,
                            outer: const ImageFilterConfig(saturation),
                          )
                        : blur,
                    child: controls,
                  ),
          ),
        ),
      ),
    );
  }
}

class _GlassRim extends CustomPainter {
  const _GlassRim(this.light, this.shade);
  final Color light;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [light, shade, light],
        stops: const [0, .58, 1],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlassRim old) => old.light != light || old.shade != shade;
}

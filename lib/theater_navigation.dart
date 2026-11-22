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
    final solid = mode == Glass.solid || MediaQuery.highContrastOf(context);
    final aero = mode == Glass.aero;
    final liquid = mode == Glass.liquid;
    final dark = colors.brightness == Brightness.dark;
    final radius = BorderRadius.circular(aero ? 0 : 34);
    final tint = Color.alphaBlend(
      colors.primary.withValues(alpha: aero ? .10 : .035),
      colors.surface,
    );
    final highlight = Colors.white.withValues(alpha: dark ? .19 : .72);
    const four = 4;
    final bar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: aero ? 8 : 4, vertical: 4),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                duration: motion(context),
                curve: fluidCurve,
                alignment: Alignment(-1 + 2 * index / (four - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / four,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(aero ? 9 : 30),
                      border: Border.all(
                        color: colors.primary.withValues(
                          alpha: solid ? .45 : .32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            NavigationBarTheme(
              data: NavigationBarThemeData(
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (s) => TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: s.contains(WidgetState.selected)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: s.contains(WidgetState.selected)
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                iconTheme: WidgetStateProperty.resolveWith(
                  (s) => IconThemeData(
                    size: 21,
                    color: s.contains(WidgetState.selected)
                        ? colors.primary
                        : colors.onSurface,
                  ),
                ),
              ),
              child: NavigationBar(
                height: 56,
                selectedIndex: index,
                onDestinationSelected: select,
                backgroundColor: Colors.transparent,
                elevation: 0,
                indicatorColor: Colors.transparent,
                animationDuration: motion(context),
                destinations: [
                  for (final (label, icon, active) in [
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
                      label: label,
                      icon: Icon(icon),
                      selectedIcon: Icon(active),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: solid
            ? colors.surfaceContainerHigh
            : aero
            ? null
            : tint.withValues(alpha: liquid ? .63 : .78),
        gradient: aero && !solid
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    highlight.withValues(alpha: .16),
                    tint,
                  ).withValues(alpha: .82),
                  tint.withValues(alpha: .72),
                ],
              )
            : null,
        borderRadius: radius,
        border: aero
            ? Border(top: BorderSide(color: highlight))
            : Border.all(color: solid ? colors.outlineVariant : highlight),
      ),
      child: Align(widthFactor: aero ? null : 1, heightFactor: 1, child: bar),
    );
    final sigma = liquid
        ? 5.0
        : aero
        ? 12.0
        : 9.0;
    final material = ClipRRect(
      borderRadius: radius,
      child: solid
          ? surface
          : BackdropFilter(
              // Resolve the sample rectangle at paint time in the toolbar's own coordinate space.
              filterConfig: ImageFilterConfig.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                bounded: true,
              ),
              child: surface,
            ),
    );
    return Padding(
      padding: aero
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: aero ? double.infinity : 480),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: dark ? .26 : .14),
                blurRadius: aero ? 5 : 12,
                offset: Offset(0, aero ? -1 : 3),
              ),
            ],
          ),
          child: material,
        ),
      ),
    );
  }
}

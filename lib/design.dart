import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

enum Glass { solid, blur, liquid, aero }

enum Palette { dynamic, monet, amoled }

const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');

Locale chineseLocale(Locale? locale) {
  if (locale?.languageCode != 'zh') return hans;
  if (locale?.scriptCode != null) {
    return locale!.scriptCode == 'Hant' ? hant : hans;
  }
  return {'TW', 'HK', 'MO'}.contains(locale?.countryCode) ? hant : hans;
}

extension ChineseText on BuildContext {
  String zh(String simplified, String traditional) =>
      Localizations.localeOf(this).scriptCode == 'Hant'
      ? traditional
      : simplified;
}

Duration motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : Durations.medium2;
const fluidCurve = Easing.emphasizedDecelerate;

ThemeData theaterTheme(
  Brightness brightness,
  ColorScheme? system,
  Palette mode,
) {
  final generated = ColorScheme.fromSeed(
    seedColor: system?.primary ?? const Color(0xff944663),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.expressive,
  );
  var scheme = mode == Palette.dynamic ? system ?? generated : generated;
  if (mode == Palette.amoled && brightness == Brightness.dark) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'GoogleSans',
    fontFamilyFallback: const ['HarmonyOSSans'],
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const FadeForwardsPageTransitionsBuilder(),
      },
    ),
    elevatedButtonTheme: const ElevatedButtonThemeData(
      variant: StyleVariant.material3Expressive,
    ),
    iconButtonTheme: const IconButtonThemeData(
      variant: StyleVariant.material3Expressive,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class ShapeMark extends StatelessWidget {
  const ShapeMark(this.shape, this.icon, {super.key, this.size = 64});
  final RoundedPolygon shape;
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: motion(context),
      curve: fluidCurve,
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: c.primaryContainer,
        shape: MaterialShapeBorder(shape: shape),
      ),
      child: Icon(icon, size: size * .43, color: c.onPrimaryContainer),
    );
  }
}

class Capsule extends StatefulWidget {
  const Capsule({
    super.key,
    required this.mode,
    required this.index,
    required this.select,
  });
  final Glass mode;
  final int index;
  final ValueChanged<int> select;
  @override
  State<Capsule> createState() => _CapsuleState();
}

class _CapsuleState extends State<Capsule> {
  ui.FragmentShader? shader;
  bool attempted = false;
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(Capsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    _prepare();
  }

  Future<void> _prepare() async {
    if (widget.mode != Glass.liquid ||
        shader != null ||
        attempted ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    attempted = true;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/capsule.frag',
      );
      if (mounted) setState(() => shader = program.fragmentShader());
    } catch (error) {
      debugPrint('Capsule refraction unavailable: $error');
    }
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final style = widget.mode;
    final names = [
      context.zh('剧场', '劇場'),
      context.zh('猜你喜欢', '猜你喜歡'),
      context.zh('历史', '歷史'),
    ];
    Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: style == Glass.aero
            ? null
            : c.surfaceContainerHigh.withValues(
                alpha: style == Glass.solid ? 1 : .73,
              ),
        gradient: style == Glass.aero
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.surface.withValues(alpha: .94),
                  c.primaryContainer.withValues(alpha: .80),
                  c.secondaryContainer.withValues(alpha: .62),
                  c.surface.withValues(alpha: .86),
                ],
                stops: const [0, .49, .51, 1],
              )
            : null,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: c.outlineVariant),
      ),
      child: NavigationBar(
        height: 68,
        selectedIndex: widget.index,
        onDestinationSelected: widget.select,
        animationDuration: motion(context),
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorShape: const StadiumBorder(),
        destinations: [
          for (final (i, icon) in [
            Icons.movie_filter_rounded,
            Icons.auto_awesome_rounded,
            Icons.history_rounded,
          ].indexed)
            NavigationDestination(icon: Icon(icon), label: names[i]),
        ],
      ),
    );
    if (style != Glass.solid) {
      final filter = style == Glass.liquid && shader != null
          ? ui.ImageFilter.shader(shader!)
          : ui.ImageFilter.blur(
              sigmaX: style == Glass.aero ? 14 : 9,
              sigmaY: style == Glass.aero ? 14 : 9,
            );
      bar = BackdropFilter(filter: filter, child: bar);
    }
    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(borderRadius: BorderRadius.circular(100), child: bar),
    );
  }
}

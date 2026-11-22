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
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
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
    final destinations = [
      (context.zh('剧场', '劇場'), Icons.movie_outlined, Icons.movie_rounded),
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
      (context.zh('设置', '設定'), Icons.settings_outlined, Icons.settings_rounded),
    ];
    final solid = style == Glass.solid || MediaQuery.highContrastOf(context);
    final liquid = style == Glass.liquid;
    final aero = style == Glass.aero;
    final rim = BorderRadius.circular(28);
    final dark = c.brightness == Brightness.dark;
    final selected = solid
        ? c.primary
        : Color.lerp(c.surfaceContainerHigh, c.primary, dark ? .30 : .38)!;
    final foreground = solid ? c.onPrimary : c.onSurface;
    final indicator = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rim,
        color: solid || style == Glass.blur
            ? selected.withValues(alpha: solid ? 1 : .88)
            : null,
        gradient: solid || style == Glass.blur
            ? null
            : LinearGradient(
                begin: liquid ? Alignment.topLeft : Alignment.topCenter,
                end: liquid ? Alignment.bottomRight : Alignment.bottomCenter,
                stops: liquid ? const [0, .22, .8, 1] : const [0, .27, .72, 1],
                colors: [
                  Color.lerp(
                    selected,
                    Colors.white,
                    dark ? .12 : (liquid ? .56 : .28),
                  )!.withValues(alpha: .9),
                  selected.withValues(alpha: liquid ? .47 : .73),
                  selected.withValues(alpha: liquid ? .60 : .90),
                  Color.lerp(selected, c.surface, .45)!.withValues(alpha: .83),
                ],
              ),
        border: solid
            ? null
            : Border.all(
                color: c.onSurface.withValues(alpha: liquid ? .22 : .14),
              ),
      ),
    );
    final bar = NavigationBarTheme(
      data: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? foreground
                : c.onSurface,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? foreground
                : c.onSurfaceVariant,
          ),
        ),
      ),
      child: NavigationBar(
        height: 62,
        selectedIndex: widget.index,
        onDestinationSelected: widget.select,
        animationDuration: motion(context),
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorShape: const StadiumBorder(),
        indicatorColor: Colors.transparent,
        destinations: [
          for (final (label, icon, filled) in destinations)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(filled),
              label: label,
            ),
        ],
      ),
    );
    Widget base = ColoredBox(
      color: c.surfaceContainerHigh.withValues(
        alpha: solid
            ? 1
            : aero
            ? .76
            : .82,
      ),
    );
    if (!solid) {
      base = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: aero ? 12 : 7,
          sigmaY: aero ? 12 : 7,
        ),
        child: base,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rim,
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: .12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: rim,
          child: Stack(
            children: [
              Positioned.fill(child: base),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 1 / destinations.length,
                          heightFactor: 1,
                          child: AnimatedSlide(
                            duration: motion(context),
                            curve: fluidCurve,
                            offset: Offset(widget.index.toDouble(), 0),
                            child: ClipRRect(
                              borderRadius: rim,
                              child: liquid && !solid && shader != null
                                  ? BackdropFilter(
                                      filter: ui.ImageFilter.shader(shader!),
                                      child: indicator,
                                    )
                                  : indicator,
                            ),
                          ),
                        ),
                      ),
                    ),
                    bar,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

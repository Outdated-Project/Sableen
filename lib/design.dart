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
    seedColor: system?.primary ?? const Color(0xff8f3c42),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  var scheme = mode == Palette.dynamic ? system ?? generated : generated;
  if (mode == Palette.dynamic && system == null) {
    final dark = brightness == Brightness.dark;
    scheme = scheme.copyWith(
      surface: dark ? const Color(0xff151515) : const Color(0xfffaf9f7),
      surfaceContainer: dark
          ? const Color(0xff272727)
          : const Color(0xffeeedea),
      surfaceContainerLow: dark
          ? const Color(0xff1d1d1d)
          : const Color(0xfff5f4f1),
    );
  }
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
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

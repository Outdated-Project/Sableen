import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';
import 'home.dart';
import 'library.dart';
import 'playback.dart';
import 'preferences.dart';
import 'src/rust/frb_generated.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Sableen());
}

class Sableen extends StatefulWidget {
  const Sableen({super.key});
  @override
  State<Sableen> createState() => _SableenState();
}

class _SableenState extends State<Sableen> {
  late final disk = SharedPreferencesAsync();
  late final prefs = Preferences(disk);
  late final library = Library(disk);
  bool ready = false, failed = false, bridge = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (!bridge) {
        await RustLib.init();
        bridge = true;
      }
      await initializePlayback();
      await prefs.restore();
      await library.restore();
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (light, dark) => ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'Sableen',
        debugShowCheckedModeBanner: false,
        supportedLocales: const [hans, hant],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        locale: switch (prefs.language) {
          'Hans' => hans,
          'Hant' => hant,
          _ => null,
        },
        localeListResolutionCallback: (locales, _) => chineseLocale(
          locales?.where((l) => l.languageCode == 'zh').firstOrNull,
        ),
        theme: theaterTheme(Brightness.light, light, prefs.palette),
        darkTheme: theaterTheme(Brightness.dark, dark, prefs.palette),
        themeMode: prefs.palette == Palette.amoled
            ? ThemeMode.dark
            : ThemeMode.system,
        home: ready
            ? Home(library: library, preferences: prefs)
            : Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: failed
                        ? ElevatedButton(
                            onPressed: () {
                              setState(() => failed = false);
                              _load();
                            },
                            child: Text(context.zh('初始化失败，重试', '初始化失敗，重試')),
                          )
                        : const CircularProgressIndicator(),
                  ),
                ),
              ),
      ),
    ),
  );
}

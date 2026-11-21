import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sableen/design.dart';
import 'package:sableen/home.dart';
import 'package:sableen/library.dart';
import 'package:sableen/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Disk extends Fake implements SharedPreferencesAsync {
  final values = <String, String>{};
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> getString(String key) async => values[key];
}

void main() {
  testWidgets(
    'Compact and wide layouts expose history and persist the chosen glass',
    (tester) async {
      final disk = _Disk();
      final settings = Preferences(disk);
      final library = Library(disk);
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      tester.view.devicePixelRatio = 1;
      for (final width in [360.0, 1280.0]) {
        tester.view.physicalSize = Size(width, 760);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(width),
            locale: hant,
            supportedLocales: const [hans, hant],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theaterTheme(Brightness.light, null, Palette.monet),
            home: Home(library: library, preferences: settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('新增你的第一部短劇'), findsOneWidget);
        await tester.tap(find.text('歷史'));
        await tester.pumpAndSettle();
        expect(find.text('還沒有觀看紀錄'), findsOneWidget);
        await tester.tap(find.byTooltip('設定'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('高斯模糊'));
        await tester.pumpAndSettle();
        final restored = Preferences(disk);
        await restored.restore();
        expect(restored.glass, Glass.blur);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

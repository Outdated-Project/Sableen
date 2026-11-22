import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sableen/design.dart';
import 'package:sableen/home.dart';
import 'package:sableen/library.dart';
import 'package:sableen/preferences.dart';
import 'package:sableen/theater_navigation.dart';
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
  testWidgets('Glass follows the content directly under the bottom bar', (
    tester,
  ) async {
    final boundary = GlobalKey();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    for (final brightness in Brightness.values) {
      for (final mode in [Glass.aero, Glass.liquid]) {
        final theme = theaterTheme(brightness, null, Palette.monet);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundary,
                  child: SizedBox(
                    width: 360,
                    height: 300,
                    child: Stack(
                      children: [
                        ListView(
                          controller: controller,
                          padding: EdgeInsets.zero,
                          children: const [
                            SizedBox(
                              height: 220,
                              child: ColoredBox(color: Colors.blue),
                            ),
                            SizedBox(
                              height: 100,
                              child: ColoredBox(color: Color(0xffff0000)),
                            ),
                            SizedBox(
                              height: 100,
                              child: ColoredBox(color: Color(0xff00ff00)),
                            ),
                            SizedBox(
                              height: 100,
                              child: ColoredBox(color: Colors.white),
                            ),
                            SizedBox(
                              height: 100,
                              child: ColoredBox(color: Colors.black),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: TheaterNavigation(
                            mode: mode,
                            index: 0,
                            select: (_) {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        Future<Color> sample(double offset, {int x = 180, int y = 263}) async {
          controller.jumpTo(offset);
          await tester.pumpAndSettle();
          final layer =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final pixels = await tester.runAsync(() async {
            final image = await layer.toImage();
            try {
              return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            } finally {
              image.dispose();
            }
          });
          // Inside the transparent bar, between two destination icons.
          final start = 4 * (y * 360 + x);
          return Color.fromARGB(
            255,
            pixels!.getUint8(start),
            pixels.getUint8(start + 1),
            pixels.getUint8(start + 2),
          );
        }

        final red = await sample(0);
        final green = await sample(100);
        expect(red.r - green.r, greaterThan(18 / 255), reason: mode.name);
        expect(green.g - red.g, greaterThan(18 / 255), reason: mode.name);
        expect(
          await sample(0, x: 14, y: 226),
          const Color(0xffff0000),
          reason: 'The upper corner is outside the stadium',
        );
        for (final offset in [200.0, 300.0]) {
          final bg = await sample(offset, y: 274);
          final a = theme.colorScheme.onSurface.computeLuminance(),
              b = bg.computeLuminance();
          expect(
            a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
            greaterThanOrEqualTo(4.5),
            reason:
                '$mode $brightness at $offset: $bg vs ${theme.colorScheme.onSurface} on ${theme.colorScheme.surface}',
          );
        }
      }
    }
  });
  testWidgets(
    'High contrast makes Liquid opaque and reduced motion disables tab animation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              highContrast: true,
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TheaterNavigation(
                  mode: Glass.liquid,
                  index: 0,
                  select: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final root = find.byType(TheaterNavigation);
      expect(
        find.descendant(of: root, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .animationDuration,
        Duration.zero,
      );
    },
  );
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
        expect(find.text('紅果短劇'), findsOneWidget);
        expect(find.text('紅果漫劇'), findsOneWidget);
        expect(find.text('沒有符合的劇目'), findsOneWidget);
        expect(find.text('猜你喜歡'), findsOneWidget);
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        await settings.save('glass', 'aero');
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(NavigationBar));
        expect(bar.width, width == 360 ? 336 : 480);
        expect(bar.height, 66);
        expect(bar.center.dx, width / 2);
        expect(bar.bottom, 750);
        await tester.tap(find.text('歷史紀錄'));
        await tester.pumpAndSettle();
        expect(find.text('還沒有觀看紀錄'), findsOneWidget);
        await tester.tap(find.text('設定'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('高斯模糊'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, '一列'));
        await tester.pumpAndSettle();
        final restored = Preferences(disk);
        await restored.restore();
        expect(restored.glass, Glass.blur);
        expect(restored.columns, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

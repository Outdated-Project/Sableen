import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';

class Preferences extends ChangeNotifier {
  Preferences(this.disk);
  final SharedPreferencesAsync disk;
  String language = 'system';
  Glass glass = Glass.solid;
  Palette palette = Palette.dynamic;
  Future<void> restore() async {
    language = await disk.getString('language') ?? 'system';
    final g = await disk.getString('glass'),
        p = await disk.getString('palette');
    glass = Glass.values.where((v) => v.name == g).firstOrNull ?? Glass.solid;
    palette =
        Palette.values.where((v) => v.name == p).firstOrNull ?? Palette.dynamic;
  }

  Future<void> save(String key, String value) async {
    await disk.setString(key, value);
    switch (key) {
      case 'language':
        language = value;
      case 'glass':
        glass = Glass.values.byName(value);
      case 'palette':
        palette = Palette.values.byName(value);
    }
    notifyListeners();
  }
}

class Settings extends StatelessWidget {
  const Settings(this.preferences, {super.key});
  final Preferences preferences;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) {
      Widget group(
        String title,
        String key,
        String selected,
        Map<String, String> values,
      ) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final v in values.entries)
                  ChoiceChip(
                    label: Text(v.value),
                    selected: v.key == selected,
                    onSelected: (_) async {
                      try {
                        await preferences.save(key, v.key);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.zh('设置保存失败', '設定儲存失敗')),
                            ),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      );
      return Scaffold(
        appBar: AppBar(title: Text(context.zh('设置', '設定'))),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                group(
                  context.zh('界面语言', '介面語言'),
                  'language',
                  preferences.language,
                  {
                    'system': context.zh('跟随系统', '跟隨系統'),
                    'Hans': '简体中文',
                    'Hant': '繁體中文',
                  },
                ),
                group(
                  context.zh('主题配色', '主題配色'),
                  'palette',
                  preferences.palette.name,
                  {
                    'dynamic': context.zh('系统动态色', '系統動態色'),
                    'monet': 'Monet',
                    'amoled': 'AMOLED Monet',
                  },
                ),
                group(
                  context.zh('导航栏材质', '導覽列材質'),
                  'glass',
                  preferences.glass.name,
                  {
                    'solid': context.zh('原色', '原色'),
                    'blur': context.zh('高斯模糊', '高斯模糊'),
                    'liquid': context.zh('流动玻璃', '流動玻璃'),
                    'aero': context.zh('极光玻璃', '極光玻璃'),
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

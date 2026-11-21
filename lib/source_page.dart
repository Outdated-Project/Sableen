import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'library.dart';

class SourcePage extends StatefulWidget {
  const SourcePage(this.library, {super.key});
  final Library library;
  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  late final feed = TextEditingController(
    text: widget.library.source.startsWith('https://')
        ? widget.library.source
        : defaultFeed,
  );
  final stream = TextEditingController(),
      title = TextEditingController(),
      tag = TextEditingController();
  bool direct = false, busy = false, failed = false;
  @override
  void dispose() {
    for (final c in [feed, stream, title, tag]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({bool public = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      if (public) {
        await widget.library.usePublicCatalog();
      } else if (direct) {
        await widget.library.addVideo(
          title.text.trim(),
          tag.text.trim(),
          stream.text.trim(),
        );
      } else {
        await widget.library.loadFeed(feed.text.trim());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(
      TextEditingController ctrl,
      String label, {
      bool url = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        enabled: !busy,
        autocorrect: !url,
        keyboardType: url ? TextInputType.url : TextInputType.text,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.zh('添加片源', '新增片源'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ListTile(
                  leading: const Icon(Icons.live_tv_rounded),
                  title: Text(context.zh('公共剧场', '公共劇場')),
                  subtitle: Text(
                    context.zh('央视频剧场 · 广州微短剧 · 红果片段', '央視頻劇場 · 廣州微短劇 · 紅果片段'),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: busy ? null : () => _submit(public: true),
                ),
                const Divider(),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in [false, true])
                      ChoiceChip(
                        label: Text(
                          v
                              ? context.zh('单条视频', '單部影片')
                              : context.zh('订阅剧单', '訂閱劇單'),
                        ),
                        selected: direct == v,
                        onSelected: busy
                            ? null
                            : (_) => setState(() {
                                direct = v;
                                failed = false;
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (direct) ...[
                  field(title, context.zh('剧名', '劇名')),
                  field(tag, context.zh('题材', '題材')),
                  field(
                    stream,
                    context.zh('视频地址（HTTPS）', '影片位址（HTTPS）'),
                    url: true,
                  ),
                ] else
                  field(
                    feed,
                    context.zh('剧单地址（HTTPS JSON）', '劇單位址（HTTPS JSON）'),
                    url: true,
                  ),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      direct
                          ? context.zh(
                              '请检查剧名、题材和 HTTPS 视频地址。',
                              '請檢查劇名、題材和 HTTPS 影片位址。',
                            )
                          : context.zh(
                              '无法读取剧单。请检查网络、地址和剧单格式。',
                              '無法讀取劇單。請檢查網路、位址和劇單格式。',
                            ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : _submit,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      busy
                          ? context.zh('读取中', '讀取中')
                          : context.zh('加入剧场', '加入劇場'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

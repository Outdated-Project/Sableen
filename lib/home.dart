import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'library.dart';
import 'playback.dart';
import 'preferences.dart';
import 'source_page.dart';
import 'src/rust/api/library.dart';

class Home extends StatefulWidget {
  const Home({super.key, required this.library, required this.preferences});
  final Library library;
  final Preferences preferences;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  String query = '';
  Publisher? publisher;
  final search = TextEditingController();
  late Future<List<Drama>> ranked;
  Library get library => widget.library;
  @override
  void initState() {
    super.initState();
    ranked = Future.value([]);
  }

  void _select(int value) {
    setState(() {
      tab = value;
      if (tab == 1) ranked = library.ranked();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _source() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SourcePage(library)),
    );
    if (ok == true && mounted) {
      setState(() {
        tab = 0;
        query = '';
        publisher = null;
        search.clear();
      });
    }
  }

  Future<void> _watch(Drama d) async {
    final last = library.latest(d.id);
    var i = d.episodes.indexWhere((e) => e.id == last?.episode);
    if (i < 0) {
      i = 0;
    } else if (last!.completed && i + 1 < d.episodes.length) {
      i++;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Theater(library: library, drama: d, initial: i),
      ),
    );
    if (mounted && tab == 1) _select(1);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.zh('清空本剧单的观看历史？', '清空此劇單的觀看歷史？')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.zh('取消', '取消')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.zh('清空', '清空')),
          ),
        ],
      ),
    );
    if (ok == true) await library.clearHistory();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final names = [
        context.zh('我的剧场', '我的劇場'),
        context.zh('猜你喜欢', '猜你喜歡'),
        context.zh('观看历史', '觀看歷史'),
      ];
      final known = <String>{};
      final rows = switch (tab) {
        0 =>
          library.dramas
              .where(
                (d) =>
                    (publisher == null ||
                        library.publishers[d.id] == publisher) &&
                    (query.isEmpty ||
                        d.title.contains(query) ||
                        d.tags.any((t) => t.contains(query))),
              )
              .toList(),
        2 => [
          for (final h in library.history)
            if (known.add(h.drama) && library.byId[h.drama] != null)
              library.byId[h.drama]!,
        ],
        _ => <Drama>[],
      };
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final inset = box.maxWidth >= 840 ? 48.0 : 20.0;
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(tab),
                        duration: motion(context),
                        curve: fluidCurve,
                        tween: Tween(begin: 0, end: 1),
                        builder: (context, progress, child) =>
                            Transform.translate(
                              offset: Offset(0, 12 * (1 - progress)),
                              child: Opacity(opacity: progress, child: child),
                            ),
                        child: CustomScrollView(
                          key: PageStorageKey(tab),
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                inset,
                                16,
                                inset,
                                12,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Row(
                                  children: [
                                    ShapeMark(
                                      MaterialShapes.cookie6Sided,
                                      Icons.play_arrow_rounded,
                                      size: 42,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Sableen',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: context.zh('添加片源', '新增片源'),
                                      onPressed: _source,
                                      icon: const Icon(Icons.add_rounded),
                                    ),
                                    IconButton(
                                      tooltip: context.zh('设置', '設定'),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              Settings(widget.preferences),
                                        ),
                                      ),
                                      icon: const Icon(Icons.tune_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(
                                inset,
                                24,
                                inset,
                                18,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        names[tab],
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    if (tab == 2 &&
                                        (library.history.isNotEmpty ||
                                            library.historyDamaged))
                                      IconButton(
                                        tooltip: context.zh('清空历史', '清空歷史'),
                                        onPressed: _clear,
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if ((library.historyDamaged ||
                                    library.writeFailed) &&
                                tab == 2)
                              SliverPadding(
                                padding: EdgeInsets.all(inset),
                                sliver: SliverToBoxAdapter(
                                  child: Text(
                                    library.historyDamaged
                                        ? context.zh(
                                            '记录无法读取。清空历史后可重新记录。',
                                            '紀錄無法讀取。清空歷史後可重新記錄。',
                                          )
                                        : context.zh(
                                            '记录未能保存到设备。',
                                            '紀錄未能儲存到裝置。',
                                          ),
                                  ),
                                ),
                              ),
                            if (tab == 0 && library.dramas.isNotEmpty)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  inset,
                                  0,
                                  inset,
                                  20,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: TextField(
                                    controller: search,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(
                                        Icons.search_rounded,
                                      ),
                                      hintText: context.zh(
                                        '搜索剧名或题材',
                                        '搜尋劇名或題材',
                                      ),
                                    ),
                                    onChanged: (s) =>
                                        setState(() => query = s.trim()),
                                  ),
                                ),
                              ),
                            if (tab == 0 && library.source == publicCatalog)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  inset,
                                  0,
                                  inset,
                                  16,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      for (final (value, label)
                                          in <(Publisher?, String)>[
                                            (null, '全部'),
                                            (
                                              Publisher.cctv,
                                              context.zh('央视频剧场', '央視頻劇場'),
                                            ),
                                            (
                                              Publisher.guangzhou,
                                              context.zh('广州微短剧', '廣州微短劇'),
                                            ),
                                            (
                                              Publisher.hongguo,
                                              context.zh('红果片段', '紅果片段'),
                                            ),
                                          ])
                                        ChoiceChip(
                                          label: Text(label),
                                          selected: publisher == value,
                                          onSelected: (_) =>
                                              setState(() => publisher = value),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (tab == 1)
                              FutureBuilder<List<Drama>>(
                                future: ranked,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return SliverToBoxAdapter(
                                      child: Center(
                                        child: ElevatedButton(
                                          onPressed: () => _select(1),
                                          child: Text(
                                            context.zh('重新推荐', '重新推薦'),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (!snapshot.hasData) {
                                    return const SliverToBoxAdapter(
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return _shelf(
                                    context,
                                    snapshot.data!,
                                    inset,
                                    box.maxWidth,
                                  );
                                },
                              )
                            else
                              _shelf(context, rows, inset, box.maxWidth),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 110),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Capsule(
                      mode: widget.preferences.glass,
                      index: tab,
                      select: _select,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _shelf(
    BuildContext context,
    List<Drama> dramas,
    double inset,
    double width,
  ) {
    if (dramas.isEmpty) {
      final emptySource = library.dramas.isEmpty;
      final text = switch (tab) {
        0 =>
          library.sourceFailed
              ? context.zh('剧单读取失败', '劇單讀取失敗')
              : emptySource
              ? context.zh('添加你的第一部短剧', '新增你的第一部短劇')
              : context.zh('没有匹配的剧目', '沒有符合的劇目'),
        1 => context.zh('暂无可推荐的剧目', '暫無可推薦的劇目'),
        _ => context.zh('还没有观看记录', '還沒有觀看紀錄'),
      };
      final c = Theme.of(context).colorScheme;
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        sliver: SliverToBoxAdapter(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceContainerLow,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
              child: Column(
                children: [
                  ShapeMark(
                    [
                      MaterialShapes.arch,
                      MaterialShapes.softBurst,
                      MaterialShapes.pill,
                    ][tab],
                    [
                      Icons.movie_filter_rounded,
                      Icons.auto_awesome_rounded,
                      Icons.history_rounded,
                    ][tab],
                    size: 92,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (emptySource) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _source,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.zh('添加片源', '新增片源')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: width < 550 ? 500 : 360,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 180 + 82 * scale,
        ),
        itemCount: dramas.length,
        itemBuilder: (context, i) {
          final d = dramas[i],
              p = library.latest(d.id),
              c = Theme.of(context).colorScheme;
          final shape = [
            MaterialShapes.arch,
            MaterialShapes.cookie7Sided,
            MaterialShapes.slanted,
            MaterialShapes.flower,
          ][i % 4];
          final single = d.episodes.singleOrNull;
          final origin = library.publishers[d.id];
          final availability =
              library.publishers[d.id] == Publisher.hongguo && single != null
              ? single.title
              : '${d.episodes.length} 集';
          Widget fallback() => ColoredBox(
            color: c.secondaryContainer,
            child: Center(
              child: ShapeMark(shape, Icons.play_arrow_rounded, size: 92),
            ),
          );
          return Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _watch(d),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: origin != null
                        ? Image.asset(
                            'assets/posters/${origin.name}-${d.episodes.first.id}.webp',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => fallback(),
                          )
                        : d.cover == null
                        ? fallback()
                        : Image.network(
                            d.cover!,
                            fit: BoxFit.cover,
                            cacheWidth: 600,
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, _, _) => fallback(),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab == 2 && p != null
                              ? '${d.episodes.where((e) => e.id == p.episode).firstOrNull?.title ?? ''} · ${clock(p.positionMs)}'
                              : '$availability   ${d.tags.join(' · ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_ui/material_ui.dart';

import 'design.dart';
import 'drama_shelf.dart';
import 'library.dart';
import 'offline.dart';
import 'playback.dart';
import 'playback_window.dart';
import 'preferences.dart';
import 'src/rust/api/library.dart';
import 'theater_navigation.dart';

enum _Filter { all, recommended, live, comic }

class Home extends StatefulWidget {
  const Home({super.key, required this.library, required this.preferences});
  final Library library;
  final Preferences preferences;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  _Filter filter = _Filter.all;
  final search = TextEditingController();
  String query = '';
  Future<List<Drama>>? ranked;
  bool enteringTheater = false;
  Library get library => widget.library;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void _setFilter(_Filter value) => setState(() {
    filter = value;
    if (value == _Filter.recommended) ranked = library.ranked();
  });

  Future<void> _watch(
    Drama drama,
    ImageProvider? poster, [
    Episode? selected,
  ]) async {
    if (enteringTheater) return;
    enteringTheater = true;
    try {
      final last = library.latest(drama.id);
      var episode = drama.episodes.indexWhere(
        (e) => e.id == (selected?.id ?? last?.episode),
      );
      if (episode < 0) {
        episode = 0;
      } else if (selected == null &&
          last!.completed &&
          episode + 1 < drama.episodes.length) {
        episode++;
      }
      final fullscreen = setTheaterFullscreen(true);
      if (!kIsWeb) {
        await fullscreen;
        if (mounted && playbackOnPhone(context)) {
          await setPhoneOrientation(PhoneOrientation.automatic);
        }
      } else {
        unawaited(fullscreen);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Theater(
            library: library,
            drama: drama,
            initial: episode,
            poster: poster,
          ),
        ),
      );
    } finally {
      try {
        if (mounted && playbackOnPhone(context)) {
          await setPhoneOrientation(PhoneOrientation.portrait);
        }
        await setTheaterFullscreen(false);
      } finally {
        enteringTheater = false;
      }
    }
    if (mounted && filter == _Filter.recommended) _setFilter(filter);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.zh('清空观看历史？', '清空觀看歷史？')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.zh('取消', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.zh('清空', '清空')),
          ),
        ],
      ),
    );
    if (ok == true) await library.clearHistory();
  }

  List<Drama> _results(Iterable<Drama> titles) => titles
      .where((d) {
        final origin = library.publishers[d.id];
        if (filter == _Filter.live && origin != Publisher.hongguo ||
            filter == _Filter.comic && origin != Publisher.comic) {
          return false;
        }
        return query.isEmpty ||
            d.title.contains(query) ||
            d.tags.any((tag) => tag.contains(query));
      })
      .toList(growable: false);

  Widget _catalog(BuildContext context, {required bool history}) {
    final seen = <String>{};
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final insets = wide ? 36.0 : 16.0;
    final colors = Theme.of(context).colorScheme;
    final searchField = TextField(
      controller: search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: context.zh('搜索剧名或题材', '搜尋劇名或題材'),
      ),
      onChanged: (s) => setState(() => query = s.trim()),
    );
    Widget shelf(List<Drama> items) => DramaShelf(
      library: library,
      columns: widget.preferences.columns,
      titles: items,
      history: history,
      onOpen: _watch,
      emptyText: history
          ? context.zh('还没有观看记录', '還沒有觀看紀錄')
          : context.zh('没有匹配的剧目', '沒有符合的劇目'),
    );
    final labels = [
      '全部',
      context.zh('猜你喜欢', '猜你喜歡'),
      context.zh('红果短剧', '紅果短劇'),
      context.zh('红果漫剧', '紅果漫劇'),
    ];
    return CustomScrollView(
      key: PageStorageKey(history ? 'history' : 'catalog-${filter.name}'),
      scrollCacheExtent: const ScrollCacheExtent.pixels(150),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            insets,
            wide ? 30 : 18,
            insets,
            wide ? 20 : 12,
          ),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                if (!history) ...[
                  Image.asset(
                    'assets/brand/sableen.png',
                    width: 38,
                    height: 38,
                    cacheWidth: 96,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    history
                        ? context.zh('历史纪录', '歷史紀錄')
                        : context.zh('剧场', '劇場'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                ),
                if (wide && !history) SizedBox(width: 300, child: searchField),
                if (!history)
                  IconButton(
                    tooltip: widget.preferences.columns == 2
                        ? context.zh('切换为单列', '切換為單列')
                        : context.zh('切换为双列', '切換為雙列'),
                    icon: Icon(
                      widget.preferences.columns == 2
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_rounded,
                    ),
                    onPressed: () => context.choosePreference(
                      widget.preferences,
                      'columns',
                      widget.preferences.columns == 2 ? '1' : '2',
                    ),
                  ),
                if (history &&
                    (library.history.isNotEmpty || library.historyDamaged))
                  IconButton(
                    tooltip: context.zh('清空历史', '清空歷史'),
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        ),
        if (history && (library.historyDamaged || library.writeFailed))
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(insets),
              child: Text(
                library.historyDamaged
                    ? context.zh('记录无法读取，清空历史后可重新记录。', '紀錄無法讀取，清空歷史後可重新記錄。')
                    : context.zh('记录未能保存到设备。', '紀錄未能儲存到裝置。'),
              ),
            ),
          ),
        if (!history)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: insets),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!wide) ...[searchField, const SizedBox(height: 8)],
                  Wrap(
                    spacing: 5,
                    runSpacing: 2,
                    children: [
                      for (final item in _Filter.values)
                        ChoiceChip(
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          shape: const StadiumBorder(),
                          label: Text(labels[item.index]),
                          showCheckmark: false,
                          side: BorderSide.none,
                          selectedColor: colors.primary,
                          backgroundColor: colors.surfaceContainer,
                          labelStyle: TextStyle(
                            fontWeight: filter == item
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: filter == item
                                ? colors.onPrimary
                                : colors.onSurface,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          selected: filter == item,
                          onSelected: (_) => _setFilter(item),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(insets, 0, insets, 110),
          sliver: history
              ? shelf([
                  for (final p in library.history)
                    if (seen.add(p.drama)) ?library.byId[p.drama],
                ])
              : filter == _Filter.recommended
              ? FutureBuilder<List<Drama>>(
                  future: ranked,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: Center(
                          child: TextButton(
                            onPressed: () => _setFilter(filter),
                            child: Text(context.zh('重试推荐', '重試推薦')),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const SliverToBoxAdapter(
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return shelf(_results(snapshot.requireData));
                  },
                )
              : shelf(_results(library.dramas)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final page = switch (tab) {
        0 => _catalog(context, history: false),
        1 => ListenableBuilder(
          listenable: library,
          builder: (context, _) => _catalog(context, history: true),
        ),
        2 => downloadsPage(library.dramas, (d, e) => _watch(d, null, e)),
        _ => Settings(widget.preferences),
      };
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1060),
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(tab),
                    tween: Tween(begin: 0, end: 1),
                    duration: motion(context),
                    curve: fluidCurve,
                    builder: (context, t, child) => Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: child,
                    ),
                    child: page,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: TheaterNavigation(
                  mode: widget.preferences.glass,
                  index: tab,
                  select: (index) {
                    if (tab == index) return;
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() {
                      tab = index;
                      if (tab == 0 && filter == _Filter.recommended) {
                        ranked = library.ranked();
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'design.dart';
import 'library.dart';
import 'src/rust/api/library.dart';

bool _acceleratedTexture = true;

Future<void> initializePlayback() async {
  MediaKit.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    _acceleratedTexture =
        await const MethodChannel('sableen/video')
            .invokeMethod<bool>('supportsAcceleratedTexture') ??
        false;
  }
}

String clock(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class Theater extends StatefulWidget {
  const Theater({
    super.key,
    required this.library,
    required this.drama,
    required this.initial,
  });
  final Library library;
  final Drama drama;
  final int initial;
  @override
  State<Theater> createState() => _TheaterState();
}

class _TheaterState extends State<Theater> with WidgetsBindingObserver {
  late final Player player;
  late final VideoController video;
  final subscriptions = <StreamSubscription<dynamic>>[];
  final elapsed = Stopwatch();
  final timeline = ValueNotifier(0);
  late int index;
  int watched = 0, previous = 0, lastWrite = 0;
  bool opening = true, failed = false, closed = false, completed = false;
  bool background = false, seeking = false;
  double? dragging;
  double requested = 0;
  int? skippedBreak;
  int? pendingWebStart;
  Episode get episode => widget.drama.episodes[index];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    background =
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden;
    index = widget.initial;
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
        protocolWhitelist: ['https', 'tcp', 'tls', 'crypto'],
      ),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: _acceleratedTexture,
      ),
    );
    subscriptions.addAll([
      player.stream.position.listen(_position),
      player.stream.duration.listen((_) => _update()),
      player.stream.buffering.listen((_) {
        _resetEvidence();
        _cadence();
        _update();
      }),
      player.stream.playing.listen((playing) {
        _resetEvidence();
        _cadence();
        if (!playing && !opening) _save();
        _update();
      }),
      player.stream.tracks.listen((_) => _cadence()),
      player.stream.track.listen((_) => _cadence()),
      player.stream.completed.listen((done) {
        if (!done || closed || opening || completed) return;
        completed = true;
        _save();
        _cadence();
        if (!background && index + 1 < widget.drama.episodes.length) {
          unawaited(_open(index + 1));
        } else {
          _update();
        }
      }),
      player.stream.error.listen((error) {
        if (error.isNotEmpty && !closed) {
          if (kDebugMode) debugPrint('Player reported: $error');
          failed = true;
          _cadence();
          _update();
        }
      }),
    ]);
    unawaited(_open(index));
  }

  void _update() {
    if (mounted && !closed) setState(() {});
  }

  Future<void> _open(int next) async {
    if (closed) return;
    if (!opening) _save();
    opening = true;
    failed = false;
    completed = false;
    dragging = null;
    index = next;
    final prior = widget.library.latest(widget.drama.id, episode.id);
    previous = prior == null || prior.completed ? 0 : prior.positionMs;
    previous = _contentPosition(previous);
    pendingWebStart = kIsWeb && previous > 0 ? previous : null;
    skippedBreak = null;
    watched = prior?.watchedMs ?? 0;
    timeline.value = previous;
    _cadence();
    _update();
    try {
      await player.open(
        Media(
          episode.url,
          start: !kIsWeb && previous > 0
              ? Duration(milliseconds: previous)
              : null,
        ),
        play: !background,
      );
      if (!closed && background) await player.pause();
    } catch (_) {
      failed = true;
    }
    if (closed) return;
    opening = false;
    lastWrite = 0;
    lastTick = 0;
    elapsed.reset();
    elapsed.start();
    _resetEvidence();
    _cadence();
    _update();
  }

  int lastTick = 0;
  bool hasBaseline = false;

  void _resetEvidence() {
    hasBaseline = false;
    lastTick = elapsed.elapsedMilliseconds;
  }

  Future<void> _seek(int target) async {
    if (closed || seeking || opening) return;
    seeking = true;
    final currentIndex = index;
    target = _contentPosition(target)
        .clamp(0, player.state.duration.inMilliseconds);
    previous = target;
    timeline.value = target;
    _resetEvidence();
    _update();
    try {
      await player.seek(Duration(milliseconds: target));
    } catch (_) {
      if (!closed && index == currentIndex) failed = true;
    } finally {
      if (!closed) {
        seeking = false;
        _resetEvidence();
        _cadence();
        _update();
      }
    }
  }

  int _contentPosition(int ms) {
    for (final interval in episode.adBreaks ?? const <AdBreak>[]) {
      if (ms < interval.startMs) break;
      if (ms < interval.endMs) return interval.endMs;
    }
    return ms;
  }

  void _position(Duration position) {
    if (closed || opening || seeking || background) return;
    final ms = position.inMilliseconds, now = elapsed.elapsedMilliseconds;
    if (failed) {
      if (!player.state.playing || player.state.buffering || ms <= previous)
        return;
      failed = false;
      _resetEvidence();
      _update();
    }
    final resume = pendingWebStart;
    if (resume != null) {
      final duration = player.state.duration.inMilliseconds;
      if (duration <= 0) return;
      pendingWebStart = null;
      unawaited(_seek(resume < duration ? resume : 0));
      return;
    }
    final content = _contentPosition(ms);
    if (content != ms) {
      if (skippedBreak != content) {
        skippedBreak = content;
        if (player.state.duration > Duration.zero) {
          unawaited(_seek(content));
        } else {
          skippedBreak = null;
        }
      }
      return;
    }
    skippedBreak = null;
    final delta = ms - previous;
    final advancing = player.state.playing && !player.state.buffering;
    if (hasBaseline &&
        advancing &&
        delta > 0 &&
        delta <= now - lastTick + 750) {
      watched += math.min(delta, math.max(0, now - lastTick));
    }
    hasBaseline = advancing;
    previous = ms;
    lastTick = now;
    if (dragging == null && (timeline.value - ms).abs() >= 250) {
      timeline.value = ms;
    }
    if (now - lastWrite >= 10000) {
      _save();
      lastWrite = now;
    }
  }

  void _save() {
    final duration = player.state.duration.inMilliseconds;
    if (opening || duration <= 0 || watched <= 0) return;
    widget.library.record(
      Progress(
        drama: widget.drama.id,
        episode: episode.id,
        positionMs: (completed ? duration : previous).clamp(0, duration),
        durationMs: duration,
        watchedMs: watched.clamp(0, duration),
        updated: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        completed: completed,
      ),
    );
  }

  void _cadence() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final selected = player.state.track.video;
    final tracks = player.state.tracks.video.where((t) => (t.fps ?? 0) > 0);
    final fps = selected.id == 'no'
        ? 0.0
        : (selected.fps ?? 0) > 0
        ? selected.fps!
        : tracks.where((t) => t.id == selected.id).firstOrNull?.fps ??
              tracks.firstOrNull?.fps ??
              0.0;
    final next =
        closed ||
            opening ||
            failed ||
            completed ||
            background ||
            !player.state.playing ||
            player.state.buffering
        ? 0.0
        : fps;
    if (next == requested) return;
    requested = next;
    unawaited(
      const OptionalMethodChannel('sableen/display')
          .invokeMethod<void>('cadence', next),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      background = true;
      _resetEvidence();
      _cadence();
      unawaited(player.pause());
      _save();
    } else if (state == AppLifecycleState.resumed) {
      background = false;
      _cadence();
    }
  }

  @override
  void dispose() {
    closed = true;
    _cadence();
    _save();
    elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    timeline.dispose();
    unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final frame = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: video,
            controls: null,
            pauseUponEnteringBackgroundMode: false,
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
          ),
          if (opening || player.state.buffering)
            const Center(child: CircularProgressIndicator()),
          if (failed)
            Center(
              child: ElevatedButton.icon(
                onPressed: opening ? null : () => _open(index),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.zh('播放失败，重试', '播放失敗，重試')),
              ),
            ),
        ],
      ),
    );
    final controls = Row(
      children: [
        IconButton.filled(
          tooltip: player.state.playing ? context.zh('暂停', '暫停') : '播放',
          onPressed: opening
              ? null
              : () {
                  if (completed || failed) {
                    _open(index);
                  } else {
                    player.playOrPause();
                  }
                },
          icon: Icon(
            player.state.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: timeline,
            builder: (context, position, _) {
              final duration = player.state.duration.inMilliseconds;
              final value = (dragging ?? position.toDouble()).clamp(
                0.0,
                math.max(1, duration).toDouble(),
              );
              return Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: value,
                      max: math.max(1, duration).toDouble(),
                      semanticFormatterCallback: (v) => clock(v.round()),
                      onChanged: opening || seeking || failed || duration <= 0
                          ? null
                          : (v) {
                              dragging = v;
                              timeline.value = v.round();
                            },
                      onChangeEnd: (v) {
                        dragging = null;
                        unawaited(_seek(v.round()));
                      },
                    ),
                  ),
                  Text('${clock(value.round())} / ${clock(duration)}'),
                ],
              );
            },
          ),
        ),
      ],
    );
    final list = ListView.builder(
      itemCount: widget.drama.episodes.length,
      itemBuilder: (context, i) => ListTile(
        selected: i == index,
        selectedTileColor: c.secondaryContainer,
        title: Text(widget.drama.episodes[i].title),
        leading: Icon(
          i == index
              ? Icons.play_circle_fill_rounded
              : Icons.play_circle_outline_rounded,
        ),
        onTap: opening || seeking || (i == index && !failed)
            ? null
            : () => _open(i),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.drama.title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= 780 ||
                (box.maxWidth > box.maxHeight * 1.6 && box.maxHeight < 420);
            final stage = Column(
              children: [
                Expanded(child: frame),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: controls,
                ),
              ],
            );
            return wide
                ? Row(
                    children: [
                      Expanded(child: stage),
                      SizedBox(
                        width: (box.maxWidth * .28).clamp(180, 340),
                        child: list,
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(flex: 3, child: stage),
                      Expanded(child: list),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

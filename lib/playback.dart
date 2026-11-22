import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'design.dart';
import 'library.dart';
import 'offline.dart';
import 'playback_window.dart';
import 'src/rust/api/library.dart';

bool _acceleratedTexture = true;
bool _androidEmulator = false;

Future<void> initializePlayback() async {
  MediaKit.ensureInitialized();
  if (androidVideo) {
    _androidEmulator =
        await const OptionalMethodChannel('com.alexmercerind/media_kit_video')
            .invokeMethod<bool>('Utils.IsEmulator') ??
        false;
  }
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
    this.poster,
  });
  final Library library;
  final Drama drama;
  final int initial;
  final ImageProvider? poster;
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
  bool showControls = true, smallWindow = false, supportsPip = false;
  bool landscape = false;
  Timer? hideControls;
  int visibilityChange = 0;
  late final VoidCallback removePipListener;
  double? dragging;
  double requested = 0;
  int? skippedBreak;
  int? pendingWebStart;
  String? localSource;
  Episode get episode => widget.drama.episodes[index];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    removePipListener = observeBrowserPipExit(_refreshVisibility);
    if (androidVideo) {
      displayChannel.setMethodCallHandler((call) async {
        if (call.method == 'pipChanged' && !closed) {
          smallWindow = call.arguments == true;
          _refreshVisibility();
          _update();
        }
      });
    }
    supportsSmallWindow().then((value) {
      supportsPip = value;
      _update();
    });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    background =
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden;
    index = widget.initial;
    player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
        protocolWhitelist: ['https', 'tcp', 'tls', 'crypto', 'file'],
      ),
    );
    video = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: _acceleratedTexture,
        // The emulator's SwiftShader EGL output can advance the clock while
        // showing black. Let the Android codec write into the texture surface.
        vo: _androidEmulator ? 'mediacodec_embed' : null,
        hwdec: _androidEmulator ? 'mediacodec' : null,
      ),
    );
    subscriptions.addAll([
      if (_androidEmulator)
        player.stream.log.listen((log) {
          if (log.level == 'error' || log.level == 'fatal') {
            debugPrint('Media ${log.prefix}: ${log.text}');
          }
        }),
      player.stream.position.listen(_position),
      player.stream.duration.listen((_) => _update()),
      player.stream.width.listen((_) => _update()),
      player.stream.height.listen((_) => _update()),
      player.stream.buffering.listen((_) {
        _resetEvidence();
        if (!opening && !player.state.buffering && showControls) {
          _scheduleControls(player.state.playing);
        }
        _cadence();
        _update();
      }),
      player.stream.playing.listen((playing) {
        _scheduleControls(playing);
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

  void _scheduleControls(bool playing) {
    if (closed) return;
    hideControls?.cancel();
    if (!playing || MediaQuery.accessibleNavigationOf(context)) {
      showControls = true;
    } else {
      hideControls = Timer(const Duration(seconds: 3), () {
        if (!closed &&
            dragging == null &&
            !failed &&
            !opening &&
            !player.state.buffering) {
          setState(() => showControls = false);
        }
      });
    }
  }

  void _reveal() {
    final hidden = !showControls;
    _scheduleControls(player.state.playing);
    if (hidden) setState(() => showControls = true);
  }

  void _togglePlaying() {
    if (opening || closed || background) return;
    _reveal();
    if (completed || failed) {
      unawaited(_open(index));
    } else {
      unawaited(player.playOrPause());
    }
  }

  void _toggleLandscape() {
    setState(() => landscape = !landscape);
    unawaited(setPlaybackLandscape(landscape));
    _reveal();
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
      final local = await offlinePath(episode);
      if (closed) {
        releaseOfflinePath(local);
        return;
      }
      final old = localSource;
      localSource = local;
      try {
        await player.open(
          Media(
            local ?? episode.url,
            start: !kIsWeb && previous > 0
                ? Duration(milliseconds: previous)
                : null,
          ),
          play: !background,
        );
      } finally {
        releaseOfflinePath(old);
      }
      if (!closed && background) await player.pause();
    } catch (_) {
      failed = true;
    }
    if (closed) return;
    opening = false;
    _scheduleControls(player.state.playing);
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
      if (!player.state.playing || player.state.buffering || ms <= previous) {
        return;
      }
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
    final revision = ++visibilityChange;
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      background = false;
      _cadence();
      return;
    }
    unawaited(_checkVisibility(state, revision));
  }

  void _refreshVisibility() {
    if (!closed) {
      didChangeAppLifecycleState(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      );
    }
  }

  Future<void> _checkVisibility(AppLifecycleState state, int revision) async {
    final visible =
        state != AppLifecycleState.detached && await videoInSmallWindow();
    if (closed || visibilityChange != revision) return;
    background = !visible;
    _resetEvidence();
    _cadence();
    if (background) {
      await player.pause();
      if (!closed) _save();
    }
  }

  @override
  void dispose() {
    closed = true;
    if (landscape) unawaited(setPlaybackLandscape(false));
    removePipListener();
    hideControls?.cancel();
    if (androidVideo) displayChannel.setMethodCallHandler(null);
    _cadence();
    _save();
    elapsed.stop();
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    timeline.dispose();
    unawaited(
      player.dispose().whenComplete(() => releaseOfflinePath(localSource)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = Video(
      controller: video,
      controls: null,
      pauseUponEnteringBackgroundMode: false,
      subtitleViewConfiguration: const SubtitleViewConfiguration(
        visible: false,
      ),
    );
    final controls = Row(
      children: [
        IconButton.filled(
          tooltip: player.state.playing ? context.zh('暂停', '暫停') : '播放',
          onPressed: opening ? null : _togglePlaying,
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
                        _reveal();
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
    final rotate =
        landscape &&
        !smallWindow &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return RotatedBox(
      quarterTurns: rotate ? 1 : 0,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _reveal(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              surface,
              if (widget.poster case final poster?
                  when !MediaQuery.disableAnimationsOf(context))
                Hero(
                  tag: widget.drama.id,
                  flightShuttleBuilder: (_, animation, direction, _, _) =>
                      FadeTransition(
                        opacity: ReverseAnimation(animation),
                        child: Image(
                          image: poster,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                  child: const SizedBox.expand(),
                ),
              if (!smallWindow) ...[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: _reveal,
                ),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: .45,
                    heightFactor: .45,
                    child: GestureDetector(
                      key: const ValueKey('center-playback'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _togglePlaying,
                      child: Semantics(
                        button: true,
                        label: player.state.playing
                            ? context.zh('暂停', '暫停')
                            : '播放',
                      ),
                    ),
                  ),
                ),
                if (opening || player.state.buffering)
                  const IgnorePointer(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (failed)
                  Center(
                    child: FilledButton.tonalIcon(
                      onPressed: opening ? null : () => _open(index),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.zh('播放失败，重试', '播放失敗，重試')),
                    ),
                  ),
                if (showControls || failed)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                onPressed: () => Navigator.maybePop(context),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const Spacer(),
                              downloadButton(
                                widget.library.dramas,
                                drama: widget.drama,
                                episode: episode,
                              ),
                              if (androidVideo ||
                                  (!kIsWeb &&
                                      defaultTargetPlatform ==
                                          TargetPlatform.iOS) ||
                                  landscape ||
                                  MediaQuery.orientationOf(context) ==
                                      Orientation.portrait)
                                IconButton.filledTonal(
                                  tooltip: landscape
                                      ? context.zh('跟随设备方向', '跟隨裝置方向')
                                      : context.zh('横屏播放', '橫向播放'),
                                  onPressed: _toggleLandscape,
                                  icon: const Icon(
                                    Icons.screen_rotation_outlined,
                                  ),
                                ),
                              if (supportsPip)
                                IconButton.filledTonal(
                                  tooltip: context.zh('小窗播放', '小窗播放'),
                                  onPressed: () async {
                                    final w = player.state.width ?? 0,
                                        h = player.state.height ?? 0;
                                    final ok = await enterSmallWindow(
                                      w > 0 && h > 0 ? w / h : 1.0,
                                    );
                                    if (context.mounted && !ok) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            context.zh('系统未开启小窗', '系統未開啟小窗'),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt_rounded,
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Card.filled(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  16,
                                  6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${widget.drama.title} · ${episode.title}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                        ),
                                        if ((player.state.width ?? 0) > 0 &&
                                            (player.state.height ?? 0) > 0)
                                          Text(
                                            '${player.state.width}×${player.state.height}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        if (widget.drama.episodes.length > 1)
                                          IconButton(
                                            tooltip: context.zh('选集', '選集'),
                                            icon: const Icon(
                                              Icons.video_library_outlined,
                                            ),
                                            onPressed: opening || seeking
                                                ? null
                                                : _selectEpisode,
                                          ),
                                      ],
                                    ),
                                    controls,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectEpisode() async {
    final episodes = widget.drama.episodes;
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: episodes.length,
        itemBuilder: (context, i) => ListTile(
          selected: i == index,
          title: Text(episodes[i].title),
          onTap: () => Navigator.pop(context, i),
        ),
      ),
    );
    if (!closed && selected != null && selected != index) await _open(selected);
  }
}

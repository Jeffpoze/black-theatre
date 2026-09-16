import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'services/jellyfin_api_service.dart';

enum StreamQuality { original, high, medium, low }

extension on StreamQuality {
  int? get maxBitrateBps => switch (this) {
        StreamQuality.original => null,
        StreamQuality.high => 8000000,
        StreamQuality.medium => 4000000,
        StreamQuality.low => 1500000,
      };

  String get label => switch (this) {
        StreamQuality.original => 'Original',
        StreamQuality.high => 'High (8 Mbps)',
        StreamQuality.medium => 'Medium (4 Mbps)',
        StreamQuality.low => 'Low (1.5 Mbps)',
      };
}

const _playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.serverUrl,
    required this.userId,
    required this.token,
    required this.itemId,
    this.startPosition = Duration.zero,
    this.subtitle,
    this.onNext,
  });
  final String title;
  final String? subtitle;
  final String serverUrl;
  final String userId;
  final String token;
  final String itemId;
  final Duration startPosition;
  final VoidCallback? onNext;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _api = JellyfinApiService();
  late final Player _player;
  late final VideoController _controller;
  String? _error;
  List<dynamic> _jellyfinStreams = const [];
  StreamQuality _quality = StreamQuality.original;
  int? _subtitleStreamIndex;
  double _speed = 1.0;
  bool _locked = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  StreamSubscription<bool>? _completedSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((error) {
      if (mounted) setState(() => _error = error);
    });
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed && widget.onNext != null) widget.onNext!();
    });
    _loadStreamsAndPlay();
    _scheduleHide();
  }

  Future<void> _loadStreamsAndPlay() async {
    try {
      final streams = await _api.getMediaStreams(widget.serverUrl, widget.userId, widget.token, widget.itemId);
      if (mounted) setState(() => _jellyfinStreams = streams);
    } catch (_) {}
    _openStream(position: widget.startPosition);
  }

  void _openStream({required Duration position}) {
    final url = JellyfinApiService.getStreamUrl(
      widget.serverUrl,
      widget.itemId,
      widget.token,
      maxBitrateBps: _quality.maxBitrateBps,
      subtitleStreamIndex: _subtitleStreamIndex,
      subtitleMethod: _subtitleStreamIndex == null ? null : JellyfinApiService.subtitleMethodFor(_subtitleCodec(_subtitleStreamIndex!)),
    );
    _player.open(Media(url, httpHeaders: JellyfinApiService.authHeaders(widget.token), start: position));
    if (_speed != 1.0) _player.setRate(_speed);
  }

  String? _subtitleCodec(int index) {
    final match = _jellyfinStreams.whereType<Map<String, dynamic>>().where((s) => s['Index'] == index);
    return match.isEmpty ? null : match.first['Codec'] as String?;
  }

  List<Map<String, dynamic>> get _subtitleTracks => _jellyfinStreams.whereType<Map<String, dynamic>>().where((s) => s['Type'] == 'Subtitle').toList();

  List<Map<String, dynamic>> get _audioStreams => _jellyfinStreams.whereType<Map<String, dynamic>>().where((s) => s['Type'] == 'Audio').toList();

  String _audioLabel(int index) {
    final streams = _audioStreams;
    if (index < 0 || index >= streams.length) return 'Track ${index + 1}';
    final stream = streams[index];
    final languageName = _languageName(stream['Language'] as String?);
    if (languageName != null) return languageName;
    final displayTitle = stream['DisplayTitle'] as String?;
    if (displayTitle != null && displayTitle.isNotEmpty) return displayTitle;
    return 'Track ${index + 1}';
  }

  static const _languageNames = {
    'eng': 'English', 'en': 'English',
    'fre': 'French', 'fra': 'French', 'fr': 'French',
    'ger': 'German', 'deu': 'German', 'de': 'German',
    'spa': 'Spanish', 'es': 'Spanish',
    'ita': 'Italian', 'it': 'Italian',
    'jpn': 'Japanese', 'ja': 'Japanese',
    'kor': 'Korean', 'ko': 'Korean',
    'chi': 'Chinese', 'zho': 'Chinese', 'zh': 'Chinese',
    'por': 'Portuguese', 'pt': 'Portuguese',
    'rus': 'Russian', 'ru': 'Russian',
    'ara': 'Arabic', 'ar': 'Arabic',
    'hin': 'Hindi', 'hi': 'Hindi',
    'dut': 'Dutch', 'nld': 'Dutch', 'nl': 'Dutch',
    'swe': 'Swedish', 'sv': 'Swedish',
    'pol': 'Polish', 'pl': 'Polish',
    'tur': 'Turkish', 'tr': 'Turkish',
  };

  String? _languageName(String? code) {
    if (code == null || code.isEmpty) return null;
    return _languageNames[code.toLowerCase()] ?? code.toUpperCase();
  }

  void _toggleSubtitles() {
    final tracks = _subtitleTracks;
    if (tracks.isEmpty) return;
    final position = _player.state.position;
    setState(() => _subtitleStreamIndex = _subtitleStreamIndex == null ? tracks.first['Index'] as int? : null);
    _openStream(position: position);
    _scheduleHide();
  }

  void _cycleSpeed() {
    final index = _playbackSpeeds.indexOf(_speed);
    final next = _playbackSpeeds[(index + 1) % _playbackSpeeds.length];
    setState(() => _speed = next);
    _player.setRate(next);
    _scheduleHide();
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _controlsVisible = !_locked;
    });
    if (!_locked) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_locked) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _seekBy(Duration offset) {
    final position = _player.state.position + offset;
    final duration = _player.state.duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && position > duration ? duration : position);
    _player.seek(clamped);
    _scheduleHide();
  }

  Future<void> _openSettings() async {
    _hideTimer?.cancel();
    final position = _player.state.position;
    final audioTracks = _player.state.tracks.audio.where((t) => t.id != 'no').toList();
    final subtitleStreams = _subtitleTracks;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141518),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text('Video Quality', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final quality in StreamQuality.values)
              RadioListTile<StreamQuality>(
                value: quality,
                groupValue: _quality,
                title: Text(quality.label),
                onChanged: (value) {
                  if (value == null) return;
                  Navigator.of(context).pop();
                  setState(() => _quality = value);
                  _openStream(position: position);
                },
              ),
            if (audioTracks.length > 1) ...[
              const Divider(color: Color(0xFF1B1D22)),
              const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text('Audio', style: TextStyle(fontWeight: FontWeight.w700))),
              for (var i = 0; i < audioTracks.length; i++)
                RadioListTile<String>(
                  value: audioTracks[i].id,
                  groupValue: _player.state.track.audio.id,
                  title: Text(_audioLabel(i)),
                  onChanged: (value) {
                    Navigator.of(context).pop();
                    _player.setAudioTrack(audioTracks[i]);
                  },
                ),
            ],
            const Divider(color: Color(0xFF1B1D22)),
            const Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text('Subtitles', style: TextStyle(fontWeight: FontWeight.w700))),
            RadioListTile<int?>(
              value: null,
              groupValue: _subtitleStreamIndex,
              title: const Text('Off'),
              onChanged: (value) {
                Navigator.of(context).pop();
                setState(() => _subtitleStreamIndex = null);
                _openStream(position: position);
              },
            ),
            for (final stream in subtitleStreams)
              RadioListTile<int?>(
                value: stream['Index'] as int?,
                groupValue: _subtitleStreamIndex,
                title: Text((stream['DisplayTitle'] as String?) ?? (stream['Language'] as String?) ?? 'Track ${stream['Index']}'),
                onChanged: (value) {
                  Navigator.of(context).pop();
                  setState(() => _subtitleStreamIndex = value);
                  _openStream(position: position);
                },
              ),
          ],
        ),
      ),
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Unable to play this video.\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA5A7AC))),
                ),
              )
            : GestureDetector(
                onTap: _toggleControls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(controller: _controller, controls: NoVideoControls),
                    if (_controlsVisible && !_locked)
                      DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .6), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: .75)])),
                      ),
                    if (_controlsVisible && !_locked)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _TopBar(onBack: () => Navigator.of(context).pop(), onSettings: _openSettings, onToggleSubtitles: _subtitleTracks.isEmpty ? null : _toggleSubtitles, subtitlesOn: _subtitleStreamIndex != null),
                      ),
                    if (_controlsVisible && !_locked)
                      _CenterControls(player: _player, onSeekBack: () => _seekBy(const Duration(seconds: -15)), onSeekForward: () => _seekBy(const Duration(seconds: 15))),
                    if (_controlsVisible && !_locked)
                      _BottomBar(player: _player, title: widget.title, subtitle: widget.subtitle, speed: _speed, onCycleSpeed: _cycleSpeed, onLock: _toggleLock, onNext: widget.onNext),
                    if (_locked)
                      Positioned(
                        left: 16,
                        bottom: 16,
                        child: SafeArea(
                          child: IconButton(
                            onPressed: _toggleLock,
                            icon: const Icon(Icons.lock_outline, color: Colors.white70),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.onSettings, required this.onToggleSubtitles, required this.subtitlesOn});
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback? onToggleSubtitles;
  final bool subtitlesOn;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back, color: Colors.white)),
            const Spacer(),
            if (onToggleSubtitles != null)
              IconButton(onPressed: onToggleSubtitles, icon: Icon(subtitlesOn ? Icons.closed_caption : Icons.closed_caption_off_outlined, color: Colors.white)),
            IconButton(onPressed: onSettings, icon: const Icon(Icons.settings_outlined, color: Colors.white)),
          ]),
        ),
      );
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.player, required this.onSeekBack, required this.onSeekForward});
  final Player player;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) => Center(
        child: StreamBuilder<bool>(
          stream: player.stream.playing,
          initialData: player.state.playing,
          builder: (context, snapshot) {
            final playing = snapshot.data ?? false;
            return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(iconSize: 40, onPressed: onSeekBack, icon: const _SeekIcon(forward: false)),
              const SizedBox(width: 24),
              IconButton(
                iconSize: 64,
                onPressed: player.playOrPause,
                icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              ),
              const SizedBox(width: 24),
              IconButton(iconSize: 40, onPressed: onSeekForward, icon: const _SeekIcon(forward: true)),
            ]);
          },
        ),
      );
}

class _SeekIcon extends StatelessWidget {
  const _SeekIcon({required this.forward});
  final bool forward;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(flipX: forward, child: const Icon(Icons.replay, color: Colors.white, size: 40)),
          const Padding(padding: EdgeInsets.only(top: 2), child: Text('15', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ],
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.player, required this.title, required this.subtitle, required this.speed, required this.onCycleSpeed, required this.onLock, required this.onNext});
  final Player player;
  final String title;
  final String? subtitle;
  final double speed;
  final VoidCallback onCycleSpeed;
  final VoidCallback onLock;
  final VoidCallback? onNext;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _speedLabel(double value) => value == value.roundToDouble() ? '${value.toInt()}x' : '${value}x';

  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) Text(subtitle!, style: const TextStyle(color: Color(0xFFCBCCD0), fontSize: 13)),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: player.state.position,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: player.stream.duration,
                      initialData: player.state.duration,
                      builder: (context, durationSnapshot) {
                        final duration = durationSnapshot.data ?? Duration.zero;
                        final maxMs = duration.inMilliseconds.toDouble();
                        final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
                        final remaining = duration > position ? duration - position : Duration.zero;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: SliderComponentShape.noOverlay),
                              child: Slider(
                                value: valueMs,
                                max: maxMs <= 0 ? 1 : maxMs,
                                onChanged: maxMs <= 0 ? null : (value) => player.seek(Duration(milliseconds: value.round())),
                              ),
                            ),
                            Row(children: [
                              Text(_format(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              const Spacer(),
                              Text('-${_format(remaining)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ]),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(onPressed: onLock, icon: const Icon(Icons.lock_open, color: Colors.white70)),
                  TextButton(
                    onPressed: onCycleSpeed,
                    child: Text(_speedLabel(speed), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                  ),
                  if (onNext != null) IconButton(onPressed: onNext, icon: const Icon(Icons.skip_next, color: Colors.white70)),
                ]),
              ],
            ),
          ),
        ),
      );
}

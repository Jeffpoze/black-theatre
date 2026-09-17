import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:better_native_video_player/cast.dart' as nvp_cast;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/jellyfin_api_service.dart';
import 'settings_controller.dart';

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

// Platform view ids must be unique per screen instance; a plain incrementing
// counter is simpler than deriving one from the item id (which can repeat
// across a list -> detail -> player navigation stack).
int _nextControllerId = 1;

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
    this.isAudioOnly = false,
    required this.settings,
  });
  final String title;
  final String? subtitle;
  final String serverUrl;
  final String userId;
  final String token;
  final String itemId;
  final Duration startPosition;
  final VoidCallback? onNext;
  final bool isAudioOnly;
  final SettingsController settings;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _api = JellyfinApiService();
  late final NativeVideoPlayerController _controller;
  String? _error;
  List<dynamic> _jellyfinStreams = const [];
  late StreamQuality _quality = switch (widget.settings.defaultQuality) {
    'high' => StreamQuality.high,
    'medium' => StreamQuality.medium,
    'low' => StreamQuality.low,
    _ => StreamQuality.original,
  };
  int? _subtitleStreamIndex;
  final double _speed = 1.0;
  bool _locked = false;
  Duration _lastKnownPosition = Duration.zero;
  String _playSessionId = '${DateTime.now().microsecondsSinceEpoch}';
  Timer? _progressTimer;
  bool _hasOpenedStreamBefore = false;
  String? _currentStreamUrl;
  String? _lastManifestCheck;

  bool _isAirplayAvailable = false;
  bool _isAirplayConnected = false;

  nvp_cast.CastSession? _castSession;
  nvp_cast.CastDevice? _castDevice;
  StreamSubscription<nvp_cast.CastSessionStatus>? _castStatusSub;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _controller = NativeVideoPlayerController(
      id: _nextControllerId++,
      autoPlay: true,
      showNativeControls: false,
      allowsPictureInPicture: true,
      canStartPictureInPictureAutomatically: true,
      mediaInfo: NativeVideoPlayerMediaInfo(title: widget.title, subtitle: widget.subtitle),
    );
    _controller.addActivityListener(_handleActivityEvent);
    _controller.addAirPlayAvailabilityListener(_handleAirPlayAvailability);
    _controller.addAirPlayConnectionListener(_handleAirPlayConnection);
    if (!widget.isAudioOnly) {
      // Jellyfin's transcode has its own idle "kill timer" that tears down
      // the ffmpeg process if it stops hearing from the client — server logs
      // showed exactly this happening mid-playback, since we never sent any
      // keep-alive. Ping roughly every 10s while a stream is open.
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_error == null) {
          final position = _castSession?.status.position ?? _controller.currentPosition;
          final paused = _castSession != null ? !_castSession!.status.isPlaying : !_controller.activityState.isPlaying;
          _api.reportPlaybackProgress(widget.serverUrl, widget.token, widget.itemId, _playSessionId, position, isPaused: paused);
        }
      });
    }
    _initializeAndPlay();
  }

  Future<void> _initializeAndPlay() async {
    try {
      await _controller.initialize();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to start the player.\n$e');
      return;
    }
    if (!widget.isAudioOnly) {
      try {
        final streams = await _api.getMediaStreams(widget.serverUrl, widget.userId, widget.token, widget.itemId);
        if (mounted) setState(() => _jellyfinStreams = streams);
      } catch (_) {}
    }
    _openStream(position: widget.startPosition);
  }

  Future<void> _openStream({required Duration position}) async {
    // Reopening (quality/subtitle change, or Retry) without telling Jellyfin
    // the previous session ended can leave its transcode job running
    // alongside the new one — two ffmpeg jobs competing for the same CPU is
    // exactly the kind of contention that starves both and shows up as a
    // fatal read timeout on either.
    if (_hasOpenedStreamBefore && !widget.isAudioOnly) {
      _api.reportPlaybackStopped(widget.serverUrl, widget.token, widget.itemId, _playSessionId, _controller.currentPosition);
    }
    _hasOpenedStreamBefore = true;
    if (widget.isAudioOnly) {
      final url = JellyfinApiService.getAudioStreamUrl(widget.serverUrl, widget.itemId, widget.userId, widget.token, maxBitrateBps: _quality.maxBitrateBps);
      _currentStreamUrl = url;
      await _controller.load(url: url, headers: JellyfinApiService.authHeaders(widget.token), startAt: position, force: true);
      if (_speed != 1.0) await _controller.setSpeed(_speed);
      return;
    }

    // Only the plain "Original, no forced subtitle" case is eligible for
    // direct-play negotiation. Quality caps and burned-in subtitles keep
    // using the known-working forced-transcode request.
    if (_quality == StreamQuality.original && _subtitleStreamIndex == null) {
      try {
        final playbackInfo = await _api.getPlaybackInfo(widget.serverUrl, widget.userId, widget.token, widget.itemId);
        final result = JellyfinApiService.buildUrlFromPlaybackInfo(widget.serverUrl, widget.itemId, widget.token, playbackInfo);
        if (result != null) {
          final (url, playSessionId) = result;
          _playSessionId = playSessionId;
          _currentStreamUrl = url;
          _lastManifestCheck = await _api.debugCheckManifest(url, widget.token);
          await _controller.load(url: url, headers: JellyfinApiService.authHeaders(widget.token), startAt: position, force: true);
          if (_speed != 1.0) await _controller.setSpeed(_speed);
          _api.reportPlaybackStart(widget.serverUrl, widget.token, widget.itemId, _playSessionId);
          return;
        }
      } catch (e) {
        print('getPlaybackInfo negotiation failed for ${widget.itemId}, falling back to forced transcode: $e');
      }
    }

    final url = JellyfinApiService.getStreamUrl(
      widget.serverUrl,
      widget.itemId,
      widget.token,
      maxBitrateBps: _quality.maxBitrateBps,
      subtitleStreamIndex: _subtitleStreamIndex,
      subtitleMethod: _subtitleStreamIndex == null ? null : JellyfinApiService.subtitleMethodFor(_subtitleCodec(_subtitleStreamIndex!)),
      playSessionId: _playSessionId,
    );
    _currentStreamUrl = url;
    _lastManifestCheck = await _api.debugCheckManifest(url, widget.token);
    await _controller.load(url: url, headers: JellyfinApiService.authHeaders(widget.token), startAt: position, force: true);
    if (_speed != 1.0) await _controller.setSpeed(_speed);
    _api.reportPlaybackStart(widget.serverUrl, widget.token, widget.itemId, _playSessionId);
  }

  void _handleActivityEvent(PlayerActivityEvent event) {
    switch (event.state) {
      case PlayerActivityState.error:
        _lastKnownPosition = _controller.currentPosition;
        final nativeMessage = (event.data?['message'] as String?) ?? 'Unable to play this video.';
        // TEMPORARY diagnostic: shows what the manifest URL actually
        // returned when fetched directly, to tell apart an HTTP/auth
        // failure on our side from AVFoundation's generic "Cannot Open"
        // bucket rejecting a response that was actually fine.
        final diagnostic = _lastManifestCheck;
        if (mounted) setState(() => _error = diagnostic == null ? nativeMessage : '$nativeMessage\n\nManifest check: $diagnostic');
        break;
      case PlayerActivityState.completed:
        if (widget.onNext != null) widget.onNext!();
        break;
      default:
        break;
    }
  }

  void _handleAirPlayAvailability(bool available) {
    if (mounted) setState(() => _isAirplayAvailable = available);
  }

  void _handleAirPlayConnection(bool connected) {
    if (mounted) setState(() => _isAirplayConnected = connected);
  }

  String? _subtitleCodec(int index) {
    final match = _jellyfinStreams.whereType<Map<String, dynamic>>().where((s) => s['Index'] == index);
    return match.isEmpty ? null : match.first['Codec'] as String?;
  }

  List<Map<String, dynamic>> get _subtitleTracks => _jellyfinStreams.whereType<Map<String, dynamic>>().where((s) => s['Type'] == 'Subtitle').toList();

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

  String _audioTrackLabel(NativeVideoPlayerAudioTrack track) {
    final languageName = _languageName(track.language);
    if (languageName != null) return languageName;
    return track.displayName.isNotEmpty ? track.displayName : 'Audio';
  }

  Future<void> _toggleSubtitles() async {
    final tracks = _subtitleTracks;
    if (tracks.isEmpty) return;
    final position = _controller.currentPosition;
    setState(() => _subtitleStreamIndex = _subtitleStreamIndex == null ? tracks.first['Index'] as int? : null);
    await _openStream(position: position);
  }

  Future<void> _togglePlayPause() async {
    if (_controller.activityState.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
  }

  void _seekBy(Duration offset) {
    final position = _controller.currentPosition + offset;
    final duration = _controller.duration;
    final clamped = position < Duration.zero ? Duration.zero : (duration > Duration.zero && position > duration ? duration : position);
    _controller.seekTo(clamped);
  }

  Future<void> _retry() async {
    setState(() => _error = null);
    await _openStream(position: _lastKnownPosition);
  }

  Future<void> _openSettings() async {
    final position = _controller.currentPosition;
    final audioTracks = await _controller.getAvailableAudioTracks();
    final subtitleStreams = _subtitleTracks;
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _PlayerSettingsSheet(
        quality: _quality,
        subtitleLabel: _subtitleLabel(),
        audioLabel: audioTracks.isEmpty ? 'Default' : _audioTrackLabel(audioTracks.firstWhere((t) => t.isSelected, orElse: () => audioTracks.first)),
        hasSubtitles: subtitleStreams.isNotEmpty,
        hasAudioChoices: audioTracks.length > 1,
        onQuality: () => _chooseQuality(sheetContext, position),
        onSubtitles: () => _chooseSubtitles(sheetContext, position, subtitleStreams),
        onAudio: () => _chooseAudio(sheetContext, audioTracks),
      ),
    );
  }

  String _subtitleLabel() {
    if (_subtitleStreamIndex == null) return 'Off';
    final stream = _subtitleTracks.cast<Map<String, dynamic>>().where((s) => s['Index'] == _subtitleStreamIndex).firstOrNull;
    if (stream == null) return 'On';
    final language = _languageName(stream['Language'] as String?) ?? 'Unknown';
    final codec = (stream['Codec'] as String?)?.toUpperCase();
    return codec == null || codec.isEmpty ? language : '$language ($codec)';
  }

  Future<void> _chooseQuality(BuildContext sheetContext, Duration position) async {
    final selected = await _showChoiceSheet<StreamQuality>(
      sheetContext,
      title: 'Quality',
      value: _quality,
      options: StreamQuality.values.map((quality) => _ChoiceOption(quality, quality.label)).toList(),
    );
    if (selected == null || !mounted) return;
    setState(() => _quality = selected);
    await _openStream(position: position);
  }

  Future<void> _chooseSubtitles(BuildContext sheetContext, Duration position, List<Map<String, dynamic>> streams) async {
    final options = <_ChoiceOption<int?>>[_ChoiceOption(null, 'Off')];
    for (final stream in streams) {
      final language = _languageName(stream['Language'] as String?) ?? 'Unknown';
      final codec = (stream['Codec'] as String?)?.toUpperCase();
      options.add(_ChoiceOption(stream['Index'] as int?, codec == null ? language : '$language ($codec)'));
    }
    final selected = await _showChoiceSheet<int?>(sheetContext, title: 'Subtitles', value: _subtitleStreamIndex, options: options);
    if (!mounted) return;
    setState(() => _subtitleStreamIndex = selected);
    await _openStream(position: position);
  }

  Future<void> _chooseAudio(BuildContext sheetContext, List<NativeVideoPlayerAudioTrack> tracks) async {
    final selectedIndex = await _showChoiceSheet<int>(
      sheetContext,
      title: 'Audio',
      value: tracks.indexWhere((t) => t.isSelected),
      options: [for (var i = 0; i < tracks.length; i++) _ChoiceOption(i, _audioTrackLabel(tracks[i]))],
    );
    if (selectedIndex == null || selectedIndex < 0 || !mounted) return;
    await _controller.setAudioTrack(tracks[selectedIndex]);
  }

  Future<T?> _showChoiceSheet<T>(BuildContext context, {required String title, required T value, required List<_ChoiceOption<T>> options}) => showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => _ChoiceSheet<T>(title: title, value: value, options: options),
  );

  Future<void> _showCastPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101114),
      isScrollControlled: true,
      builder: (sheetContext) => _CastPickerSheet(onSelected: (device) {
        Navigator.of(sheetContext).pop();
        _connectCast(device);
      }),
    );
  }

  Future<void> _connectCast(nvp_cast.CastDevice device) async {
    final url = _currentStreamUrl;
    if (url == null) return;
    try {
      final session = await nvp_cast.CastSession.connect(device);
      await session.loadMedia(
        contentUrl: url,
        contentType: 'application/x-mpegURL',
        title: widget.title,
        subtitle: widget.subtitle,
        startAt: _controller.currentPosition,
      );
      await _controller.pause();
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _castSession = session;
        _castDevice = device;
      });
      _castStatusSub = session.statusStream.listen((_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cast to ${device.displayName}: $e')));
      }
    }
  }

  Future<void> _disconnectCast() async {
    final session = _castSession;
    _castStatusSub?.cancel();
    _castStatusSub = null;
    setState(() {
      _castSession = null;
      _castDevice = null;
    });
    await session?.close();
    await _controller.play();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _controller.removeActivityListener(_handleActivityEvent);
    _controller.removeAirPlayAvailabilityListener(_handleAirPlayAvailability);
    _controller.removeAirPlayConnectionListener(_handleAirPlayConnection);
    _castStatusSub?.cancel();
    _castSession?.close();
    if (!widget.isAudioOnly) {
      final position = _castSession?.status.position ?? _controller.currentPosition;
      _api.reportPlaybackStopped(widget.serverUrl, widget.token, widget.itemId, _playSessionId, position);
    }
    _controller.dispose();
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Unable to play this video.\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA5A7AC))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _retry, child: const Text('Retry')),
              ]),
            ),
          )
        : _castSession != null
            ? _CastingView(device: _castDevice!, session: _castSession!, title: widget.title, subtitle: widget.subtitle, onStop: _disconnectCast)
            : NativeVideoPlayer(
                controller: _controller,
                overlayBuilder: (overlayContext, controller) => _locked
                    ? Positioned(
                        left: 16,
                        bottom: 16,
                        child: SafeArea(
                          child: IconButton(
                            onPressed: _toggleLock,
                            icon: const Icon(Icons.lock_outline, color: Colors.white70),
                            style: IconButton.styleFrom(backgroundColor: Colors.black45),
                          ),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black.withValues(alpha: .6), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: .75)],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _TopBar(
                              title: widget.title,
                              subtitle: widget.subtitle,
                              onBack: () => Navigator.of(context).pop(),
                              onLock: _toggleLock,
                              isAirplayAvailable: _isAirplayAvailable,
                              isAirplayConnected: _isAirplayConnected,
                              onAirPlay: () => _controller.showAirPlayPicker(),
                              onCast: _showCastPicker,
                            ),
                          ),
                          _CenterControls(
                            controller: _controller,
                            skipSeconds: widget.settings.skipSeconds,
                            onSeekBack: () => _seekBy(Duration(seconds: -widget.settings.skipSeconds)),
                            onSeekForward: () => _seekBy(Duration(seconds: widget.settings.skipSeconds)),
                            onPrevious: () => _seekBy(const Duration(seconds: -10)),
                            onNext: widget.onNext,
                            onPlayPause: _togglePlayPause,
                          ),
                          _BottomBar(
                            controller: _controller,
                            onSettings: _openSettings,
                            onToggleSubtitles: _subtitleTracks.isEmpty ? null : _toggleSubtitles,
                            subtitlesOn: _subtitleStreamIndex != null,
                          ),
                        ],
                      ),
              ),
  );
}

class _PlayerSettingsSheet extends StatelessWidget {
  const _PlayerSettingsSheet({
    required this.quality,
    required this.subtitleLabel,
    required this.audioLabel,
    required this.hasSubtitles,
    required this.hasAudioChoices,
    required this.onQuality,
    required this.onSubtitles,
    required this.onAudio,
  });
  final StreamQuality quality;
  final String subtitleLabel;
  final String audioLabel;
  final bool hasSubtitles;
  final bool hasAudioChoices;
  final VoidCallback onQuality;
  final VoidCallback onSubtitles;
  final VoidCallback onAudio;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 66),
      padding: const EdgeInsets.fromLTRB(34, 12, 34, 34),
      decoration: const BoxDecoration(color: Colors.black, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFF29292C), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 28),
          const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 26),
          const Divider(color: Color(0xFF252529), height: 1),
          _SettingsRow(label: 'Quality', value: quality == StreamQuality.original ? 'Original' : quality.label, onTap: onQuality),
          _SettingsRow(label: 'Subtitles', value: subtitleLabel, onTap: hasSubtitles ? onSubtitles : null),
          _SettingsRow(label: 'Audio', value: audioLabel, onTap: hasAudioChoices ? onAudio : null),
          const _SettingsRow(label: 'Playback Options', value: '', onTap: null),
        ],
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 25),
      child: Row(children: [
        Text(label, style: TextStyle(color: onTap == null ? const Color(0xFF808084) : Colors.white, fontSize: 20)),
        const Spacer(),
        if (value.isNotEmpty) Text(value, style: const TextStyle(color: Color(0xFFA9A8AD), fontSize: 20)),
        if (onTap != null) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.chevron_right, color: Color(0xFFA9A8AD))),
      ]),
    ),
  );
}

class _ChoiceOption<T> {
  const _ChoiceOption(this.value, this.label);
  final T value;
  final String label;
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.value, required this.options});
  final String title;
  final T value;
  final List<_ChoiceOption<T>> options;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 66),
      padding: const EdgeInsets.fromLTRB(34, 12, 34, 28),
      decoration: const BoxDecoration(color: Color(0xFF101114), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFF29292C), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final option in options)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(option.label, style: const TextStyle(color: Colors.white, fontSize: 18)),
              trailing: option.value == value ? const Icon(Icons.check, color: Color(0xFFFFB800)) : null,
              onTap: () => Navigator.of(context).pop(option.value),
            ),
        ],
      ),
    ),
  );
}

class _CastPickerSheet extends StatefulWidget {
  const _CastPickerSheet({required this.onSelected});
  final void Function(nvp_cast.CastDevice device) onSelected;

  @override
  State<_CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends State<_CastPickerSheet> {
  List<nvp_cast.CastDevice>? _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  Future<void> _discover() async {
    try {
      final devices = await nvp_cast.CastDeviceDiscovery.discover();
      if (mounted) setState(() => _devices = devices);
    } on nvp_cast.CastDiscoveryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not search for Cast devices: $e');
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      decoration: const BoxDecoration(color: Color(0xFF101114), borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFF29292C), borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 24),
          const Text('Cast to Device', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(_error!, style: const TextStyle(color: Color(0xFFA5A7AC)), textAlign: TextAlign.center))
          else if (_devices == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator())
          else if (_devices!.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No Cast devices found on your network.', style: TextStyle(color: Color(0xFFA5A7AC))))
          else
            for (final device in _devices!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cast, color: Colors.white),
                title: Text(device.displayName, style: const TextStyle(color: Colors.white, fontSize: 17)),
                subtitle: device.model != null ? Text(device.model!, style: const TextStyle(color: Color(0xFFA9A8AD))) : null,
                onTap: () => widget.onSelected(device),
              ),
        ],
      ),
    ),
  );
}

class _CastingView extends StatelessWidget {
  const _CastingView({required this.device, required this.session, required this.title, required this.subtitle, required this.onStop});
  final nvp_cast.CastDevice device;
  final nvp_cast.CastSession session;
  final String title;
  final String? subtitle;
  final VoidCallback onStop;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cast_connected, color: Color(0xFFFFB800), size: 64),
          const SizedBox(height: 20),
          Text('Casting to ${device.displayName}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Color(0xFFAAA9AE), fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 32),
          StreamBuilder<nvp_cast.CastSessionStatus>(
            stream: session.statusStream,
            initialData: session.status,
            builder: (context, snapshot) {
              final status = snapshot.data ?? session.status;
              final duration = status.duration ?? Duration.zero;
              final maxMs = duration.inMilliseconds.toDouble();
              final valueMs = status.position.inMilliseconds.toDouble().clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
              return Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                      iconSize: 56,
                      onPressed: status.isPlaying ? session.pause : session.play,
                      icon: Icon(status.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                    ),
                  ]),
                  Slider(
                    value: valueMs,
                    max: maxMs <= 0 ? 1 : maxMs,
                    onChanged: maxMs <= 0 ? null : (value) => session.seek(Duration(milliseconds: value.round())),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_format(status.position), style: const TextStyle(color: Colors.white70)),
                    Text(_format(duration), style: const TextStyle(color: Colors.white70)),
                  ]),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: onStop, child: const Text('Stop Casting')),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onLock,
    required this.isAirplayAvailable,
    required this.isAirplayConnected,
    required this.onAirPlay,
    required this.onCast,
  });
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onLock;
  final bool isAirplayAvailable;
  final bool isAirplayConnected;
  final VoidCallback onAirPlay;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(54, 26, 42, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFAAA9AE), fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          IconButton(onPressed: onLock, icon: const Icon(Icons.lock_open, color: Color(0xFFD3D2D6), size: 26)),
          IconButton(
            onPressed: isAirplayAvailable ? onAirPlay : null,
            icon: Icon(Icons.airplay, color: isAirplayConnected ? const Color(0xFFFFB800) : (isAirplayAvailable ? const Color(0xFFD3D2D6) : const Color(0xFF5A5A5E)), size: 31),
          ),
          IconButton(onPressed: onCast, icon: const Icon(Icons.cast_outlined, color: Color(0xFFD3D2D6), size: 31)),
          IconButton(onPressed: onBack, icon: const Icon(Icons.close, color: Color(0xFFD3D2D6), size: 36)),
        ],
      ),
    ),
  );
}

class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.controller,
    required this.skipSeconds,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
  });
  final NativeVideoPlayerController controller;
  final int skipSeconds;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) => Center(
    child: StreamBuilder<PlayerActivityState>(
      stream: controller.playerStateStream,
      initialData: controller.activityState,
      builder: (context, snapshot) {
        final playing = (snapshot.data ?? PlayerActivityState.idle).isPlaying;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(iconSize: 42, onPressed: onPrevious, icon: const Icon(Icons.skip_previous, color: Color(0xFFC9C8CD))),
            const SizedBox(width: 66),
            IconButton(
              iconSize: 68,
              onPressed: onPlayPause,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
            ),
            const SizedBox(width: 66),
            IconButton(iconSize: 42, onPressed: onNext ?? onSeekForward, icon: const Icon(Icons.skip_next, color: Colors.white)),
          ],
        );
      },
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller, required this.onSettings, required this.onToggleSubtitles, required this.subtitlesOn});
  final NativeVideoPlayerController controller;
  final VoidCallback onSettings;
  final VoidCallback? onToggleSubtitles;
  final bool subtitlesOn;

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(54, 8, 54, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onToggleSubtitles != null)
                  IconButton(
                    onPressed: onToggleSubtitles,
                    icon: Icon(subtitlesOn ? Icons.closed_caption : Icons.closed_caption_outlined, color: const Color(0xFFD3D2D6), size: 31),
                  ),
                const SizedBox(width: 18),
                IconButton(onPressed: onSettings, icon: const Icon(Icons.settings, color: Color(0xFFD3D2D6), size: 34)),
              ],
            ),
            StreamBuilder<Duration>(
              stream: controller.positionStream,
              initialData: controller.currentPosition,
              builder: (context, positionSnapshot) {
                final position = positionSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: controller.durationStream,
                  initialData: controller.duration,
                  builder: (context, durationSnapshot) {
                    final duration = durationSnapshot.data ?? Duration.zero;
                    final maxMs = duration.inMilliseconds.toDouble();
                    final valueMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);
                    final remaining = duration > position ? duration - position : Duration.zero;
                    return Row(
                      children: [
                        SizedBox(width: 76, child: Text(_format(position), style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.left)),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: const Color(0xFFFFB800),
                              inactiveTrackColor: const Color(0xFF5D5D60),
                              trackHeight: 8,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: valueMs,
                              max: maxMs <= 0 ? 1 : maxMs,
                              onChanged: maxMs <= 0 ? null : (value) => controller.seekTo(Duration(milliseconds: value.round())),
                            ),
                          ),
                        ),
                        SizedBox(width: 86, child: Text('-${_format(remaining)}', style: const TextStyle(color: Colors.white, fontSize: 18), textAlign: TextAlign.right)),
                      ],
                    );
                  },
                );
              },
            ),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFFD3D2D6), size: 28),
          ],
        ),
      ),
    ),
  );
}

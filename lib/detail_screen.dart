import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import 'player_screen.dart';
import 'services/jellyfin_api_service.dart';
import 'settings_controller.dart';

// `dynamic as Type?` throws if the value is non-null but the wrong type —
// it does not return null. These treat an unexpected type as absent instead
// of crashing the whole page over a single malformed/unusual field.
String? _asString(dynamic value) => value is String ? value : null;
int? _asInt(dynamic value) => value is num ? value.toInt() : null;
num? _asNum(dynamic value) => value is num ? value : null;

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.serverUrl, required this.userId, required this.token, required this.itemId, required this.settings});
  final String serverUrl;
  final String userId;
  final String token;
  final String itemId;
  final SettingsController settings;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _api = JellyfinApiService();
  Map<String, dynamic>? _item;
  List<dynamic> _seasons = const [];
  Map<String, dynamic>? _nextUp;
  String? _selectedSeasonId;
  List<dynamic> _seasonEpisodes = const [];
  bool _isLoadingEpisodes = false;
  List<dynamic> _tracks = const [];
  List<dynamic> _techStreams = const [];
  bool _isLoading = true;
  String? _error;
  bool _favoriteBusy = false;
  bool _watchedBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final item = await _api.getItemDetail(widget.serverUrl, widget.userId, widget.token, widget.itemId);
      List<dynamic> seasons = const [];
      Map<String, dynamic>? nextUp;
      List<dynamic> tracks = const [];
      if (item['Type'] == 'Series') {
        final results = await Future.wait([
          _api.getSeasons(widget.serverUrl, widget.userId, widget.token, widget.itemId),
          _api.getNextUp(widget.serverUrl, widget.userId, widget.token, widget.itemId),
        ]);
        seasons = results[0] as List<dynamic>;
        nextUp = results[1] as Map<String, dynamic>?;
      } else if (item['IsFolder'] == true) {
        // A playable folder that isn't a Series (music album, audiobook
        // folder, playlist, box set): its children are what's actually
        // playable, not the folder itself.
        tracks = await _api.getChildItems(widget.serverUrl, widget.userId, widget.token, widget.itemId);
      }
      if (!mounted) return;
      setState(() {
        _item = item;
        _seasons = seasons;
        _nextUp = nextUp;
        _tracks = tracks;
        _isLoading = false;
      });
      final defaultSeasonId = (nextUp?['SeasonId'] as String?) ?? seasons.whereType<Map<String, dynamic>>().firstOrNull?['Id'] as String?;
      if (defaultSeasonId != null) _selectSeason(defaultSeasonId);
      // Only leaf playable items have their own media file to describe. For
      // a series, describe whichever episode "Play" would actually start.
      final techItemId = item['Type'] == 'Series' ? (nextUp?['Id'] as String?) : (item['IsFolder'] == true ? null : widget.itemId);
      if (techItemId != null) {
        _api.getMediaStreams(widget.serverUrl, widget.userId, widget.token, techItemId).then((streams) {
          if (mounted) setState(() => _techStreams = streams);
        }).catchError((_) {});
      }
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _error = 'Unable to load details.'; });
    }
  }

  Future<void> _selectSeason(String seasonId) async {
    setState(() { _selectedSeasonId = seasonId; _isLoadingEpisodes = true; });
    try {
      final episodes = await _api.getEpisodes(widget.serverUrl, widget.userId, widget.token, widget.itemId, seasonId: seasonId);
      if (!mounted || _selectedSeasonId != seasonId) return;
      setState(() { _seasonEpisodes = episodes; _isLoadingEpisodes = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoadingEpisodes = false);
    }
  }

  bool get _isFavorite => (_item?['UserData'] as Map<String, dynamic>?)?['IsFavorite'] == true;
  bool get _isWatched => (_item?['UserData'] as Map<String, dynamic>?)?['Played'] == true;

  Future<void> _toggleFavorite() async {
    final item = _item;
    if (item == null || _favoriteBusy) return;
    final next = !_isFavorite;
    setState(() => _favoriteBusy = true);
    try {
      await _api.setFavorite(widget.serverUrl, widget.userId, widget.token, widget.itemId, next);
      if (!mounted) return;
      setState(() => (item['UserData'] as Map<String, dynamic>)['IsFavorite'] = next);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _toggleWatched() async {
    final item = _item;
    if (item == null || _watchedBusy) return;
    final next = !_isWatched;
    setState(() => _watchedBusy = true);
    try {
      await _api.setWatched(widget.serverUrl, widget.userId, widget.token, widget.itemId, next);
      if (!mounted) return;
      setState(() => (item['UserData'] as Map<String, dynamic>)['Played'] = next);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _watchedBusy = false);
    }
  }

  void _play(String itemId, String title, {String? subtitle, Duration startPosition = Duration.zero, VoidCallback? onNext, bool replace = false, bool isAudioOnly = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(title: title, subtitle: subtitle, serverUrl: widget.serverUrl, userId: widget.userId, token: widget.token, itemId: itemId, startPosition: startPosition, onNext: onNext, isAudioOnly: isAudioOnly, settings: widget.settings),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  void _playEpisode(Map<String, dynamic> episode, {bool replace = false}) {
    final itemId = episode['Id'] as String?;
    if (itemId == null) return;
    final seriesName = _item?['Name'] as String? ?? '';
    final season = episode['ParentIndexNumber'];
    final epNum = episode['IndexNumber'];
    final epName = (episode['Name'] as String?) ?? 'Episode';
    final subtitle = season != null && epNum != null ? 'S$season:E$epNum - $epName' : epName;
    final ticks = (episode['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'];
    final episodes = _seasonEpisodes.whereType<Map<String, dynamic>>().toList();
    final index = episodes.indexWhere((e) => e['Id'] == itemId);
    final next = index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
    _play(itemId, seriesName, subtitle: subtitle, startPosition: ticksToDuration(ticks), replace: replace, onNext: next == null ? null : () => _playEpisode(next, replace: true));
  }

  void _playTrack(Map<String, dynamic> track) {
    final itemId = track['Id'] as String?;
    if (itemId == null) return;
    final title = (track['Name'] as String?) ?? 'Track';
    final ticks = (track['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'];
    final isAudioOnly = track['Type'] == 'Audio' || track['Type'] == 'AudioBook';
    _play(itemId, title, startPosition: ticksToDuration(ticks), isAudioOnly: isAudioOnly);
  }

  Map<String, dynamic>? get _firstPlayableTrack {
    final tracks = _tracks.whereType<Map<String, dynamic>>().toList();
    return tracks.firstWhereOrNull((t) => (t['UserData'] as Map<String, dynamic>?)?['Played'] != true) ?? tracks.firstOrNull;
  }

  void _playMain() {
    final item = _item;
    if (item == null) return;
    final name = item['Name'] as String? ?? 'Untitled';
    if (item['Type'] == 'Series') {
      final nextUp = _nextUp;
      if (nextUp != null) {
        _playEpisode(nextUp);
        return;
      }
      final firstEpisode = _seasonEpisodes.whereType<Map<String, dynamic>>().firstOrNull;
      if (firstEpisode != null) _playEpisode(firstEpisode);
      return;
    }
    if (item['IsFolder'] == true) {
      final track = _firstPlayableTrack;
      if (track != null) _playTrack(track);
      return;
    }
    final ticks = (item['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'];
    final isAudioOnly = item['Type'] == 'Audio' || item['Type'] == 'AudioBook';
    _play(widget.itemId, name, startPosition: ticksToDuration(ticks), isAudioOnly: isAudioOnly);
  }

  bool get _hasResumablePlay {
    final item = _item;
    if (item == null) return false;
    if (item['Type'] == 'Series') return _nextUp != null && ((_nextUp!['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'] ?? 0) > 0;
    if (item['IsFolder'] == true) return ((_firstPlayableTrack?['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'] ?? 0) > 0;
    return ((item['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'] ?? 0) > 0;
  }

  Future<void> _openSeasonPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141518),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text('Seasons', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final season in _seasons.whereType<Map<String, dynamic>>())
              ListTile(
                title: Text((season['Name'] as String?) ?? 'Season'),
                trailing: season['Id'] == _selectedSeasonId ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                onTap: () => Navigator.of(context).pop(season['Id'] as String?),
              ),
          ],
        ),
      ),
    );
    if (selected != null && selected != _selectedSeasonId) _selectSeason(selected);
  }

  void _showUnavailable(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final item = _item;
    if (item == null) return Scaffold(body: Center(child: Text(_error ?? 'Not found', style: const TextStyle(color: Color(0xFFA5A7AC)))));

    final name = _asString(item['Name']) ?? 'Untitled';
    final year = item['ProductionYear']?.toString();
    final officialRating = _asString(item['OfficialRating']);
    final communityRating = _asNum(item['CommunityRating']);
    final criticRating = _asNum(item['CriticRating']);
    final overview = _asString(item['Overview']);
    final genres = (item['Genres'] as List<dynamic>?)?.whereType<String>().join(', ');
    final studios = (item['Studios'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().map((s) => _asString(s['Name'])).whereType<String>().join(', ');
    final people = (item['People'] as List<dynamic>?)?.whereType<Map<String, dynamic>>() ?? const [];
    final cast = people.where((p) => p['Type'] == 'Actor').toList();
    final directors = people.where((p) => p['Type'] == 'Director').map((p) => _asString(p['Name'])).whereType<String>().join(', ');
    final backdropTag = (item['BackdropImageTags'] as List<dynamic>?)?.whereType<String>().firstOrNull;
    final backdropUrl = backdropTag != null ? JellyfinApiService.getBackdropUrl(widget.serverUrl, widget.itemId, imageTag: backdropTag, maxWidth: 1200) : null;
    final imageTags = item['ImageTags'];
    final logoTag = imageTags is Map ? _asString(imageTags['Logo']) : null;
    final logoUrl = logoTag != null ? JellyfinApiService.getLogoUrl(widget.serverUrl, widget.itemId, imageTag: logoTag, maxWidth: 800) : null;
    final isSeries = item['Type'] == 'Series';
    final isContainer = !isSeries && item['IsFolder'] == true;
    final canPlay = isSeries ? (_nextUp != null || _seasonEpisodes.isNotEmpty) : (isContainer ? _tracks.isNotEmpty : true);
    final selectedSeasonName = _asString(_seasons.whereType<Map<String, dynamic>>().firstWhere((s) => s['Id'] == _selectedSeasonId, orElse: () => const {})['Name']);

    return Scaffold(
      backgroundColor: const Color(0xFF090A0C),
      body: Stack(
        children: [
          // A softly blurred, dimmed backdrop behind the whole page so the
          // content feels like an extension of the artwork rather than
          // ending abruptly at the hero image, Apple TV-style. Blurred pixels
          // hide detail anyway, so this can stay at a much lower resolution
          // than the sharp hero image above it.
          if (backdropUrl != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                child: CachedNetworkImage(
                  imageUrl: backdropUrl,
                  httpHeaders: JellyfinApiService.authHeaders(widget.token),
                  fit: BoxFit.cover,
                  memCacheWidth: 240,
                ),
              ),
            ),
          if (backdropUrl != null) const Positioned.fill(child: ColoredBox(color: Color(0xCC090A0C))),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 460,
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: const Color(0xFF090A0C).withValues(alpha: .85),
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton(
                      onPressed: () => _showUnavailable('Cast'),
                      icon: const Icon(Icons.cast_outlined),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: backdropUrl == null
                      ? const ColoredBox(color: Color(0xFF181A1E))
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(imageUrl: backdropUrl, httpHeaders: JellyfinApiService.authHeaders(widget.token), fit: BoxFit.cover, memCacheWidth: 1200),
                            const DecoratedBox(
                              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF090A0C)])),
                            ),
                            Positioned(
                              left: 24,
                              right: 24,
                              bottom: 26,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (logoUrl != null)
                                    CachedNetworkImage(
                                      imageUrl: logoUrl,
                                      httpHeaders: JellyfinApiService.authHeaders(widget.token),
                                      memCacheWidth: 800,
                                      fit: BoxFit.contain,
                                      height: 94,
                                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                                    )
                                  else
                                    Text(
                                      name,
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w800,
                                        shadows: [Shadow(blurRadius: 12)],
                                      ),
                                    ),
                                  if (isSeries && _nextUp != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      _asString(_nextUp!['Name']) ?? 'Next episode',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (backdropUrl == null && logoUrl == null) ...[
                    Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                  ],
                  if (isSeries && _nextUp != null)
                    _EpisodeMetaRow(episode: _nextUp!, fallbackRating: officialRating)
                  else
                    Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (year != null) Text(year, style: const TextStyle(color: Color(0xFFA5A7AC))),
                      if (officialRating != null) _RatingPill(text: officialRating),
                      if (communityRating != null) _RatingBadge(icon: Icons.star, color: Colors.amber, value: communityRating.toStringAsFixed(1)),
                      if (criticRating != null) _RatingBadge(icon: Icons.local_movies, color: const Color(0xFFFF5252), value: '${criticRating.round()}%'),
                    ]),
                  const SizedBox(height: 20),
                  if (canPlay) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                        onPressed: _playMain,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_hasResumablePlay ? 'Resume' : 'Watch'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ActionButton(icon: _isFavorite ? Icons.bookmark : Icons.bookmark_border, label: 'Watchlist', active: _isFavorite, onTap: _toggleFavorite),
                      _ActionButton(icon: Icons.star_border_rounded, label: 'Rate', active: false, onTap: () => _showUnavailable('Ratings')),
                      _ActionButton(icon: _isWatched ? Icons.check_circle : Icons.check_circle_outline, label: 'Watched', active: _isWatched, onTap: _toggleWatched),
                      _ActionButton(icon: Icons.download_outlined, label: 'Download', active: false, onTap: () => _showUnavailable('Downloads')),
                      _ActionButton(icon: Icons.more_vert, label: 'More', active: false, onTap: () => _showUnavailable('More actions')),
                    ],
                  ),
                  if (overview != null) ...[const SizedBox(height: 20), Text(overview, style: const TextStyle(height: 1.4))],
                  if (directors.isNotEmpty) ...[const SizedBox(height: 12), Text('Directed by $directors', style: const TextStyle(color: Color(0xFFA5A7AC)))],
                  if (genres != null && genres.isNotEmpty) ...[const SizedBox(height: 16), _LabelValue(label: 'Genres', value: genres)],
                  if (studios != null && studios.isNotEmpty) ...[const SizedBox(height: 8), _LabelValue(label: 'Studios', value: studios)],
                  if (_techStreams.isNotEmpty) ...[const SizedBox(height: 20), _TechInfo(streams: _techStreams)],
                ],
              ),
            ),
          ),
          if (_seasons.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GestureDetector(
                  onTap: _openSeasonPicker,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                    decoration: BoxDecoration(color: const Color(0xFF1B1D22), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(selectedSeasonName ?? 'Season', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const Icon(Icons.expand_more, size: 20),
                    ]),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 190,
                child: _isLoadingEpisodes
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _seasonEpisodes.length,
                        itemBuilder: (context, index) => _EpisodeCard(episode: _seasonEpisodes[index], serverUrl: widget.serverUrl, token: widget.token, onPlay: _playEpisode),
                      ),
              ),
            ),
          ],
          if (isContainer && _tracks.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text('Tracks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverList.builder(
              itemCount: _tracks.length,
              itemBuilder: (context, index) => _TrackRow(track: _tracks[index], onPlay: _playTrack),
            ),
          ],
          if (cast.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text('Cast & Crew', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 128,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cast.length,
                  itemBuilder: (context, index) => _CastMember(person: cast[index], serverUrl: widget.serverUrl, token: widget.token),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpisodeMetaRow extends StatelessWidget {
  const _EpisodeMetaRow({required this.episode, this.fallbackRating});
  final Map<String, dynamic> episode;
  final String? fallbackRating;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String? _formatDate(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso);
    if (date == null) return null;
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final season = episode['ParentIndexNumber'];
    final indexNumber = episode['IndexNumber'];
    final date = _formatDate(_asString(episode['PremiereDate']));
    final runtimeTicks = episode['RunTimeTicks'];
    final runtimeMinutes = runtimeTicks != null ? ticksToDuration(runtimeTicks).inMinutes : null;
    final rating = _asString(episode['OfficialRating']) ?? fallbackRating;

    return Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (season != null && indexNumber != null) Text('S$season • E$indexNumber', style: const TextStyle(color: Color(0xFFA5A7AC), fontWeight: FontWeight.w600)),
      if (date != null) Text(date, style: const TextStyle(color: Color(0xFFA5A7AC))),
      if (runtimeMinutes != null && runtimeMinutes > 0) Text('${runtimeMinutes}m', style: const TextStyle(color: Color(0xFFA5A7AC))),
      if (rating != null) _RatingPill(text: rating),
    ]);
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFA5A7AC)), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFA5A7AC))),
      );
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.icon, required this.color, required this.value});
  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Color(0xFFA5A7AC))),
      ]);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1B1D22)),
            child: Icon(icon, color: active ? Theme.of(context).colorScheme.primary : Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFA5A7AC))),
        ]),
      );
}

class _TechInfo extends StatelessWidget {
  const _TechInfo({required this.streams});
  final List<dynamic> streams;

  static const _codecLabels = {
    'h264': 'H.264', 'hevc': 'HEVC', 'av1': 'AV1', 'vp9': 'VP9', 'vp8': 'VP8',
    'mpeg2video': 'MPEG-2', 'mpeg4': 'MPEG-4', 'vc1': 'VC-1',
    'aac': 'AAC', 'ac3': 'AC3', 'eac3': 'E-AC3', 'dts': 'DTS', 'truehd': 'TrueHD',
    'flac': 'FLAC', 'mp3': 'MP3', 'opus': 'Opus', 'pcm_s16le': 'PCM',
    'subrip': 'SRT', 'srt': 'SRT', 'ass': 'ASS', 'ssa': 'SSA', 'pgssub': 'PGS',
    'dvdsub': 'VOBSUB', 'dvbsub': 'DVBSUB', 'mov_text': 'MOV Text', 'vtt': 'VTT', 'webvtt': 'VTT',
  };

  String _codecLabel(String? codec) {
    if (codec == null) return '';
    return _codecLabels[codec.toLowerCase()] ?? codec.toUpperCase();
  }

  String _resolutionLabel(int? height) {
    if (height == null) return '';
    if (height >= 2000) return '4K';
    if (height >= 1300) return '1440p';
    if (height >= 900) return '1080p';
    if (height >= 600) return '720p';
    return '${height}p';
  }

  @override
  Widget build(BuildContext context) {
    final all = streams.whereType<Map<String, dynamic>>().toList();
    final video = all.firstWhereOrNull((s) => s['Type'] == 'Video');
    final audio = all.firstWhereOrNull((s) => s['Type'] == 'Audio' && s['IsDefault'] == true) ?? all.firstWhereOrNull((s) => s['Type'] == 'Audio');
    final subtitle = all.firstWhereOrNull((s) => s['Type'] == 'Subtitle' && s['IsDefault'] == true) ?? all.firstWhereOrNull((s) => s['Type'] == 'Subtitle');

    String? videoLine;
    if (video != null) {
      final res = _resolutionLabel(_asInt(video['Height']));
      final isDovi = _asString(video['VideoRangeType'])?.toUpperCase().contains('DOVI') == true;
      final profile = _asString(video['Profile']);
      final codec = _codecLabel(_asString(video['Codec']));
      videoLine = '$res${isDovi ? ' DoVi' : ''} ($codec${profile != null ? ' $profile' : ''})';
    }

    final audioLine = audio == null ? null : (_asString(audio['DisplayTitle']) ?? '${_asString(audio['Language'])?.toUpperCase() ?? 'Unknown'} (${_codecLabel(_asString(audio['Codec']))})');
    final subtitleLine = subtitle == null ? null : (_asString(subtitle['DisplayTitle']) ?? '${_asString(subtitle['Language'])?.toUpperCase() ?? 'Unknown'} (${_codecLabel(_asString(subtitle['Codec']))})');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (videoLine != null) _InfoRow(label: 'Video', value: videoLine),
      if (audioLine != null) _InfoRow(label: 'Audio', value: audioLine),
      if (subtitleLine != null) _InfoRow(label: 'Subtitles', value: subtitleLine),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Color(0xFFA5A7AC)))),
          Expanded(child: Text(value)),
        ]),
      );
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Color(0xFFA5A7AC))),
        ],
      );
}

class _CastMember extends StatelessWidget {
  const _CastMember({required this.person, required this.serverUrl, required this.token});
  final dynamic person;
  final String serverUrl;
  final String token;

  @override
  Widget build(BuildContext context) {
    if (person is! Map<String, dynamic>) return const SizedBox.shrink();
    final item = person as Map<String, dynamic>;
    final personId = item['Id'] as String?;
    final tag = item['PrimaryImageTag'] as String?;
    final imageUrl = personId != null && tag != null ? JellyfinApiService.getImageUrl(serverUrl, personId, imageTag: tag, maxWidth: 220) : null;
    final name = item['Name'] as String? ?? '';
    final role = item['Role'] as String?;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: imageUrl == null
                    ? const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.person_outline, color: Colors.white24))
                    : CachedNetworkImage(imageUrl: imageUrl, httpHeaders: JellyfinApiService.authHeaders(token), fit: BoxFit.cover, memCacheWidth: 220, errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.person_outline, color: Colors.white24))),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (role != null && role.isNotEmpty) Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Color(0xFFA5A7AC))),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.onPlay});
  final dynamic track;
  final void Function(Map<String, dynamic> track) onPlay;

  String _formatDuration(dynamic ticks) {
    final duration = ticksToDuration(ticks);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${duration.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (track is! Map<String, dynamic>) return const SizedBox.shrink();
    final item = track as Map<String, dynamic>;
    final name = item['Name'] as String? ?? 'Track';
    final index = item['IndexNumber'];
    final runTimeTicks = item['RunTimeTicks'];
    final isPlayed = (item['UserData'] as Map<String, dynamic>?)?['Played'] == true;

    return ListTile(
      onTap: () => onPlay(item),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: SizedBox(
        width: 28,
        child: Text(index != null ? '$index' : '', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA5A7AC))),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isPlayed) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary)),
        if (runTimeTicks != null) Text(_formatDuration(runTimeTicks), style: const TextStyle(color: Color(0xFFA5A7AC), fontSize: 13)),
      ]),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.serverUrl, required this.token, required this.onPlay});
  final dynamic episode;
  final String serverUrl;
  final String token;
  final void Function(Map<String, dynamic> episode) onPlay;

  @override
  Widget build(BuildContext context) {
    if (episode is! Map<String, dynamic>) return const SizedBox.shrink();
    final item = episode as Map<String, dynamic>;
    final itemId = item['Id'] as String?;
    final name = item['Name'] as String? ?? 'Episode';
    final indexNumber = item['IndexNumber'];
    final isWatched = (item['UserData'] as Map<String, dynamic>?)?['Played'] == true;
    final tag = item['PrimaryImageTag'] as String? ?? (item['ImageTags'] is Map ? (item['ImageTags'] as Map)['Primary'] as String? : null);
    final imageUrl = itemId != null && tag != null ? JellyfinApiService.getImageUrl(serverUrl, itemId, imageTag: tag, maxWidth: 500) : null;

    return GestureDetector(
      onTap: () => onPlay(item),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 168,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 168,
                      height: 96,
                      child: imageUrl == null
                          ? const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.movie_outlined, color: Colors.white24))
                          : CachedNetworkImage(imageUrl: imageUrl, httpHeaders: JellyfinApiService.authHeaders(token), fit: BoxFit.cover, memCacheWidth: 500, errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF17191D))),
                    ),
                  ),
                  if (isWatched)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: Icon(Icons.check, size: 14, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('E${indexNumber ?? '?'} • $name', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

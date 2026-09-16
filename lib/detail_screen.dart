import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'player_screen.dart';
import 'services/jellyfin_api_service.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.serverUrl, required this.userId, required this.token, required this.itemId});
  final String serverUrl;
  final String userId;
  final String token;
  final String itemId;

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
      if (item['Type'] == 'Series') {
        final results = await Future.wait([
          _api.getSeasons(widget.serverUrl, widget.userId, widget.token, widget.itemId),
          _api.getNextUp(widget.serverUrl, widget.userId, widget.token, widget.itemId),
        ]);
        seasons = results[0] as List<dynamic>;
        nextUp = results[1] as Map<String, dynamic>?;
      }
      if (!mounted) return;
      setState(() {
        _item = item;
        _seasons = seasons;
        _nextUp = nextUp;
        _isLoading = false;
      });
      final defaultSeasonId = (nextUp?['SeasonId'] as String?) ?? seasons.whereType<Map<String, dynamic>>().firstOrNull?['Id'] as String?;
      if (defaultSeasonId != null) _selectSeason(defaultSeasonId);
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
      builder: (_) => PlayerScreen(title: title, subtitle: subtitle, serverUrl: widget.serverUrl, userId: widget.userId, token: widget.token, itemId: itemId, startPosition: startPosition, onNext: onNext, isAudioOnly: isAudioOnly),
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
    final ticks = (item['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'];
    final isAudioOnly = item['Type'] == 'Audio' || item['Type'] == 'AudioBook';
    _play(widget.itemId, name, startPosition: ticksToDuration(ticks), isAudioOnly: isAudioOnly);
  }

  bool get _hasResumablePlay {
    final item = _item;
    if (item == null) return false;
    if (item['Type'] == 'Series') return _nextUp != null && ((_nextUp!['UserData'] as Map<String, dynamic>?)?['PlaybackPositionTicks'] ?? 0) > 0;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final item = _item;
    if (item == null) return Scaffold(body: Center(child: Text(_error ?? 'Not found', style: const TextStyle(color: Color(0xFFA5A7AC)))));

    final name = item['Name'] as String? ?? 'Untitled';
    final year = item['ProductionYear']?.toString();
    final officialRating = item['OfficialRating'] as String?;
    final communityRating = item['CommunityRating'];
    final overview = item['Overview'] as String?;
    final genres = (item['Genres'] as List<dynamic>?)?.whereType<String>().join(', ');
    final studios = (item['Studios'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().map((s) => s['Name'] as String?).whereType<String>().join(', ');
    final cast = (item['People'] as List<dynamic>?)?.whereType<Map<String, dynamic>>().where((p) => p['Type'] == 'Actor').toList() ?? const [];
    final backdropTag = (item['BackdropImageTags'] as List<dynamic>?)?.whereType<String>().firstOrNull;
    final backdropUrl = backdropTag != null ? JellyfinApiService.getBackdropUrl(widget.serverUrl, widget.itemId, imageTag: backdropTag) : null;
    final isSeries = item['Type'] == 'Series';
    final canPlay = !isSeries || _nextUp != null || _seasonEpisodes.isNotEmpty;
    final selectedSeasonName = _seasons.whereType<Map<String, dynamic>>().firstWhere((s) => s['Id'] == _selectedSeasonId, orElse: () => const {})['Name'] as String?;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: const Color(0xFF090A0C),
            flexibleSpace: FlexibleSpaceBar(
              background: backdropUrl == null
                  ? const ColoredBox(color: Color(0xFF181A1E))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(imageUrl: backdropUrl, httpHeaders: JellyfinApiService.authHeaders(widget.token), fit: BoxFit.cover),
                        const DecoratedBox(
                          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF090A0C)])),
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
                  Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (year != null) Text(year, style: const TextStyle(color: Color(0xFFA5A7AC))),
                    if (officialRating != null) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFA5A7AC)), borderRadius: BorderRadius.circular(4)), child: Text(officialRating, style: const TextStyle(fontSize: 12, color: Color(0xFFA5A7AC)))),
                    if (communityRating != null)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text((communityRating as num).toStringAsFixed(1), style: const TextStyle(color: Color(0xFFA5A7AC))),
                      ]),
                  ]),
                  const SizedBox(height: 20),
                  if (canPlay) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _playMain,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(_hasResumablePlay ? 'Resume' : 'Play'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(children: [
                    IconButton(
                      onPressed: _toggleWatched,
                      icon: Icon(_isWatched ? Icons.check_circle : Icons.check_circle_outline, color: _isWatched ? Theme.of(context).colorScheme.primary : Colors.white70),
                    ),
                    IconButton(
                      onPressed: _toggleFavorite,
                      icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: _isFavorite ? Theme.of(context).colorScheme.primary : Colors.white70),
                    ),
                  ]),
                  if (overview != null) ...[const SizedBox(height: 16), Text(overview, style: const TextStyle(height: 1.4))],
                  if (genres != null && genres.isNotEmpty) ...[const SizedBox(height: 16), _LabelValue(label: 'Genres', value: genres)],
                  if (studios != null && studios.isNotEmpty) ...[const SizedBox(height: 8), _LabelValue(label: 'Studios', value: studios)],
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(selectedSeasonName ?? 'Season', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const Icon(Icons.arrow_drop_down),
                  ]),
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
    );
  }
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
    final imageUrl = personId != null && tag != null ? JellyfinApiService.getImageUrl(serverUrl, personId, imageTag: tag) : null;
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
                    : CachedNetworkImage(imageUrl: imageUrl, httpHeaders: JellyfinApiService.authHeaders(token), fit: BoxFit.cover, errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.person_outline, color: Colors.white24))),
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
    final imageUrl = itemId != null && tag != null ? JellyfinApiService.getImageUrl(serverUrl, itemId, imageTag: tag) : null;

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
                          : CachedNetworkImage(imageUrl: imageUrl, httpHeaders: JellyfinApiService.authHeaders(token), fit: BoxFit.cover, errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF17191D))),
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

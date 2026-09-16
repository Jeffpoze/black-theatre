import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'services/jellyfin_api_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.serverUrl, required this.userId, required this.token});
  final String serverUrl;
  final String userId;
  final String token;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _api = JellyfinApiService();
  List<dynamic> _items = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _api.getUpcomingItems(widget.serverUrl, widget.userId, widget.token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _isLoading = false; _error = 'Unable to load upcoming releases.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate(_items);
    return Scaffold(
      appBar: AppBar(title: const Text('CALENDAR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFA5A7AC))))
              : groups.isEmpty
                  ? const Center(child: Text('No upcoming releases found in your library.', style: TextStyle(color: Color(0xFFA5A7AC))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                              child: Text(group.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFA5A7AC))),
                            ),
                            for (final item in group.items) _UpcomingRow(item: item, serverUrl: widget.serverUrl, token: widget.token),
                          ],
                        );
                      },
                    ),
    );
  }

  List<_DateGroup> _groupByDate(List<dynamic> items) {
    final byDate = <String, List<dynamic>>{};
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final date = DateTime.tryParse(item['PremiereDate'] as String? ?? '');
      final key = date == null ? 'Unknown' : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      byDate.putIfAbsent(key, () => []).add(item);
    }
    final keys = byDate.keys.toList()..sort();
    return [for (final key in keys) _DateGroup(label: _formatGroupLabel(key), items: byDate[key]!)];
  }

  String _formatGroupLabel(String key) {
    final date = DateTime.tryParse(key);
    if (date == null) return 'Date unknown';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _DateGroup {
  const _DateGroup({required this.label, required this.items});
  final String label;
  final List<dynamic> items;
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.item, required this.serverUrl, required this.token});
  final Map<String, dynamic> item;
  final String serverUrl;
  final String token;

  @override
  Widget build(BuildContext context) {
    final isEpisode = item['Type'] == 'Episode';
    final title = isEpisode ? (item['SeriesName'] as String? ?? 'Unknown Show') : (item['Name'] as String? ?? 'Untitled');
    final subtitle = isEpisode
        ? 'S${item['ParentIndexNumber'] ?? '?'}E${item['IndexNumber'] ?? '?'} • ${item['Name'] ?? ''}'
        : 'Movie';

    final (posterId, tag) = _posterImage(item);
    final imageUrl = posterId != null && tag != null ? JellyfinApiService.getImageUrl(serverUrl, posterId, imageTag: tag, maxWidth: 170) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 56,
              height: 80,
              child: imageUrl == null
                  ? const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.movie_outlined, color: Colors.white24))
                  : CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: JellyfinApiService.authHeaders(token),
                      fit: BoxFit.cover,
                      memCacheWidth: 170,
                      placeholder: (_, _) => const ColoredBox(color: Color(0xFF17191D)),
                      errorWidget: (_, _, _) => const ColoredBox(color: Color(0xFF17191D), child: Icon(Icons.movie_outlined, color: Colors.white24)),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFFA5A7AC)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String?, String?) _posterImage(Map<String, dynamic> item) {
    final itemId = item['Id'] as String?;
    final primaryTag = item['PrimaryImageTag'];
    if (primaryTag is String && primaryTag.isNotEmpty) return (itemId, primaryTag);
    final imageTags = item['ImageTags'];
    if (imageTags is Map && imageTags['Primary'] is String) return (itemId, imageTags['Primary'] as String);
    final seriesTag = item['SeriesPrimaryImageTag'];
    final seriesId = item['SeriesId'];
    if (seriesTag is String && seriesTag.isNotEmpty && seriesId is String) return (seriesId, seriesTag);
    return (null, null);
  }
}

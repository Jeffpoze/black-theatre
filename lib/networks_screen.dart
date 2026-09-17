import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'services/jellyfin_api_service.dart';
import 'settings_controller.dart';

// Jellyfin has no distinct "Network" concept — the distributing network
// (Netflix, Apple TV+, …) and a production studio both just land in the
// same Studios list. Server-wide Studios includes plenty of production
// companies (A24, Bones, Legendary…) that aren't what "network browsing"
// means here, so this filters down to recognizable streaming/broadcast
// networks by name rather than showing every studio.
const _knownNetworkPatterns = [
  'netflix',
  'apple tv',
  'prime video',
  'amazon',
  'disney',
  'hulu',
  'hbo',
  'max',
  'paramount',
  'peacock',
  'crunchyroll',
  'funimation',
  'showtime',
  'starz',
  'fx',
  'amc',
  'bbc',
  'itv',
  'adult swim',
  'cartoon network',
  'nickelodeon',
  'youtube',
  'tubi',
  'crackle',
  'britbox',
];

bool _looksLikeNetwork(String name) {
  final lower = name.toLowerCase();
  return _knownNetworkPatterns.any((pattern) => lower.contains(pattern));
}

class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key, required this.session, required this.settings});
  final JellyfinSession session;
  final SettingsController settings;

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  final _api = JellyfinApiService();
  List<dynamic>? _networks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final studios = await _api.getStudios(widget.session.serverUrl, widget.session.userId, widget.session.token);
    final networks = studios.whereType<Map<String, dynamic>>().where((s) {
      final name = s['Name'] as String?;
      return name != null && _looksLikeNetwork(name);
    }).toList()
      ..sort((a, b) => ((a['Name'] as String?) ?? '').compareTo((b['Name'] as String?) ?? ''));
    if (mounted) setState(() => _networks = networks);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('NETWORKS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
    body: _networks == null
        ? const Center(child: CircularProgressIndicator())
        : _networks!.isEmpty
            ? const Center(child: Text('No recognized networks found in your library.', style: TextStyle(color: Color(0xFFA5A7AC))))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.8,
                ),
                itemCount: _networks!.length,
                itemBuilder: (context, index) {
                  final network = _networks![index] as Map<String, dynamic>;
                  return _NetworkTile(network: network, session: widget.session, settings: widget.settings);
                },
              ),
  );
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network, required this.session, required this.settings});
  final Map<String, dynamic> network;
  final JellyfinSession session;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final id = network['Id'] as String?;
    final name = (network['Name'] as String?) ?? 'Network';
    final tag = network['ImageTags'] is Map ? (network['ImageTags'] as Map)['Primary'] as String? : null;
    final imageUrl = id != null && tag != null ? JellyfinApiService.getImageUrl(session.serverUrl, id, imageTag: tag, maxWidth: 400) : null;

    return GestureDetector(
      onTap: id == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NetworkItemsScreen(session: session, settings: settings, studioId: id, studioName: name)),
              ),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF1B1D22), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(16),
        alignment: Alignment.center,
        child: imageUrl == null
            ? Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))
            : CachedNetworkImage(imageUrl: imageUrl, httpHeaders: JellyfinApiService.authHeaders(session.token), fit: BoxFit.contain, errorWidget: (_, _, _) => Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
      ),
    );
  }
}

class NetworkItemsScreen extends StatefulWidget {
  const NetworkItemsScreen({super.key, required this.session, required this.settings, required this.studioId, required this.studioName});
  final JellyfinSession session;
  final SettingsController settings;
  final String studioId;
  final String studioName;

  @override
  State<NetworkItemsScreen> createState() => _NetworkItemsScreenState();
}

class _NetworkItemsScreenState extends State<NetworkItemsScreen> {
  final _api = JellyfinApiService();
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _api.getItemsByStudio(widget.session.serverUrl, widget.session.userId, widget.session.token, widget.studioId);
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.studioName.toUpperCase(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
    body: _items == null
        ? const Center(child: CircularProgressIndicator())
        : _items!.isEmpty
            ? const Center(child: Text('Nothing here yet.', style: TextStyle(color: Color(0xFFA5A7AC))))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.66,
                ),
                itemCount: _items!.length,
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: MediaPoster(
                    item: _items![index],
                    serverUrl: widget.session.serverUrl,
                    userId: widget.session.userId,
                    token: widget.session.token,
                    fill: true,
                    settings: widget.settings,
                  ),
                ),
              ),
  );
}

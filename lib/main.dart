// ignore_for_file: avoid_print

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/jellyfin_api_service.dart';

void main() => runApp(const BlackTheatreTvApp());

class BlackTheatreTvApp extends StatelessWidget {
  const BlackTheatreTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF090A0C);
    return MaterialApp(
      title: 'Black Theatre',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Color(0xFF141518)),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF191A1E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withValues(alpha: .6))),
          labelStyle: const TextStyle(color: Color(0xFFA5A7AC)),
        ),
        textTheme: ThemeData.dark().textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      home: const AuthenticationScreen(),
    );
  }
}

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key});
  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = JellyfinApiService();
  bool _isLoading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final session = await _api.login(serverUrl: _serverController.text, username: _usernameController.text, password: _passwordController.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('serverUrl', session.serverUrl);
      await prefs.setString('userId', session.userId);
      await prefs.setString('accessToken', session.token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(session: session)));
    } catch (_) {
      if (mounted) setState(() => _error = 'We could not connect. Check your details and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ListView(shrinkWrap: true, children: [
                const Icon(Icons.movie_filter_outlined, size: 48),
                const SizedBox(height: 24),
                Text('Welcome to your theatre.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Connect your Jellyfin server to begin.', style: TextStyle(color: Color(0xFFA5A7AC))),
                const SizedBox(height: 32),
                TextField(controller: _serverController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Jellyfin Server URL', hintText: 'https://jellyfin.example.com')),
                const SizedBox(height: 14),
                TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 14),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                if (_error != null) ...[const SizedBox(height: 16), Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80)))],
                const SizedBox(height: 24),
                SizedBox(height: 52, child: FilledButton(onPressed: _isLoading ? null : _signIn, child: _isLoading ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign In'))),
              ]),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session});
  final JellyfinSession session;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = JellyfinApiService();
  List<dynamic> _continueWatching = const [];
  List<dynamic> _libraryViews = const [];
  Map<String, List<dynamic>> _categoryItems = {};
  String? _selectedCategoryId;
  bool _isLoadingHome = true;

  @override
  void initState() {
    super.initState();
    _loadHomeSections();
  }

  Future<void> _loadHomeSections() async {
    final results = await Future.wait([
      _loadSection('continue watching', () => _api.getContinueWatching(widget.session.serverUrl, widget.session.userId, widget.session.token)),
      _loadSection('library views', () => _api.getLibraryViews(widget.session.serverUrl, widget.session.userId, widget.session.token)),
    ]);
    final continueWatching = results[0];
    final libraryViews = results[1];

    final categoryIds = libraryViews.whereType<Map<String, dynamic>>().map((view) => view['Id'] as String?).whereType<String>().toList();
    final categoryResults = await Future.wait(categoryIds.map(
      (id) => _loadSection('category $id', () => _api.getRecentItemsForView(widget.session.serverUrl, widget.session.userId, widget.session.token, id)),
    ));

    if (!mounted) return;
    setState(() {
      _continueWatching = continueWatching;
      _libraryViews = libraryViews;
      _categoryItems = Map.fromIterables(categoryIds, categoryResults);
      _isLoadingHome = false;
    });
  }

  Future<List<dynamic>> _loadSection(String name, Future<List<dynamic>> Function() load) async {
    try {
      return await load();
    } catch (e) {
      print('Failed to load $name: $e');
      return const [];
    }
  }

  void _selectCategory(String? id) {
    Navigator.of(context).pop();
    setState(() => _selectedCategoryId = id);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCategoryId == null
        ? null
        : _libraryViews.whereType<Map<String, dynamic>>().firstWhere((view) => view['Id'] == _selectedCategoryId, orElse: () => const {});

    return Scaffold(
      appBar: AppBar(
        title: Text(selected != null && selected['Name'] is String ? (selected['Name'] as String).toUpperCase() : 'BLACK THEATRE', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
        leading: Builder(builder: (context) => IconButton(onPressed: () => Scaffold.of(context).openDrawer(), icon: const Icon(Icons.menu))),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search))],
      ),
      drawer: _CategoryDrawer(libraryViews: _libraryViews, selectedId: _selectedCategoryId, onSelect: _selectCategory),
      body: _selectedCategoryId == null
          ? ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _HeroPlaceholder(),
                _MediaRow(title: 'Continue Watching', serverUrl: widget.session.serverUrl, token: widget.session.token, items: _continueWatching, isLoading: _isLoadingHome),
                for (final view in _libraryViews.whereType<Map<String, dynamic>>())
                  if (view['Id'] is String)
                    _MediaRow(
                      title: (view['Name'] as String?) ?? 'Library',
                      serverUrl: widget.session.serverUrl,
                      token: widget.session.token,
                      items: _categoryItems[view['Id']] ?? const [],
                      isLoading: _isLoadingHome,
                    ),
              ],
            )
          : _CategoryGrid(items: _categoryItems[_selectedCategoryId] ?? const [], serverUrl: widget.session.serverUrl, token: widget.session.token, isLoading: _isLoadingHome),
    );
  }
}

class _CategoryDrawer extends StatelessWidget {
  const _CategoryDrawer({required this.libraryViews, required this.selectedId, required this.onSelect});
  final List<dynamic> libraryViews;
  final String? selectedId;
  final void Function(String?) onSelect;

  @override
  Widget build(BuildContext context) => Drawer(
        backgroundColor: const Color(0xFF0D0E11),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              const Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 20), child: Text('CATEGORIES', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Color(0xFFA5A7AC)))),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Home'),
                selected: selectedId == null,
                selectedTileColor: const Color(0xFF1B1D22),
                onTap: () => onSelect(null),
              ),
              for (final view in libraryViews.whereType<Map<String, dynamic>>())
                if (view['Id'] is String)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text((view['Name'] as String?) ?? 'Library'),
                    selected: selectedId == view['Id'],
                    selectedTileColor: const Color(0xFF1B1D22),
                    onTap: () => onSelect(view['Id'] as String),
                  ),
            ],
          ),
        ),
      );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.items, required this.serverUrl, required this.token, required this.isLoading});
  final List<dynamic> items;
  final String serverUrl;
  final String token;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const Center(child: Text('Nothing here yet.', style: TextStyle(color: Color(0xFFA5A7AC))));
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 0.66),
      itemCount: items.length,
      itemBuilder: (_, index) => ClipRRect(borderRadius: BorderRadius.circular(6), child: _MediaPoster(item: items[index], serverUrl: serverUrl, token: token, fill: true)),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        height: 390,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        decoration: BoxDecoration(color: const Color(0xFF181A1E), borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_circle_outline, size: 56, color: Colors.white70), SizedBox(height: 12), Text('Your featured story', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)), SizedBox(height: 6), Text('Trailers will play here', style: TextStyle(color: Colors.white54))])),
      );
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.title, required this.serverUrl, required this.token, required this.items, required this.isLoading});
  final String title;
  final String serverUrl;
  final String token;
  final List<dynamic> items;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          SizedBox(height: 190, child: isLoading || items.isEmpty ? ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: 5, separatorBuilder: (_, _) => const SizedBox(width: 12), itemBuilder: (_, index) => _PosterPlaceholder(index: index)) : ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: items.length, itemBuilder: (_, index) => _MediaPoster(item: items[index], serverUrl: serverUrl, token: token))),
        ]),
      );
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => Container(width: 132, decoration: BoxDecoration(color: Color(0xFF17191D + (index * 0x020202)), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 32));
}

class _MediaPoster extends StatelessWidget {
  const _MediaPoster({required this.item, required this.serverUrl, required this.token, this.fill = false});
  final dynamic item;
  final String serverUrl;
  final String token;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (item is! Map<String, dynamic>) return _DarkPosterPlaceholder(fill: fill);
    final (posterItemId, imageTag) = _posterImage(item);
    if (posterItemId == null || imageTag == null || imageTag.isEmpty) {
      return _DarkPosterPlaceholder(fill: fill);
    }
    final imageUrl = JellyfinApiService.getImageUrl(serverUrl, posterItemId, imageTag: imageTag);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        httpHeaders: JellyfinApiService.authHeaders(token),
        fit: BoxFit.cover,
        placeholder: (_, _) => _DarkPosterPlaceholder(fill: fill),
        errorWidget: (_, _, _) => _DarkPosterPlaceholder(fill: fill),
      ),
    );
    if (fill) return image;
    return Padding(padding: const EdgeInsets.only(right: 12), child: SizedBox(width: 132, child: image));
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

class _DarkPosterPlaceholder extends StatelessWidget {
  const _DarkPosterPlaceholder({this.fill = false});
  final bool fill;

  @override
  Widget build(BuildContext context) => Container(
        width: fill ? null : 132,
        color: const Color(0xFF17191D),
        child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 32),
      );
}

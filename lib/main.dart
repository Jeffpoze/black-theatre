// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_screen.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'services/jellyfin_api_service.dart';
import 'settings_controller.dart';
import 'settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final settings = SettingsController();
  await settings.load();
  final savedSession = await _loadSavedSession();
  runApp(BlackTheatreTvApp(settings: settings, initialSession: savedSession));
}

Future<JellyfinSession?> _loadSavedSession() async {
  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString('serverUrl');
  final userId = prefs.getString('userId');
  final token = prefs.getString('accessToken');
  final username = prefs.getString('username');
  if (serverUrl == null || userId == null || token == null || username == null)
    return null;
  return JellyfinSession(
    serverUrl: serverUrl,
    userId: userId,
    token: token,
    username: username,
  );
}

class BlackTheatreTvApp extends StatelessWidget {
  const BlackTheatreTvApp({
    super.key,
    required this.settings,
    this.initialSession,
  });
  final SettingsController settings;
  final JellyfinSession? initialSession;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF090A0C);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'Black Theatre',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: background,
          colorScheme: ColorScheme.dark(
            primary: settings.accentColor,
            surface: const Color(0xFF141518),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF191A1E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: settings.accentColor.withValues(alpha: .8),
              ),
            ),
            labelStyle: const TextStyle(color: Color(0xFFA5A7AC)),
          ),
          textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: settings.accentColor,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        home: initialSession != null
            ? HomePage(session: initialSession!, settings: settings)
            : AuthenticationScreen(settings: settings),
      ),
    );
  }
}

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key, required this.settings});
  final SettingsController settings;
  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = JellyfinApiService();
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final session = await _api.login(
        serverUrl: _serverController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('serverUrl', session.serverUrl);
        await prefs.setString('userId', session.userId);
        await prefs.setString('accessToken', session.token);
        await prefs.setString('username', session.username);
      } else {
        await prefs.remove('serverUrl');
        await prefs.remove('userId');
        await prefs.remove('accessToken');
        await prefs.remove('username');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(session: session, settings: widget.settings),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'We could not connect. Check your details and try again.',
        );
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
          child: ListView(
            shrinkWrap: true,
            children: [
              Image.asset('assets/images/logo_mark.png', width: 88, height: 88),
              const SizedBox(height: 24),
              Text(
                'Welcome to your theatre.',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect your Jellyfin server to begin.',
                style: TextStyle(color: Color(0xFFA5A7AC)),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _serverController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Jellyfin Server URL',
                  hintText: 'https://jellyfin.example.com',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFFA5A7AC),
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (value) =>
                    setState(() => _rememberMe = value ?? true),
                title: const Text('Remember me'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session, required this.settings});
  final JellyfinSession session;
  final SettingsController settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = JellyfinApiService();
  List<dynamic> _continueWatching = const [];
  List<dynamic> _libraryViews = const [];
  Map<String, List<dynamic>> _categoryItems = {};
  List<dynamic> _featuredItems = const [];
  String? _selectedCategoryId;
  bool _isLoadingContinueWatching = true;
  bool _isLoadingFeaturedItems = true;
  final Set<String> _loadingCategoryIds = {};
  List<dynamic> _selectedCategoryItems = const [];
  bool _isLoadingSelectedCategory = false;

  @override
  void initState() {
    super.initState();
    _loadHomeSections();
  }

  Future<void> _loadHomeSections() async {
    // Each row should become usable as soon as its request completes. The
    // previous two-stage Future.wait held the whole homepage hostage to the
    // slowest section, then started every library request at once.
    _loadContinueWatching();
    _loadFeaturedItems();
    final libraryViews = await _loadSection(
      'library views',
      () => _api.getLibraryViews(
        widget.session.serverUrl,
        widget.session.userId,
        widget.session.token,
      ),
    );
    if (!mounted) return;
    final categoryIds = libraryViews
        .whereType<Map<String, dynamic>>()
        .map((view) => view['Id'] as String?)
        .whereType<String>()
        .toList();
    setState(() {
      _libraryViews = libraryViews;
      _loadingCategoryIds.addAll(categoryIds);
    });
    _loadCategoryRows(categoryIds);
  }

  Future<void> _loadContinueWatching() async {
    final items = await _loadSection(
      'continue watching',
      () => _api.getContinueWatching(
        widget.session.serverUrl,
        widget.session.userId,
        widget.session.token,
      ),
    );
    if (!mounted) return;
    setState(() {
      _continueWatching = items;
      _isLoadingContinueWatching = false;
    });
  }

  Future<void> _loadFeaturedItems() async {
    final items = await _loadSection(
      'featured items',
      () => _api.getFeaturedItems(
        widget.session.serverUrl,
        widget.session.userId,
        widget.session.token,
      ),
    );
    if (!mounted) return;
    setState(() {
      _featuredItems = items;
      _isLoadingFeaturedItems = false;
    });
  }

  Future<void> _loadCategoryRows(List<String> categoryIds) async {
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < categoryIds.length) {
        final id = categoryIds[nextIndex++];
        final items = await _loadSection(
          'category $id',
          () => _api.getRecentItemsForView(
            widget.session.serverUrl,
            widget.session.userId,
            widget.session.token,
            id,
          ),
        );
        if (!mounted) return;
        setState(() {
          _categoryItems = {..._categoryItems, id: items};
          _loadingCategoryIds.remove(id);
        });
      }
    }

    // Parent-art lookups make a category request more expensive than it first
    // appears. Three workers keep the server responsive for video playback.
    await Future.wait(
      List.generate(categoryIds.length.clamp(0, 3), (_) => worker()),
    );
  }

  Future<List<dynamic>> _loadSection(
    String name,
    Future<List<dynamic>> Function() load,
  ) async {
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
    if (id != null) _loadSelectedCategory(id);
  }

  Future<void> _loadSelectedCategory(String id) async {
    setState(() => _isLoadingSelectedCategory = true);
    final sort = widget.settings.sortFor(id);
    final items = await _loadSection(
      'selected category $id',
      () => _api.getLibraryItems(
        widget.session.serverUrl,
        widget.session.userId,
        widget.session.token,
        id,
        sort: sort,
      ),
    );
    if (!mounted || _selectedCategoryId != id) return;
    setState(() {
      _selectedCategoryItems = items;
      _isLoadingSelectedCategory = false;
    });
  }

  void _changeSort(SortOption option) {
    final id = _selectedCategoryId;
    if (id == null) return;
    widget.settings.setSortFor(id, option);
    _loadSelectedCategory(id);
  }

  void _openSettings() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SettingsScreen(settings: widget.settings, session: widget.session),
      ),
    );
  }

  void _openCalendar() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(
          serverUrl: widget.session.serverUrl,
          userId: widget.session.userId,
          token: widget.session.token,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCategoryId == null
        ? null
        : _libraryViews.whereType<Map<String, dynamic>>().firstWhere(
            (view) => view['Id'] == _selectedCategoryId,
            orElse: () => const {},
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected != null && selected['Name'] is String
              ? (selected['Name'] as String).toUpperCase()
              : 'BLACK THEATRE',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu),
          ),
        ),
        actions: [
          if (_selectedCategoryId != null)
            PopupMenuButton<SortOption>(
              icon: const Icon(Icons.sort),
              onSelected: _changeSort,
              itemBuilder: (context) => [
                for (final option in SortOption.values)
                  PopupMenuItem(value: option, child: Text(option.label)),
              ],
            ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
        ],
      ),
      drawer: _CategoryDrawer(
        libraryViews: _libraryViews,
        selectedId: _selectedCategoryId,
        onSelect: _selectCategory,
        onSettings: _openSettings,
        onCalendar: _openCalendar,
      ),
      body: _selectedCategoryId == null
          ? ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _isLoadingFeaturedItems
                    ? const _HeroPlaceholder()
                    : _HeroCarousel(
                        items: _featuredItems,
                        serverUrl: widget.session.serverUrl,
                        userId: widget.session.userId,
                        token: widget.session.token,
                      ),
                _MediaRow(
                  title: 'Continue Watching',
                  serverUrl: widget.session.serverUrl,
                  userId: widget.session.userId,
                  token: widget.session.token,
                  items: _continueWatching,
                  isLoading: _isLoadingContinueWatching,
                ),
                for (final view
                    in _libraryViews.whereType<Map<String, dynamic>>())
                  if (view['Id'] is String)
                    _MediaRow(
                      title: (view['Name'] as String?) ?? 'Library',
                      serverUrl: widget.session.serverUrl,
                      userId: widget.session.userId,
                      token: widget.session.token,
                      items: _categoryItems[view['Id']] ?? const [],
                      isLoading: _loadingCategoryIds.contains(view['Id']),
                    ),
              ],
            )
          : _CategoryGrid(
              items: _selectedCategoryItems,
              serverUrl: widget.session.serverUrl,
              userId: widget.session.userId,
              token: widget.session.token,
              isLoading: _isLoadingSelectedCategory,
            ),
    );
  }
}

class _CategoryDrawer extends StatelessWidget {
  const _CategoryDrawer({
    required this.libraryViews,
    required this.selectedId,
    required this.onSelect,
    required this.onSettings,
    required this.onCalendar,
  });
  final List<dynamic> libraryViews;
  final String? selectedId;
  final void Function(String?) onSelect;
  final VoidCallback onSettings;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: const Color(0xFF0D0E11),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Text(
              'CATEGORIES',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color(0xFFA5A7AC),
              ),
            ),
          ),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Divider(color: Color(0xFF1B1D22)),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Calendar'),
            onTap: onCalendar,
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: onSettings,
          ),
        ],
      ),
    ),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.items,
    required this.serverUrl,
    required this.userId,
    required this.token,
    required this.isLoading,
  });
  final List<dynamic> items;
  final String serverUrl;
  final String userId;
  final String token;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty)
      return const Center(
        child: Text(
          'Nothing here yet.',
          style: TextStyle(color: Color(0xFFA5A7AC)),
        ),
      );
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _MediaPoster(
          item: items[index],
          serverUrl: serverUrl,
          userId: userId,
          token: token,
          fill: true,
        ),
      ),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 390,
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 28),
    decoration: BoxDecoration(
      color: const Color(0xFF181A1E),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline, size: 56, color: Colors.white70),
          SizedBox(height: 12),
          Text(
            'Your featured story',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 6),
          Text(
            'Trailers will play here',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    ),
  );
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    required this.items,
    required this.serverUrl,
    required this.userId,
    required this.token,
  });
  final List<dynamic> items;
  final String serverUrl;
  final String userId;
  final String token;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 7), (_) {
        if (!mounted) return;
        final next = (_page + 1) % widget.items.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return const _HeroPlaceholder();
    return SizedBox(
      height: 390,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: items.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) => _HeroCard(
              item: items[index],
              serverUrl: widget.serverUrl,
              userId: widget.userId,
              token: widget.token,
            ),
          ),
          if (items.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page ? Colors.white : Colors.white30,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.item,
    required this.serverUrl,
    required this.userId,
    required this.token,
  });
  final Map<String, dynamic> item;
  final String serverUrl;
  final String userId;
  final String token;

  @override
  Widget build(BuildContext context) {
    final itemId = item['Id'] as String?;
    final name = item['Name'] as String? ?? 'Untitled';
    final overview = item['Overview'] as String?;
    final backdropTag = (item['BackdropImageTags'] as List<dynamic>?)
        ?.whereType<String>()
        .firstOrNull;
    final backdropUrl = itemId != null && backdropTag != null
        ? JellyfinApiService.getBackdropUrl(
            serverUrl,
            itemId,
            imageTag: backdropTag,
            maxWidth: 1200,
          )
        : null;
    final isMovie = item['Type'] == 'Movie';

    return GestureDetector(
      onTap: itemId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailScreen(
                  serverUrl: serverUrl,
                  userId: userId,
                  token: token,
                  itemId: itemId,
                ),
              ),
            ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF181A1E),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdropUrl != null)
              CachedNetworkImage(
                imageUrl: backdropUrl,
                httpHeaders: JellyfinApiService.authHeaders(token),
                fit: BoxFit.cover,
                memCacheWidth: 1200,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF090A0C)],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (overview != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFCACBCF)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (isMovie)
                    SizedBox(
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              title: name,
                              serverUrl: serverUrl,
                              userId: userId,
                              token: token,
                              itemId: itemId!,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Play'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.title,
    required this.serverUrl,
    required this.userId,
    required this.token,
    required this.items,
    required this.isLoading,
  });
  final String title;
  final String serverUrl;
  final String userId;
  final String token;
  final List<dynamic> items;
  final bool isLoading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 246,
          child: isLoading || items.isEmpty
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => _PosterPlaceholder(index: index),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (_, index) => _MediaPoster(
                    item: items[index],
                    serverUrl: serverUrl,
                    userId: userId,
                    token: token,
                  ),
                ),
        ),
      ],
    ),
  );
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 2 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xFF17191D + (index * 0x020202)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.movie_outlined,
              color: Colors.white24,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 12, width: 96, color: const Color(0xFF17191D)),
        const SizedBox(height: 6),
        Container(height: 10, width: 60, color: const Color(0xFF17191D)),
      ],
    ),
  );
}

class _MediaPoster extends StatelessWidget {
  const _MediaPoster({
    required this.item,
    required this.serverUrl,
    required this.userId,
    required this.token,
    this.fill = false,
  });
  final dynamic item;
  final String serverUrl;
  final String userId;
  final String token;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (item is! Map<String, dynamic>)
      return _DarkPosterPlaceholder(fill: fill);
    final (posterItemId, imageTag) = _posterImage(item);
    final Widget content;
    if (posterItemId == null || imageTag == null || imageTag.isEmpty) {
      content = _DarkPosterPlaceholder(fill: fill);
    } else {
      final imageUrl = JellyfinApiService.getImageUrl(
        serverUrl,
        posterItemId,
        imageTag: imageTag,
        maxWidth: 400,
      );
      content = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          httpHeaders: JellyfinApiService.authHeaders(token),
          fit: BoxFit.cover,
          memCacheWidth: 400,
          placeholder: (_, _) => _DarkPosterPlaceholder(fill: fill),
          errorWidget: (_, _, _) => _DarkPosterPlaceholder(fill: fill),
        ),
      );
    }

    final navigableId = _navigableItemId(item);
    final unwatchedCount = _unwatchedCount(item);
    final badged = Stack(
      children: [
        Positioned.fill(child: content),
        if (unwatchedCount != null && unwatchedCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unwatchedCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
    final poster = AspectRatio(aspectRatio: 2 / 3, child: badged);
    final tappable = GestureDetector(
      onTap: navigableId == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailScreen(
                  serverUrl: serverUrl,
                  userId: userId,
                  token: token,
                  itemId: navigableId,
                ),
              ),
            ),
      child: fill
          ? poster
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                poster,
                const SizedBox(height: 8),
                Text(
                  item['Name'] as String? ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_yearInfo(item) != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _yearInfo(item)!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFA5A7AC),
                    ),
                  ),
                ],
              ],
            ),
    );
    if (fill) return tappable;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(width: 132, child: tappable),
    );
  }

  String? _yearInfo(Map<String, dynamic> item) {
    final year = item['ProductionYear'];
    if (year == null) return null;
    if (item['Type'] == 'Series') {
      final status = item['Status'] as String?;
      final endDate = item['EndDate'] as String?;
      if (status != 'Continuing' && endDate is String) {
        final endYear = DateTime.tryParse(endDate)?.year;
        if (endYear != null) return '$year - $endYear';
      }
      return '$year - Present';
    }
    return '$year';
  }

  int? _unwatchedCount(Map<String, dynamic> item) {
    if (item['Type'] != 'Series') return null;
    final userData = item['UserData'];
    if (userData is! Map) return null;
    final count = userData['UnplayedItemCount'];
    return count is num ? count.toInt() : null;
  }

  String? _navigableItemId(Map<String, dynamic> item) {
    if (item['Type'] == 'Episode') return item['SeriesId'] as String?;
    return item['Id'] as String?;
  }

  (String?, String?) _posterImage(Map<String, dynamic> item) {
    // Episodes carry their own screenshot as PrimaryImageTag, but browsing rows
    // should show the show's poster, not a random episode still.
    if (item['Type'] == 'Episode') {
      final seriesTag = item['SeriesPrimaryImageTag'];
      final seriesId = item['SeriesId'];
      if (seriesTag is String && seriesTag.isNotEmpty && seriesId is String)
        return (seriesId, seriesTag);
    }
    final itemId = item['Id'] as String?;
    final primaryTag = item['PrimaryImageTag'];
    if (primaryTag is String && primaryTag.isNotEmpty)
      return (itemId, primaryTag);
    final imageTags = item['ImageTags'];
    if (imageTags is Map && imageTags['Primary'] is String)
      return (itemId, imageTags['Primary'] as String);
    final seriesTag = item['SeriesPrimaryImageTag'];
    final seriesId = item['SeriesId'];
    if (seriesTag is String && seriesTag.isNotEmpty && seriesId is String)
      return (seriesId, seriesTag);
    // Audio tracks usually carry no image of their own; fall back to the album's art.
    final albumTag = item['AlbumPrimaryImageTag'];
    final albumId = item['AlbumId'];
    if (albumTag is String && albumTag.isNotEmpty && albumId is String)
      return (albumId, albumTag);
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

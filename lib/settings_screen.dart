import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'services/jellyfin_api_service.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.session});
  final SettingsController settings;
  final JellyfinSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SETTINGS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: ListView(
          children: [
            _SettingsRow(title: 'Account', subtitle: session.username, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountScreen(session: session, settings: settings)))),
            _SettingsRow(title: 'Appearance', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppearanceScreen(settings: settings)))),
            _SettingsRow(title: 'Playback', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaybackScreen(settings: settings)))),
            _SettingsRow(title: 'Ratings & Logos', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RatingsScreen(settings: settings)))),
            _SettingsRow(title: 'About', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
          ],
        ),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.title, this.subtitle, required this.onTap});
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            title: Text(title, style: const TextStyle(fontSize: 16)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(subtitle!, style: const TextStyle(color: Color(0xFFA5A7AC)))),
                const Icon(Icons.chevron_right, color: Color(0xFFA5A7AC)),
              ],
            ),
            onTap: onTap,
          ),
          const Divider(height: 1, color: Color(0xFF1B1D22), indent: 20),
        ],
      );
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.session, required this.settings});
  final JellyfinSession session;
  final SettingsController settings;

  Future<void> _signOut(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('serverUrl');
    await prefs.remove('userId');
    await prefs.remove('accessToken');
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => AuthenticationScreen(settings: settings)), (route) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ACCOUNT', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: ListView(
          children: [
            _InfoRow(label: 'Username', value: session.username),
            _InfoRow(label: 'Server', value: session.serverUrl),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF8A80), side: const BorderSide(color: Color(0xFFFF8A80))),
                  onPressed: () => _signOut(context),
                  child: const Text('Sign Out'),
                ),
              ),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            title: Text(label, style: const TextStyle(fontSize: 16)),
            trailing: Text(value, style: const TextStyle(color: Color(0xFFA5A7AC))),
          ),
          const Divider(height: 1, color: Color(0xFF1B1D22), indent: 20),
        ],
      );
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('APPEARANCE', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Theme Color', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Choose the accent color used throughout the app.', style: TextStyle(color: Color(0xFFA5A7AC))),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: settings,
              builder: (context, _) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final option in accentColorOptions)
                    _ColorSwatch(
                      option: option,
                      selected: settings.accentColor.toARGB32() == option.color.toARGB32(),
                      onTap: () => settings.setAccentColor(option.color),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.option, required this.selected, required this.onTap});
  final AccentColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: option.color,
                shape: BoxShape.circle,
                border: selected ? Border.all(color: Colors.white, width: 3) : null,
              ),
              child: selected ? const Icon(Icons.check, color: Colors.white) : null,
            ),
            const SizedBox(height: 8),
            Text(option.name, style: const TextStyle(fontSize: 12, color: Color(0xFFA5A7AC))),
          ],
        ),
      );
}

class PlaybackScreen extends StatelessWidget {
  const PlaybackScreen({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('PLAYBACK', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text('Skip Interval', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final seconds in skipIntervalOptions)
                RadioListTile<int>(
                  value: seconds,
                  groupValue: settings.skipSeconds,
                  title: Text('$seconds seconds'),
                  onChanged: (value) {
                    if (value != null) settings.setSkipSeconds(value);
                  },
                ),
              const Divider(color: Color(0xFF1B1D22)),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text('Default Quality', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Used when a new video starts playing. Lower this if playback lags on a slow connection.', style: TextStyle(color: Color(0xFFA5A7AC))),
              ),
              for (final quality in defaultQualityOptions)
                RadioListTile<String>(
                  value: quality,
                  groupValue: settings.defaultQuality,
                  title: Text(quality.qualityLabel),
                  onChanged: (value) {
                    if (value != null) settings.setDefaultQuality(value);
                  },
                ),
            ],
          ),
        ),
      );
}

class RatingsScreen extends StatefulWidget {
  const RatingsScreen({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  late final _omdbController = TextEditingController(text: widget.settings.omdbApiKey);
  late final _tmdbController = TextEditingController(text: widget.settings.tmdbApiKey);

  @override
  void dispose() {
    _omdbController.dispose();
    _tmdbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('RATINGS & LOGOS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('IMDb Ratings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Jellyfin\'s own rating is whatever its metadata provider set — usually TheTVDB for TV shows or TMDB for movies. '
              'To also show a real IMDb rating, get a free API key at omdbapi.com and paste it here.',
              style: TextStyle(color: Color(0xFFA5A7AC)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _omdbController,
              decoration: const InputDecoration(labelText: 'OMDB API Key', border: OutlineInputBorder()),
              onSubmitted: (value) => widget.settings.setOmdbApiKey(value.trim()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                widget.settings.setOmdbApiKey(_omdbController.text.trim());
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
              },
              child: const Text('Save'),
            ),
            const SizedBox(height: 32),
            const Text('Network Logos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'The Networks screen and home banner show a real Netflix/Apple TV/etc. logo when one is available, fetched live from '
              'themoviedb.org. Get a free API key at themoviedb.org/settings/api and paste it here.',
              style: TextStyle(color: Color(0xFFA5A7AC)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tmdbController,
              decoration: const InputDecoration(labelText: 'TMDB API Key', border: OutlineInputBorder()),
              onSubmitted: (value) => widget.settings.setTmdbApiKey(value.trim()),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                widget.settings.setTmdbApiKey(_tmdbController.text.trim());
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ABOUT', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Black Theatre', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('Version 1.0.0', style: TextStyle(color: Color(0xFFA5A7AC))),
            SizedBox(height: 16),
            Text('A personal Jellyfin client.', style: TextStyle(color: Color(0xFFA5A7AC))),
          ]),
        ),
      );
}

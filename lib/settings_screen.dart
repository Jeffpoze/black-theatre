import 'package:flutter/material.dart';

import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SETTINGS', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.8))),
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

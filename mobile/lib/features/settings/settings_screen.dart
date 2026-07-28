import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/theme_controller.dart';
import '../sync/background_sync.dart';
import 'settings_repository.dart';

const _githubUrl = 'https://github.com/JRedrupp/deepread';

const _frequencyPresets = [
  (minutes: 15, label: '15 min'),
  (minutes: 30, label: '30 min'),
  (minutes: 60, label: '1 hour'),
  (minutes: 180, label: '3 hours'),
];

const _themeModePresets = [
  (mode: ThemeMode.dark, label: 'Dark'),
  (mode: ThemeMode.light, label: 'Light'),
  (mode: ThemeMode.system, label: 'System'),
];

/// Fixed, deterministic absolute-time format (not relative — "5 minutes
/// ago" would make widget tests time-dependent for no real benefit here).
String formatLastSynced(DateTime? time) {
  if (time == null) return 'Never';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

typedef SyncSettingsChanged = Future<void> Function({required int frequencyMinutes, required bool wifiOnly});

Future<void> _defaultOnSyncSettingsChanged({required int frequencyMinutes, required bool wifiOnly}) {
  return BackgroundSync.register(frequencyMinutes: frequencyMinutes, wifiOnly: wifiOnly);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onSignOut,
    this.settingsRepository,
    this.onSyncSettingsChanged = _defaultOnSyncSettingsChanged,
  });

  final Future<void> Function() onSignOut;

  /// Overridable so widget tests can supply a repository backed by
  /// [SharedPreferences.setMockInitialValues] instead of the real plugin.
  final SettingsRepository? settingsRepository;

  /// Called after a sync setting is persisted, to re-register the
  /// background task with the new frequency/constraints. Overridable so
  /// widget tests don't have to touch the real Workmanager platform channel.
  final SyncSettingsChanged onSyncSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsRepository? _settings;
  DateTime? _lastSyncedAt;
  int _frequencyMinutes = 15;
  bool _wifiOnlySync = false;
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = widget.settingsRepository ?? await SettingsRepository.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _lastSyncedAt = settings.lastSyncedAt;
      _frequencyMinutes = settings.refreshFrequencyMinutes;
      _wifiOnlySync = settings.wifiOnlySync;
      _themeMode = settings.themeMode;
    });
  }

  Future<void> _updateThemeMode(ThemeMode mode) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setThemeMode(mode);
    setState(() => _themeMode = mode);
    ThemeController.mode.value = mode;
  }

  Future<void> _updateFrequency(int minutes) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setRefreshFrequencyMinutes(minutes);
    setState(() => _frequencyMinutes = minutes);
    await widget.onSyncSettingsChanged(frequencyMinutes: minutes, wifiOnly: _wifiOnlySync);
  }

  Future<void> _updateWifiOnly(bool wifiOnly) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setWifiOnlySync(wifiOnly);
    setState(() => _wifiOnlySync = wifiOnly);
    await widget.onSyncSettingsChanged(frequencyMinutes: _frequencyMinutes, wifiOnly: wifiOnly);
  }

  Future<void> _handleSignOut() async {
    await widget.onSignOut();
    // AuthGate (below every pushed route, at the Navigator's root) only
    // re-renders itself in reaction to the auth-state change — it can't
    // reach up and pop routes pushed on top of it. Without this, the user
    // would be stranded looking at this screen after signing out.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final captionStyle = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Sync'),
          ListTile(
            title: const Text('Last synced'),
            subtitle: Text(formatLastSynced(_lastSyncedAt)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Background refresh frequency'),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [
                    for (final preset in _frequencyPresets)
                      ButtonSegment(value: preset.minutes, label: Text(preset.label)),
                  ],
                  selected: {_frequencyMinutes},
                  onSelectionChanged: (selected) => _updateFrequency(selected.first),
                ),
                const SizedBox(height: 6),
                Text(
                  "If background sync never seems to run, check this app's battery settings — "
                  'some manufacturers block background work regardless of this setting.',
                  style: captionStyle,
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Wifi-only sync'),
            subtitle: Text(
              'Applies to background sync only — manual sync always uses whatever network is available.',
              style: captionStyle,
            ),
            value: _wifiOnlySync,
            onChanged: _updateWifiOnly,
          ),
          const Divider(height: 1),
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Theme'),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    for (final preset in _themeModePresets) ButtonSegment(value: preset.mode, label: Text(preset.label)),
                  ],
                  selected: {_themeMode},
                  onSelectionChanged: (selected) => _updateThemeMode(selected.first),
                ),
                const SizedBox(height: 6),
                Text(
                  "Only re-themes the app itself — downloaded articles keep their existing dark "
                  'styling in the reader regardless of this setting.',
                  style: captionStyle,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: _handleSignOut,
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('View on GitHub'),
            onTap: () => launchUrl(Uri.parse(_githubUrl)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/local/database.dart';
import '../../theme/theme_controller.dart';
import '../sync/background_sync.dart';
import '../sync/retention_service.dart';
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

const _expireDaysPresets = [
  (days: null, label: 'Off'),
  (days: 7, label: '7 days'),
  (days: 30, label: '30 days'),
  (days: 90, label: '90 days'),
];

const _capPerFeedPresets = [
  (cap: null, label: 'Off'),
  (cap: 20, label: '20'),
  (cap: 50, label: '50'),
  (cap: 100, label: '100'),
];

/// Fixed, deterministic absolute-time format (not relative — "5 minutes
/// ago" would make widget tests time-dependent for no real benefit here).
String formatLastSynced(DateTime? time) {
  if (time == null) return 'Never';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
  if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / gb).toStringAsFixed(2)} GB';
}

typedef SyncSettingsChanged = Future<void> Function({required int frequencyMinutes, required bool wifiOnly});

Future<void> _defaultOnSyncSettingsChanged({required int frequencyMinutes, required bool wifiOnly}) {
  return BackgroundSync.register(frequencyMinutes: frequencyMinutes, wifiOnly: wifiOnly);
}

Future<RetentionService> _buildRetentionService(AppDatabase db) async {
  final docsDir = await getApplicationDocumentsDirectory();
  return RetentionService(db, articlesDir: Directory(p.join(docsDir.path, 'articles')));
}

Future<int> _defaultComputeStorageBytes(AppDatabase db) async {
  final retention = await _buildRetentionService(db);
  return retention.computeStorageBytes();
}

Future<void> _defaultOnClearDownloaded(AppDatabase db) async {
  final retention = await _buildRetentionService(db);
  await retention.clearAllDownloaded();
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onSignOut,
    required this.db,
    this.settingsRepository,
    this.onSyncSettingsChanged = _defaultOnSyncSettingsChanged,
    this.computeStorageBytes = _defaultComputeStorageBytes,
    this.onClearDownloaded = _defaultOnClearDownloaded,
  });

  final Future<void> Function() onSignOut;

  final AppDatabase db;

  /// Overridable so widget tests can supply a repository backed by
  /// [SharedPreferences.setMockInitialValues] instead of the real plugin.
  final SettingsRepository? settingsRepository;

  /// Called after a sync setting is persisted, to re-register the
  /// background task with the new frequency/constraints. Overridable so
  /// widget tests don't have to touch the real Workmanager platform channel.
  final SyncSettingsChanged onSyncSettingsChanged;

  /// Overridable so widget tests can supply a fast fake instead of touching
  /// real dart:io directory listing (real file I/O doesn't reliably
  /// complete under testWidgets'/pumpAndSettle's fake-async zone without
  /// `tester.runAsync` — the actual eviction/byte-counting logic is tested
  /// directly in retention_service_test.dart instead).
  final Future<int> Function(AppDatabase db) computeStorageBytes;
  final Future<void> Function(AppDatabase db) onClearDownloaded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsRepository? _settings;
  DateTime? _lastSyncedAt;
  int _frequencyMinutes = 15;
  bool _wifiOnlySync = false;
  ThemeMode _themeMode = ThemeMode.dark;
  int? _retentionExpireDays;
  int? _retentionCapPerFeed;
  int? _storageBytes;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = widget.settingsRepository ?? await SettingsRepository.load();
    final bytes = await widget.computeStorageBytes(widget.db);
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _lastSyncedAt = settings.lastSyncedAt;
      _frequencyMinutes = settings.refreshFrequencyMinutes;
      _wifiOnlySync = settings.wifiOnlySync;
      _themeMode = settings.themeMode;
      _retentionExpireDays = settings.retentionExpireReadAfterDays;
      _retentionCapPerFeed = settings.retentionCapPerFeed;
      _storageBytes = bytes;
    });
  }

  Future<void> _updateRetentionExpireDays(int? days) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setRetentionExpireReadAfterDays(days);
    setState(() => _retentionExpireDays = days);
  }

  Future<void> _updateRetentionCapPerFeed(int? cap) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setRetentionCapPerFeed(cap);
    setState(() => _retentionCapPerFeed = cap);
  }

  Future<void> _confirmAndClearDownloaded() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear downloaded articles?'),
        content: const Text(
          "This frees device storage but won't undo automatically — articles are only "
          're-downloaded when the source republishes or re-renders them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onClearDownloaded(widget.db);
    final bytes = await widget.computeStorageBytes(widget.db);
    if (mounted) setState(() => _storageBytes = bytes);
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
          const _SectionHeader('Storage'),
          ListTile(
            title: const Text('Storage used'),
            subtitle: Text(_storageBytes == null ? 'Calculating…' : formatBytes(_storageBytes!)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Auto-expire read articles after'),
                const SizedBox(height: 8),
                SegmentedButton<int?>(
                  key: const Key('retention-expire-segmented'),
                  segments: [
                    for (final preset in _expireDaysPresets) ButtonSegment(value: preset.days, label: Text(preset.label)),
                  ],
                  selected: {_retentionExpireDays},
                  onSelectionChanged: (selected) => _updateRetentionExpireDays(selected.first),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cap articles kept per feed'),
                const SizedBox(height: 8),
                SegmentedButton<int?>(
                  key: const Key('retention-cap-segmented'),
                  segments: [
                    for (final preset in _capPerFeedPresets) ButtonSegment(value: preset.cap, label: Text(preset.label)),
                  ],
                  selected: {_retentionCapPerFeed},
                  onSelectionChanged: (selected) => _updateRetentionCapPerFeed(selected.first),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Clear downloaded articles'),
            onTap: _confirmAndClearDownloaded,
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

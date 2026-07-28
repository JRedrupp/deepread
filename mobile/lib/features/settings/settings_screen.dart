import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings_repository.dart';

const _githubUrl = 'https://github.com/JRedrupp/deepread';

/// Fixed, deterministic absolute-time format (not relative — "5 minutes
/// ago" would make widget tests time-dependent for no real benefit here).
String formatLastSynced(DateTime? time) {
  if (time == null) return 'Never';
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onSignOut, this.settingsRepository});

  final Future<void> Function() onSignOut;

  /// Overridable so widget tests can supply a repository backed by
  /// [SharedPreferences.setMockInitialValues] instead of the real plugin.
  final SettingsRepository? settingsRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  DateTime? _lastSyncedAt;

  @override
  void initState() {
    super.initState();
    _loadLastSynced();
  }

  Future<void> _loadLastSynced() async {
    final settings = widget.settingsRepository ?? await SettingsRepository.load();
    if (!mounted) return;
    setState(() => _lastSyncedAt = settings.lastSyncedAt);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Last synced'),
            subtitle: Text(formatLastSynced(_lastSyncedAt)),
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

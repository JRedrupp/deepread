import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around app-wide Supabase config.
///
/// URL and anon key are read from --dart-define at build time, e.g.:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Never hardcode these values here.
class AppSupabase {
  AppSupabase._();

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, publishableKey: _publishableKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}

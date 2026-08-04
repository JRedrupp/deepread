import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Swaps between the login screen and the app itself based on Supabase
/// auth state — the single source of truth for "is someone signed in",
/// no separate local flag to keep in sync.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AppSupabase.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = AppSupabase.client.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return HomeShell(db: db);
      },
    );
  }
}

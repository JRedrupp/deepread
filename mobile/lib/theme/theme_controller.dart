import 'package:flutter/material.dart';

/// App-wide current theme mode. A simple static [ValueNotifier] rather than
/// threading state through every screen's constructor down to
/// SettingsScreen — matches the app's existing no-DI-framework style (see
/// TECH_DEBT.md's note on riverpod being unused). `main.dart` seeds this
/// from [SettingsRepository.themeMode] at startup and wraps [MaterialApp] in
/// a [ValueListenableBuilder] listening to it.
class ThemeController {
  ThemeController._();

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.dark);
}

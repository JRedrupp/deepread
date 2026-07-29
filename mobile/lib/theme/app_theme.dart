import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dev-tool inspired theme: dark by default, monospace for metadata,
/// sans-serif for titles/chrome, subtle borders instead of shadows. `light()`
/// mirrors the same look with light surfaces — note the actual downloaded
/// article content shown in the reader's WebView is unaffected by either
/// theme: its CSS is baked in server-side at render time (see CLAUDE.md).
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF10151C);
  static const Color surface = Color(0xFF161C25);
  static const Color border = Color(0xFF262E3A);
  static const Color accent = Color(0xFF4FD1B5);
  static const Color textPrimary = Color(0xFFE6E8EB);
  static const Color textSecondary = Color(0xFF8A94A3);

  static const Color lightBackground = Color(0xFFF5F7FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFD8DEE6);
  static const Color lightTextPrimary = Color(0xFF1A2027);
  static const Color lightTextSecondary = Color(0xFF5B6472);

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        onPrimary: Color(0xFF06201A),
        onSurface: textPrimary,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        surface: lightSurface,
        primary: accent,
        onPrimary: Color(0xFF06201A),
        onSurface: lightTextPrimary,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1),
      textTheme: base.textTheme.apply(
        bodyColor: lightTextPrimary,
        displayColor: lightTextPrimary,
      ),
    );
  }

  /// Terminal-readout style text for metadata: timestamps, domains,
  /// sync status, byte sizes. Kept visually distinct from body/title text.
  /// Needs [context] to pick the right default color under whichever
  /// theme (dark/light) is currently active.
  static TextStyle metadataStyle(BuildContext context, {Color? color, double fontSize = 12}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color ?? (isDark ? textSecondary : lightTextSecondary),
      letterSpacing: 0.2,
    );
  }
}

/// A small bracket-tag status badge, e.g. `[NEW]`, `[SYNCED]`, `[FAILED]`.
class StatusTag extends StatelessWidget {
  const StatusTag(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tagColor = color ?? AppTheme.accent;
    return Text(
      '[$label]',
      style: AppTheme.metadataStyle(context, color: tagColor, fontSize: 11),
    );
  }
}

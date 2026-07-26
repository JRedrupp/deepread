import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dev-tool inspired theme: dark by default, monospace for metadata,
/// sans-serif for titles/chrome, subtle borders instead of shadows.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF10151C);
  static const Color surface = Color(0xFF161C25);
  static const Color border = Color(0xFF262E3A);
  static const Color accent = Color(0xFF4FD1B5);
  static const Color textPrimary = Color(0xFFE6E8EB);
  static const Color textSecondary = Color(0xFF8A94A3);

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

  /// Terminal-readout style text for metadata: timestamps, domains,
  /// sync status, byte sizes. Kept visually distinct from body/title text.
  static TextStyle metadataStyle({Color? color, double fontSize = 12}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      color: color ?? textSecondary,
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
      style: AppTheme.metadataStyle(color: tagColor, fontSize: 11),
    );
  }
}

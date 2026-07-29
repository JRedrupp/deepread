import 'package:deepread/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark() and light() produce distinct ThemeData for their brightness', () {
    final dark = AppTheme.dark();
    final light = AppTheme.light();

    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
  });

  testWidgets('metadataStyle defaults to the dark text-secondary color under a dark theme', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            style = AppTheme.metadataStyle(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(style.color, AppTheme.textSecondary);
  });

  testWidgets('metadataStyle defaults to the light text-secondary color under a light theme', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            style = AppTheme.metadataStyle(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(style.color, AppTheme.lightTextSecondary);
  });

  testWidgets('metadataStyle honors an explicit color override regardless of brightness', (tester) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            style = AppTheme.metadataStyle(context, color: AppTheme.accent);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(style.color, AppTheme.accent);
  });
}

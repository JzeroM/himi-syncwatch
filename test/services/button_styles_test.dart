import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/ui/button_styles.dart';

void main() {
  group('readableFilledButtonStyle', () {
    test('底色为 primary，前景为规范配对的 onPrimary', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1),
        brightness: Brightness.dark,
      );
      final style = readableFilledButtonStyle(scheme);

      expect(style.backgroundColor?.resolve(const <WidgetState>{}),
          scheme.primary);
      expect(style.foregroundColor?.resolve(const <WidgetState>{}),
          scheme.onPrimary);
    });

    test('亮色 primary 下前景为深色（白字问题不再出现）', () {
      const lightPrimary = Color(0xFFB2DFDB);
      const scheme = ColorScheme(
        brightness: Brightness.dark,
        primary: lightPrimary,
        onPrimary: Colors.black,
        // 其余字段用默认值填充以保持 const
        secondary: Color(0xFF03DAC6),
        onSecondary: Colors.black,
        error: Color(0xFFB00020),
        onError: Colors.white,
        surface: Color(0xFF1C1B1F),
        onSurface: Colors.white,
      );
      final style = readableFilledButtonStyle(scheme);
      final fg = style.foregroundColor?.resolve(const <WidgetState>{});

      expect(fg, isNotNull);
      expect(ThemeData.estimateBrightnessForColor(fg!), Brightness.dark);
    });
  });
}

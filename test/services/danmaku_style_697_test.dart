import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

/// P3：弹幕颜色模式与描边样式。
///
/// 语义（四端必须一致）：
/// - `colorMode`：`color`（源色，默认）/ `white`（统一白）/ `custom`；
/// - `outlineWidth`：0~4，0 表示关闭描边；
/// - 非法存档值必须回落默认，不能把面板弄崩。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('1. 默认值与钳制', () {
    test('1.1 默认：源色 + 描边 1.0', () {
      const s = AppSettings();
      expect(s.danmakuColorMode, 'color');
      expect(s.danmakuCustomColor, 0xFFFFFFFF);
      expect(s.danmakuOutlineWidth, 1.0);
      expect(s.danmakuOutlineColor, 0xFF000000);
    });

    test('1.2 非法颜色模式回落 color', () {
      final s = AppSettings.fromJson(
        jsonDecode(jsonEncode({'danmakuColorMode': 'rainbow'}))
            as Map<String, dynamic>,
      );
      expect(s.danmakuColorMode, 'color');
    });

    test('1.3 描边宽度钳到 0~4', () {
      final lo = AppSettings.fromJson(
        jsonDecode(jsonEncode({'danmakuOutlineWidth': -3}))
            as Map<String, dynamic>,
      );
      expect(lo.danmakuOutlineWidth, AppSettings.danmakuOutlineWidthMin);

      final hi = AppSettings.fromJson(
        jsonDecode(jsonEncode({'danmakuOutlineWidth': 99}))
            as Map<String, dynamic>,
      );
      expect(hi.danmakuOutlineWidth, AppSettings.danmakuOutlineWidthMax);
    });
  });

  group('2. 序列化往返', () {
    test('2.1 toJson/fromJson 保留全部样式字段', () {
      final s = const AppSettings().copyWith(
        danmakuColorMode: 'custom',
        danmakuCustomColor: 0xFFFFD54F,
        danmakuOutlineWidth: 2.5,
        danmakuOutlineColor: 0xFF102030,
      );
      final round = AppSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(round.danmakuColorMode, 'custom');
      expect(round.danmakuCustomColor, 0xFFFFD54F);
      expect(round.danmakuOutlineWidth, 2.5);
      expect(round.danmakuOutlineColor, 0xFF102030);
    });
  });

  group('3. 四端渲染器接线（结构）', () {
    test('3.1 Flutter 渲染器按模式取色 + 描边', () {
      final f = read('lib/screens/player/widgets/danmaku_overlay.dart');
      expect(f, contains('switch (widget.colorMode)'));
      expect(f, contains("'white' =>"));
      expect(f, contains('widget.outlineWidth'));
      expect(f, contains('widget.outlineColor'));
    });

    test('3.2 安卓渲染器有 setStyle 且生效', () {
      final k = read('android/app/src/main/kotlin/com/himi/syncwatch/'
          'nativeplayer/DanmakuLayerView.kt');
      expect(k, contains('fun setStyle('));
      expect(k, contains('effectiveRgb('));
      expect(k, contains('clearShadowLayer()'));
    });

    test('3.3 鸿蒙渲染器按模式取色 + 描边', () {
      final e = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
          'native/DanmakuLayer.ets');
      expect(e, contains('effectiveColor('));
      expect(e, contains('danmakuOutlineWidth'));
      expect(e, contains('argbToCss('));
    });

    test('3.4a QML 颜色属性必须用 var（int 是 32 位有符号，0xFF 开头会溢出）', () {
      final q = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
      expect(q, contains('property var customColor'));
      expect(q, contains('property var outlineColor'));
      expect(q, isNot(contains('property int customColor')));
      expect(q, isNot(contains('property int outlineColor')));
    });

    test('3.4 Qt 渲染器按模式取色 + 描边', () {
      final q = read('native/windows_qt_player/src/qml/DanmakuLayer.qml');
      expect(q, contains('effectiveColor('));
      expect(q, contains('root.outlineWidth > 0'));
      expect(q, contains('root.cssColor(root.outlineColor)'));
    });

    test('3.5 设置页可配置（三模式 + 描边）', () {
      final ui = read('lib/screens/settings/danmaku_config_screen.dart');
      expect(ui, contains("ButtonSegment(value: 'color'"));
      expect(ui, contains("ButtonSegment(value: 'white'"));
      expect(ui, contains("ButtonSegment(value: 'custom'"));
      expect(ui, contains('danmakuOutlineWidthSlider'));
    });
  });

  group('4. 备份白名单', () {
    test('4.1 四个样式字段纳入备份与还原', () {
      final b = read('lib/services/backup/backup_service.dart');
      expect(b, contains("'colorMode': settings.danmakuColorMode"));
      expect(b, contains("'outlineWidth': settings.danmakuOutlineWidth"));
      expect(b, contains("danmakuColorMode: danmaku?['colorMode']"));
    });
  });
}

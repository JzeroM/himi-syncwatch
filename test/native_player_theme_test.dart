import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_theme.dart';

/// 跨语言主题常量一致性：Dart `NativePlayerTheme` 是唯一真相源，
/// Android（Kotlin `NPTheme`）与鸿蒙（ArkTS `NativePlayerPanel.ets`）
/// 必须逐项同值。改动任一端必须同步三端，否则测试失败。
void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/NativePlayerUi.kt',
  ).readAsStringSync();

  final arkts = File(
    'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/NativePlayerPanel.ets',
  ).readAsStringSync();

  /// 从 Kotlin 源码里按名字取 `const val NAME = <值>` 的十六进制字面量。
  int kotlinHex(String name) {
    final m = RegExp('const val $name = (0x[0-9A-Fa-f]+)').firstMatch(kotlin);
    expect(m, isNotNull, reason: 'Kotlin NPTheme 缺少常量 $name');
    return int.parse(m!.group(1)!.substring(2), radix: 16);
  }

  /// 从 Kotlin 源码里按名字取 `const val NAME = <数值>` 的整数。
  int kotlinInt(String name) {
    final m = RegExp('const val $name = ([0-9.]+)').firstMatch(kotlin);
    expect(m, isNotNull, reason: 'Kotlin NPTheme 缺少常量 $name');
    return double.parse(m!.group(1)!).round();
  }

  group('Dart ↔ Android（Kotlin NPTheme）', () {
    test('强调色与灰阶', () {
      expect(kotlinHex('ACCENT'), NativePlayerTheme.accent.toARGB32());
      expect(kotlinHex('ACCENT_SOFT'), NativePlayerTheme.accentSoft.toARGB32());
      expect(kotlinHex('WHITE'), NativePlayerTheme.white.toARGB32());
      expect(kotlinHex('WHITE_70'), NativePlayerTheme.white70.toARGB32());
      expect(kotlinHex('WHITE_54'), NativePlayerTheme.white54.toARGB32());
      expect(kotlinHex('WHITE_38'), NativePlayerTheme.white38.toARGB32());
      expect(kotlinHex('WHITE_24'), NativePlayerTheme.white24.toARGB32());
    });

    test('玻璃/浮层色', () {
      expect(kotlinHex('PANEL_TINT'), NativePlayerTheme.panelTint.toARGB32());
      expect(kotlinHex('FALLBACK_TINT'), NativePlayerTheme.fallbackTint.toARGB32());
      expect(kotlinHex('RIM'), NativePlayerTheme.rim.toARGB32());
      expect(kotlinHex('DECODE_PANEL'), NativePlayerTheme.decodePanel.toARGB32());
      expect(
        kotlinHex('DECODE_CURRENT_TEXT'),
        NativePlayerTheme.decodeCurrentText.toARGB32(),
      );
      expect(kotlinHex('FOCUS_RING'), NativePlayerTheme.focusRing.toARGB32());
      expect(kotlinHex('SHADOW'), NativePlayerTheme.shadow.toARGB32());
    });

    test('圆角', () {
      expect(kotlinInt('RADIUS_PANEL'), NativePlayerTheme.radiusPanel.round());
      expect(kotlinInt('RADIUS_CHIP'), NativePlayerTheme.radiusChip.round());
      expect(kotlinInt('RADIUS_CARD'), NativePlayerTheme.radiusCard.round());
      expect(kotlinInt('RADIUS_DECODE'), NativePlayerTheme.radiusDecode.round());
      expect(kotlinInt('RADIUS_BADGE'), NativePlayerTheme.radiusBadge.round());
    });

    test('顶栏', () {
      expect(kotlinInt('TOP_BAR_HEIGHT'), NativePlayerTheme.topBarHeight.round());
      expect(kotlinInt('TOP_ICON_SIZE'), NativePlayerTheme.topIconSize.round());
      expect(
        kotlinInt('TOP_CHIP_ICON_SIZE'),
        NativePlayerTheme.topChipIconSize.round(),
      );
      expect(kotlinInt('TITLE_SIZE'), NativePlayerTheme.titleSize.round());
      expect(kotlinInt('CAPTION_SIZE'), NativePlayerTheme.captionSize.round());
      expect(kotlinInt('CHIP_PAD_H'), NativePlayerTheme.chipPadH.round());
      expect(kotlinInt('CHIP_PAD_V'), NativePlayerTheme.chipPadV.round());
      expect(kotlinInt('CLOCK_WIDTH'), NativePlayerTheme.clockWidth.round());
      expect(kotlinInt('CLOCK_HEIGHT'), NativePlayerTheme.clockHeight.round());
      expect(kotlinInt('CLOCK_RIGHT'), NativePlayerTheme.clockRight.round());
    });

    test('底栏', () {
      expect(kotlinInt('LOGO_WIDTH'), NativePlayerTheme.logoWidth.round());
      expect(kotlinInt('LOGO_HEIGHT'), NativePlayerTheme.logoHeight.round());
      expect(kotlinInt('TIME_CELL'), NativePlayerTheme.timeCellWidth.round());
      expect(
        kotlinInt('TIME_CELL_WIDE'),
        NativePlayerTheme.timeCellWidthWide.round(),
      );
      expect(kotlinInt('SEEK_TRACK'), NativePlayerTheme.seekTrackHeight.round());
      expect(kotlinInt('SEEK_THUMB'), NativePlayerTheme.seekThumbRadius.round());
      expect(
        kotlinInt('TRANSPORT_SIDE'),
        NativePlayerTheme.transportSideSize.round(),
      );
      expect(
        kotlinInt('TRANSPORT_PLAY'),
        NativePlayerTheme.transportPlaySize.round(),
      );
      expect(kotlinInt('TRANSPORT_GAP'), NativePlayerTheme.transportGap.round());
      expect(
        kotlinInt('CONTROL_ICON'),
        NativePlayerTheme.controlIconSize.round(),
      );
      expect(kotlinInt('CONTROL_GAP'), NativePlayerTheme.controlGap.round());
      expect(kotlinInt('BADGE_MIN'), NativePlayerTheme.badgeMinSize.round());
      expect(kotlinInt('LOCK_ICON'), NativePlayerTheme.lockIconSize.round());
    });

    test('面板', () {
      expect(kotlinInt('PANEL_RIGHT'), NativePlayerTheme.panelRight.round());
      expect(
        kotlinInt('PANEL_TOP_OFFSET'),
        NativePlayerTheme.panelTopOffset.round(),
      );
      expect(
        kotlinInt('PANEL_BOTTOM_OFFSET'),
        NativePlayerTheme.panelBottomOffset.round(),
      );
      expect(kotlinInt('PANEL_PAD_H'), NativePlayerTheme.panelPadH.round());
      expect(kotlinInt('PANEL_PAD_V'), NativePlayerTheme.panelPadV.round());
      expect(kotlinInt('PANEL_CHECK_SLOT'), NativePlayerTheme.panelCheckSlot.round());
      expect(
        kotlinInt('ADJUST_LABEL_WIDTH'),
        NativePlayerTheme.adjustLabelWidth.round(),
      );
      expect(
        kotlinInt('ADJUST_VALUE_WIDTH'),
        NativePlayerTheme.adjustValueWidth.round(),
      );
      expect(
        kotlinInt('ADJUST_ROW_PAD_V'),
        NativePlayerTheme.adjustRowPadV.round(),
      );
      expect(
        kotlinInt('DECODE_PANEL_WIDTH'),
        NativePlayerTheme.decodePanelWidth.round(),
      );
      expect(
        kotlinInt('SEGMENT_CARD_WIDTH'),
        NativePlayerTheme.segmentCardWidth.round(),
      );
      expect(
        kotlinInt('SEGMENT_ROW_ICON'),
        NativePlayerTheme.segmentRowIconSize.round(),
      );
      expect(
        kotlinInt('SEGMENT_CHEVRON'),
        NativePlayerTheme.segmentChevronSize.round(),
      );
      expect(kotlinInt('AUTO_HIDE_MS'), NativePlayerTheme.autoHideMs);
    });

    test('面板宽度夹取比例与边界一致', () {
      // Dart 侧 panelWidthRatio/min/max 是唯一来源，Kotlin 用 dp 计算。
      expect(NativePlayerTheme.panelWidthRatio, closeTo(0.42, 1e-9));
      expect(NativePlayerTheme.panelMinWidth, 260);
      expect(NativePlayerTheme.panelMaxWidth, 320);
      expect(kotlin.contains('0.42f'), isTrue,
          reason: 'Kotlin 面板宽度比例需与 Dart panelWidthRatio 一致');
    });
  });

  group('Dart ↔ 鸿蒙（ArkTS NativePlayerPanel）', () {
    test('选中主色/着色/圆角/内边距', () {
      expect(arkts.contains('#6366F1'), isTrue,
          reason: '鸿蒙选中主色需与 Dart accent 一致');
      expect(arkts.contains('#1F1A1D23'), isTrue,
          reason: '鸿蒙面板着色需与 Dart panelTint 一致');
      expect(RegExp(r'\.borderRadius\(16\)').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板圆角需与 Dart radiusPanel 一致');
      expect(RegExp(r'\.width\(320\)').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板宽需与 Dart panelMaxWidth 一致');
      expect(RegExp(r'right: 12').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板右距需与 Dart panelRight 一致');
      expect(RegExp(r'top: 48').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板上距需与 Dart panelTopOffset 一致');
      expect(RegExp(r'bottom: 116').hasMatch(arkts), isTrue,
          reason: '鸿蒙面板下距需与 Dart panelBottomOffset 一致');
      expect(RegExp(r'left: 16, right: 16, top: 10, bottom: 4').hasMatch(arkts),
          isTrue,
          reason: '鸿蒙面板标题内边距需与 Flutter SelectorSidePanel 一致');
    });

    test('倍速档位与 Dart 侧一致', () {
      expect(
        arkts.contains('[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]'),
        isTrue,
        reason: '鸿蒙倍速档位需与 Flutter SpeedMenuPanel 一致',
      );
    });

    test('选项行对勾槽宽 18', () {
      expect(RegExp(r'\.width\(18\)').hasMatch(arkts), isTrue,
          reason: '鸿蒙对勾槽宽需与 Dart panelCheckSlot 一致');
    });

    test('解码模式当前值颜色与 Dart 一致', () {
      expect(arkts.contains('#A5B4FC'), isTrue,
          reason: '鸿蒙解码当前值颜色需与 Dart decodeCurrentText 一致');
    });
  });
}

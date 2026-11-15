import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 694：Windows DPI 缩放下「Qt 逻辑像素 ↔ Win32 物理像素」交界审计。
///
/// 真机回归（Win11 125%/150%）：控件层放大偏移飘出宿主、视频避让错位
/// ——根因是 Win32 API（物理 px）与 QWindow::setGeometry（逻辑 px）混用
/// 不换算 dpr。100% 缩放两者相等（Win10 侥幸正确），>100% 必乱。
void main() {
  late String mainCpp;
  late String mpvCpp;
  late String mpvH;

  setUpAll(() {
    mainCpp = File('native/windows_qt_player/src/main.cpp').readAsStringSync();
    mpvCpp =
        File('native/windows_qt_player/src/mpv_window.cpp').readAsStringSync();
    mpvH = File('native/windows_qt_player/src/mpv_window.h').readAsStringSync();
  });

  group('1. 控件层贴附（syncOverlayGeometry）', () {
    test('1.1 物理 → 逻辑换算（÷dpr + qRound）', () {
      final start = mainCpp.indexOf('const auto syncOverlayGeometry');
      expect(start, greaterThan(0));
      final block = mainCpp.substring(start, start + 1200);
      expect(block, contains('devicePixelRatio'));
      expect(block, contains('qRound(rc.left / dpr)'));
      expect(block, contains('qRound((rc.right - rc.left) / dpr)'));
    });

    test('1.2 创建日志带 dpr（真机截图即诊断）', () {
      expect(mainCpp, contains('"dpr=" << overlayDpr'));
    });
  });

  group('2. 视频子窗 inset 单位换算', () {
    test('2.1 insetToPx（逻辑 vp → 物理 px）存在', () {
      expect(mpvCpp, contains('int MpvWindow::insetToPx(int logical) const'));
      expect(mpvCpp, contains('qRound(logical * dpr)'));
      expect(mpvH, contains('int insetToPx(int logical) const;'));
    });

    test('2.2 createVideoWindow / syncGeometry 均经换算', () {
      final create = mpvCpp.substring(
        mpvCpp.indexOf('void MpvWindow::createVideoWindow'),
        mpvCpp.indexOf('void MpvWindow::syncGeometry'),
      );
      expect(create, contains('insetToPx(insetTop_)'));
      expect(create, contains('insetToPx(insetBottom_)'));
      final sync = mpvCpp.substring(
        mpvCpp.indexOf('void MpvWindow::syncGeometry'),
        mpvCpp.indexOf('void MpvWindow::setOverlayInsets'),
      );
      expect(sync, contains('insetToPx(insetTop_)'));
      expect(sync, contains('insetToPx(insetBottom_)'));
    });

    test('2.3 字段单位注释（逻辑 vp）', () {
      expect(mpvH, contains('单位**逻辑 vp**'));
    });
  });

  group('3. 正确对照组不被破坏', () {
    test('3.1 followParentOnce 的物理 → 逻辑换算仍在', () {
      final start = mpvCpp.indexOf('void MpvWindow::followParentOnce');
      expect(start, greaterThan(0));
      final block = mpvCpp.substring(start, start + 2600);
      expect(block, contains('parentPhysical.x() / dpr'));
      expect(block, contains('devicePixelRatio'));
    });
  });
}

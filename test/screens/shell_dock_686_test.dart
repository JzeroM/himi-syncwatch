import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 686：Windows 桌面侧边导航改为**垂直 Dock**（方案 C）+ Esc 完全禁用。
///
/// ## 侧边栏为什么改
///
/// 旧实现是「可折叠抽屉 + 每项之间横线分隔 + 选中淡白底」：
///   - 5 个导航项之间各插 `Divider`，像系统菜单
///   - 选中态 `0x33FFFFFF` 在深色渐变上几乎看不出来
///   - 与底部胶囊导航的「水珠 + 玻璃胶囊」语言完全割裂
///
/// 新实现：每个导航项是独立玻璃方块（类 macOS Dock 竖立左侧）
///   - 收起 72px（只有图标）/ 展开 200px（图标 + 文字）
///   - 选中：放大 + 主色外发光 + 右侧 3px 竖条
///   - 悬停：整块右移 + 提亮；收起态出 tooltip
///
/// ## Esc 为什么禁用
///
/// 677 的 EscapeFilter 有三层语义（收面板 → 退全屏 → requestExit +
/// Qt.quit()）。真机反馈两个问题：
///   - 房间模式按 Esc 弹「解散/离开房间」确认，不符合预期
///   - 单人模式 `if (!playerState.isRoom) Qt.quit()` 本地立即关窗，
///     与同时发出的 `requestExit` 竞争（Dart 单人分支也没有处理）
///
/// 用户明确要求「Esc 不做任何动作」→ 整个过滤器与信号链删除。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String sideDrawer;
  late String mainCpp;
  late String mpvH;
  late String overlayQml;
  late String mainQml;
  late String shortcutsQml;

  setUpAll(() {
    sideDrawer = read('lib/screens/shell/shell_side_drawer.dart');
    mainCpp = read('native/windows_qt_player/src/main.cpp');
    mpvH = read('native/windows_qt_player/src/mpv_window.h');
    overlayQml = read('native/windows_qt_player/src/qml/Overlay.qml');
    mainQml = read('native/windows_qt_player/src/qml/Main.qml');
    shortcutsQml = read('native/windows_qt_player/src/qml/PlayerShortcuts.qml');
  });

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  // ═══════════════════════════════════════════════════════════════
  // A. Esc 完全禁用
  // ═══════════════════════════════════════════════════════════════

  group('A Esc 完全禁用', () {
    test('A1 C++ 不再安装 EscapeFilter', () {
      final code = codeOnly(mainCpp);
      expect(code, isNot(contains('EscapeFilter')));
      expect(code, isNot(contains('installEventFilter')));
      expect(code, isNot(contains('Qt::Key_Escape')));
      expect(code, isNot(contains('notifyEscape')));
    });

    test('A2 MpvWindow 不再有 escapePressed / notifyEscape', () {
      final code = codeOnly(mpvH);
      expect(code, isNot(contains('escapePressed')));
      expect(code, isNot(contains('notifyEscape')));
    });

    test('A3 Overlay.qml 不再连接 onEscapePressed', () {
      final code = codeOnly(overlayQml);
      expect(code, isNot(contains('onEscapePressed')));
    });

    test('A4 两窗 QML 都没有 Escape Shortcut', () {
      expect(codeOnly(mainQml), isNot(contains('sequence: "Escape"')));
      expect(codeOnly(shortcutsQml), isNot(contains('sequence: "Escape"')));
    });

    test('A5 Esc 不再触发退出（无 requestExit 绑在 Esc 上）', () {
      // 整个 Overlay 的 Esc 分支已删除，requestExit 只剩其它入口
      expect(codeOnly(overlayQml), isNot(contains('Qt.quit()')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. Dock 尺寸与结构
  // ═══════════════════════════════════════════════════════════════

  group('B 垂直 Dock 尺寸', () {
    test('B1 收起 72 / 展开 200', () {
      expect(sideDrawer, contains('static const double _railWidth = 72'));
      expect(sideDrawer, contains('static const double _expandedWidth = 200'));
    });

    test('B2 图标块 48×48、圆角 14', () {
      expect(sideDrawer, contains('static const double _tileSize = 48'));
      expect(sideDrawer, contains('static const double _tileRadius = 14'));
    });

    test('B3 宽度按动画插值（72 → 200）', () {
      expect(sideDrawer,
          contains('_railWidth + (_expandedWidth - _railWidth) * curve'));
    });

    test('B4 不再用 240 宽抽屉', () {
      expect(sideDrawer, isNot(contains('_panelWidth')));
      expect(sideDrawer, isNot(contains('240')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. Dock 视觉语言
  // ═══════════════════════════════════════════════════════════════

  group('C Dock 视觉（液态玻璃）', () {
    test('C1 687：选中态主色渐变玻璃 + 外发光 + 内高光', () {
      // 687 从「淡色底 + 细描边」升级为「主色渐变 + 外发光 + 顶部内高光」
      expect(sideDrawer, contains('LinearGradient('));
      expect(sideDrawer, contains('blurRadius: 16'));
      expect(sideDrawer, contains('kNavBlobColor.withValues(alpha: 0.30)'));
      // 内高光（玻璃厚度感）
      expect(sideDrawer, contains('Colors.white.withValues(alpha: 0.10)'));
    });

    test('C2 687：选中指示器改为竖向光条（AnimatedPositioned 滑动）', () {
      // 旧的「右侧 3px 竖条」改成独立的 DockIndicatorBar：
      // 切换时平滑滑到新位置，不是瞬间消失出现
      expect(sideDrawer, contains('class DockIndicatorBar'));
      expect(sideDrawer, contains('AnimatedPositioned'));
      expect(sideDrawer, contains('width: 3'));
      expect(sideDrawer, contains('height: 24'));
    });

    test('C3 687：悬停时图标上浮 + 放大（Dock 磁吸感）', () {
      expect(sideDrawer, contains('AnimatedSlide'));
      expect(sideDrawer, contains('AnimatedScale'));
      expect(sideDrawer, contains('Offset(0, -0.04)'));
      expect(sideDrawer, contains('scale: hovered ? 1.08 : 1.0'));
    });

    test('C6 687：整条侧边栏包在大圆角玻璃里', () {
      expect(sideDrawer, contains('GlassContainer('));
      expect(sideDrawer, contains('BorderRadius.circular(20)'));
    });

    test('C7 687：收起态品牌为单字母 H', () {
      expect(sideDrawer, contains("'H'"));
      expect(sideDrawer, contains('ValueKey(\'brandLetter\')'));
      // 展开态仍是 HIMI / 同步观影
      expect(sideDrawer, contains("'HIMI'"));
      expect(sideDrawer, contains("'同步观影'"));
    });

    test('C8 687：收起态选中项有呼吸圆点', () {
      expect(sideDrawer, contains('!showLabel && selected'));
      expect(sideDrawer, contains('shape: BoxShape.circle'));
    });

    test('C9 687：导航项分组（组间空隙代替横线）', () {
      expect(sideDrawer, contains('_groupSplitAfter'));
    });

    test('C4 收起态用 Tooltip 显示名称（文字不常显）', () {
      expect(sideDrawer, contains('Tooltip('));
      expect(sideDrawer, contains('message: kShellNavLabels[index]'));
      expect(sideDrawer, contains('showLabel'));
    });

    test('C5 不再有每项之间的 Divider（老式列表感）', () {
      final code = codeOnly(sideDrawer);
      expect(code, isNot(contains('Divider(')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 兼容与性能
  // ═══════════════════════════════════════════════════════════════

  group('D 兼容既有接口', () {
    test('D1 保留 shellContentArea / drawerToggle 两个 key', () {
      expect(sideDrawer, contains("ValueKey('shellContentArea')"));
      expect(sideDrawer, contains("ValueKey('drawerToggle')"));
    });

    test('D2 导航常量不变（tv_top_nav_bar 共用）', () {
      expect(sideDrawer, contains("const List<String> kShellNavLabels"));
      expect(sideDrawer, contains("const List<IconData> kShellNavIcons"));
      expect(sideDrawer,
          contains("const List<IconData> kShellNavSelectedIcons"));
      expect(sideDrawer, contains("'首页', '收藏', 'Emby', '声网', '设置'"));
    });

    test('D3 桌面断点仍 1000', () {
      expect(sideDrawer, contains('kShellDesktopBreakpoint = 1000.0'));
    });

    test('D4 动画只在外层监听（不再每 item 一个 AnimatedBuilder）', () {
      final count = RegExp(r'AnimatedBuilder\(').allMatches(sideDrawer).length;
      expect(count, 1, reason: '5 个 item 各自监听会导致折叠时 5 次重建');
    });

    test('D5 每个导航项有稳定 key（测试与自动化用）', () {
      expect(sideDrawer, contains("ValueKey('shellDockItem_\$index')"));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 交互行为
  // ═══════════════════════════════════════════════════════════════

  group('E Dock 交互', () {
    test('E1 点图标切换分支（onSelect）', () {
      expect(sideDrawer, contains('onTap: () => widget.onSelect(index)'));
    });

    test('E2 点把手切换展开态', () {
      expect(sideDrawer, contains('onTap: _toggle'));
      expect(sideDrawer, contains('_controller.forward()'));
      expect(sideDrawer, contains('_controller.reverse()'));
    });

    test('E3 悬停追踪（进入/离开都重置）', () {
      expect(sideDrawer, contains('_hoverIndex = index'));
      expect(sideDrawer, contains('_hoverIndex = -1'));
      expect(sideDrawer, contains('onEnter:'));
      expect(sideDrawer, contains('onExit:'));
    });

    test('E4 文字在展开进度 > 0.5 才显示（防糊在图标上）', () {
      expect(sideDrawer, contains('final showLabel = curve > 0.5'));
    });
  });
}

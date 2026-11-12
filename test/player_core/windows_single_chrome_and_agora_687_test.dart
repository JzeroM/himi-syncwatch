import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 687：两件事一起修。
///
/// ## 1. Windows 单人播放恢复原生标题栏三钮 + 左上角返回按钮
///
/// 679 为房间模式去掉了系统标题栏（避免误点 X 杀掉播放窗、房间悬空），
/// 但那个改动是**全局**的——单人播放也失去了最小化/最大化/关闭三钮。
/// 679 同时删掉了左上角返回按钮。两者都需要**仅单人模式**恢复。
///
/// 关键：不能靠 QML 改 `flags`（会销毁重建原生窗口 → 播放中断、
/// `mpv` 的 `wid` 绑定失效黑屏），必须在 C++ 改 `GWL_STYLE` 位。
///
/// 另外发现**单人 `RequestExit` 在 Dart 侧没有分支**（落到 switch 的
/// default 被静默丢弃）——光加按钮会「点了没反应」，必须一起补。
///
/// ## 2. 安卓切到「声网」标签卡顿（全平台通用缺陷）
///
/// 根因三处叠加：
///   a. `_bookEpoch++` 换 `ValueKey` → 整本书销毁重建（封面 6 处
///      `BoxShadow` blur 30/26/14 重新离屏渲染）
///   b. `TweenAnimationBuilder` 每次 build 新建 `ColorTween` → 白跑
///      320ms 颜色动画，期间每帧重算 `AgoraBookPalette.fromAccent`
///   c. 无 `RepaintBoundary`，翻页/重建牵连同级重绘
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String mpvCpp;
  late String mpvH;
  late String mainCpp;
  late String mainQml;
  late String topBar;
  late String overlayQml;
  late String adapterDart;
  late String playerScreen;
  late String agoraScreen;
  late String guideBook;

  setUpAll(() {
    const dir = 'native/windows_qt_player/src';
    mpvCpp = read('$dir/mpv_window.cpp');
    mpvH = read('$dir/mpv_window.h');
    mainCpp = read('$dir/main.cpp');
    mainQml = read('$dir/qml/Main.qml');
    topBar = read('$dir/qml/TopBar.qml');
    overlayQml = read('$dir/qml/Overlay.qml');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
    agoraScreen = read('lib/screens/agora/agora_config_screen.dart');
    guideBook = read('lib/widgets/agora/agora_guide_book.dart');
  });

  String codeOnly(String s) => s
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

  String extract(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    var i = start;
    while (i < src.length && src[i] != '(') {
      i++;
    }
    var paren = 0;
    for (; i < src.length; i++) {
      if (src[i] == '(') paren++;
      if (src[i] == ')') {
        paren--;
        if (paren == 0) {
          i++;
          break;
        }
      }
    }
    while (i < src.length && src[i] != '{') {
      i++;
    }
    var depth = 0;
    for (; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    return src.substring(start);
  }

  // ═══════════════════════════════════════════════════════════════
  // A. Windows 窗口边框按房间态切换
  // ═══════════════════════════════════════════════════════════════

  group('A 单人恢复原生标题栏三钮', () {
    test('A1 C++ 用 GWL_STYLE 位切换（不重建窗口）', () {
      final body = extract(mpvCpp, 'void MpvWindow::setRoomChrome(');
      expect(body, contains('GWL_STYLE'));
      expect(body, contains('WS_CAPTION'));
      expect(body, contains('WS_MINIMIZEBOX'));
      expect(body, contains('WS_MAXIMIZEBOX'));
      // 房间：清位；单人：置位
      expect(body, contains('style & ~kCaption'));
      expect(body, contains('style | kCaption'));
    });

    test('A2 改完必须发 FRAMECHANGED（否则三钮不重绘）', () {
      final body = extract(mpvCpp, 'void MpvWindow::setRoomChrome(');
      expect(body, contains('SWP_FRAMECHANGED'));
    });

    test('A3 幂等（无变化不折腾）', () {
      final body = extract(mpvCpp, 'void MpvWindow::setRoomChrome(');
      expect(body, contains('if (next == style) return;'));
    });

    test('A4 Main.qml 初始带边框（不再全局 FramelessWindowHint）', () {
      final code = codeOnly(mainQml);
      expect(code, isNot(contains('FramelessWindowHint')));
      expect(code, contains('flags: Qt.Window'));
    });

    test('A5 IPC 命令 setRoomChrome 已接通', () {
      expect(mainCpp, contains('QLatin1String("setRoomChrome")'));
      expect(mainCpp, contains('mpv.setRoomChrome('));
      expect(adapterDart, contains("'type': 'setRoomChrome'"));
      expect(adapterDart, contains('void setRoomChrome(bool room)'));
    });

    test('A6 进房设 true、退房设 false', () {
      final enter =
          extract(playerScreen, 'Future<void> _applyRoomSplitLayout(');
      expect(enter, contains('qt.setRoomChrome(true)'));
      final exit = extract(playerScreen, 'Future<void> _exitRoomSplitLayout()');
      expect(exit, contains('setRoomChrome(false)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 左上角返回按钮（仅单人）
  // ═══════════════════════════════════════════════════════════════

  group('B 左上角返回按钮', () {
    test('B1 按钮存在且仅单人显示', () {
      expect(topBar, contains('icon: Icons.arrowBack'));
      expect(topBar, contains('visible: !playerState.isRoom'));
      expect(topBar, contains('tooltip: "返回"'));
    });

    test('B2 点击发 requestExit（与原生 X 同一链路）', () {
      expect(topBar, contains('"type": "requestExit"'));
    });

    test('B3 返回按钮在标题之前（左上角）', () {
      final backIdx = topBar.indexOf('Icons.arrowBack');
      final titleIdx = topBar.indexOf('text: playerState.title');
      expect(backIdx, greaterThan(0));
      expect(titleIdx, greaterThan(backIdx),
          reason: '返回按钮必须在标题左侧');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 单人 RequestExit 分支（关键缺口）
  // ═══════════════════════════════════════════════════════════════

  group('C 单人退出链路', () {
    test('C1 RequestExit 有独立的单人分支', () {
      final body = extract(playerScreen, 'Future<void> _handleNativeUiCommand(');
      expect(body, contains('if (command is RequestExit)'));
      // 房间分支：确认框
      expect(body, contains('_confirmLeaveRoom()'));
      // 单人分支：直接退页 + 关 Qt
      expect(body, contains('_safePopPlayerPage()'));
      expect(body, contains('MpvSessionPlatform.closeQtPlayer()'));
    });

    test('C2 单人分支不是「落到 default 被丢弃」', () {
      // 旧实现只有 `command is RequestExit && roomCode != null && ...`
      // 一个条件，单人直接穿过到 switch
      expect(
        playerScreen,
        isNot(contains(
            'if (command is RequestExit && widget.roomCode != null && _roomQtActive)')),
      );
    });

    test('C3 房间分支仍走确认框（不误改）', () {
      final body = extract(playerScreen, 'Future<void> _handleNativeUiCommand(');
      expect(body, contains('widget.roomCode != null && _roomQtActive'));
      expect(body, contains('activeQtAdapter?.focus()'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 无边框专属交互仅房间启用
  // ═══════════════════════════════════════════════════════════════

  group('D 自绘拖动/缩放仅房间态', () {
    test('D1 顶栏拖拽区 enabled 绑房间态', () {
      final body = extract(topBar, 'MouseArea {');
      expect(body, contains('enabled: playerState.isRoom'));
    });

    test('D2 8 向拉伸热区 visible 绑房间态', () {
      final idx = overlayQml.indexOf('WindowResizeEdges {');
      expect(idx, greaterThan(0));
      final body = overlayQml.substring(
          idx, (idx + 300).clamp(0, overlayQml.length));
      expect(body, contains('visible: playerState.isRoom'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. 声网切标签卡顿（全平台）
  // ═══════════════════════════════════════════════════════════════

  group('E 声网书本不再销毁重建', () {
    test('E1 不再用 _bookEpoch 换 ValueKey', () {
      expect(codeOnly(agoraScreen), isNot(contains('_bookEpoch')));
      expect(codeOnly(agoraScreen),
          isNot(contains("ValueKey('agoraGuideBook_")));
    });

    test('E2 改用 resetSignal 信号', () {
      expect(agoraScreen, contains('_bookReset'));
      expect(agoraScreen, contains('resetSignal: _bookReset'));
      expect(agoraScreen, contains('ValueNotifier<int>(0)'));
    });

    test('E3 切走分支时发信号（保留回到封面行为）', () {
      expect(agoraScreen, contains('_bookReset.value++'));
      // 表单收起逻辑保持不变
      expect(agoraScreen, contains('_editing = saved?.isConfigured != true'));
    });

    test('E4 信号在 dispose 释放（防泄漏）', () {
      expect(agoraScreen, contains('_bookReset.dispose()'));
    });

    test('E5 书本监听信号并重置到合上封面', () {
      expect(guideBook, contains('final ValueListenable<int>? resetSignal'));
      final body = extract(guideBook, 'void _handleReset()');
      expect(body, contains('_index = -1'));
      expect(body, contains('_target = null'));
      expect(body, contains('_flip.value = 0'));
      // 监听注册与注销
      expect(guideBook, contains('resetSignal?.addListener(_handleReset)'));
      expect(guideBook, contains('resetSignal?.removeListener(_handleReset)'));
    });

    test('E6 didUpdateWidget 里迁移监听（防悬挂）', () {
      final body = extract(guideBook, 'void didUpdateWidget(');
      expect(body, contains('old.resetSignal?.removeListener'));
      expect(body, contains('widget.resetSignal?.addListener'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // F. 颜色动画不再白跑
  // ═══════════════════════════════════════════════════════════════

  group('F 主题色动画只在真变时跑', () {
    test('F1 缓存 ColorTween（不每次 build 新建）', () {
      expect(guideBook, contains('late ColorTween _accentTween'));
      // build 里用缓存的实例
      expect(guideBook, contains('tween: _accentTween'));
      // 不再在 build 里 new ColorTween
      final build = extract(guideBook, 'Widget build(BuildContext context)');
      expect(build, isNot(contains('ColorTween(')));
    });

    test('F2 themeColor 变化才重建 tween', () {
      final body = extract(guideBook, 'void didUpdateWidget(');
      expect(body, contains('old.themeColor != widget.themeColor'));
    });

    test('F3 书本包 RepaintBoundary（隔离重绘）', () {
      expect(guideBook, contains('RepaintBoundary('));
    });
  });
}

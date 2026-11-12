import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 682：Windows 房间模式三项真机回归修复。
///
/// ## 1. 删除在播资源后再播其他资源 → 播放/暂停失效
///
/// 根因链（三处叠加）：
///   a. `MpvWindow::stopPlayback()` 只把本地镜像 `paused_ = true`，**没有**
///      同步 mpv 的 `pause` 属性（仍是 `no`）。
///   b. mpv 的 `pause` 是**跨 loadfile 保持**的——上一条媒体被置 `pause=yes`
///      后，下一次 `loadfile` 继承暂停态。
///   c. QML 读 `playerState.paused`（镜像）做 `togglePause()` 取反 →
///      镜像错位时点一下反而把画面停住 / 点了没反应。
///
/// 修复：`stopPlayback` 强制 `pause=yes`；`load` 强制 `pause=no` 并回传
/// `pausedChanged(false)`；两侧用 `hasMedia_` 显式标志解耦。
///
/// ## 2. 删除在播资源后不显示占位文字
///
/// `stopPlayback()` 会回一帧 `paused:true`（清进度用），Dart 侧旧实现
/// 无条件把它翻成 `paused` → `playerReady` 误判「有内容」→ 占位层隐藏。
/// 修复：适配器加 `_hasMedia`，卸载态下丢弃播放态镜像。
///
/// ## 3. 进房间初始窗口太大
///
/// 旧实现两窗合计铺满整个工作区（宽 = 工作区宽、高 = 工作区高）。
/// 修复：按工作区缩比居中（宽 82% 且不超 1600，高 80%）。
///
/// ## 4. 并排两窗必须同层
///
/// 两个独立顶层窗在普通 z-order 下可能只被盖住一个。修复：两窗同时
/// `HWND_TOPMOST`，全屏除外。
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String mpvCpp;
  late String mpvH;
  late String mainCpp;
  late String adapterDart;
  late String playerScreen;

  setUpAll(() {
    mpvCpp = read('$dir/src/mpv_window.cpp');
    mpvH = read('$dir/src/mpv_window.h');
    mainCpp = read('$dir/src/main.cpp');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  /// 截取 `signature` 起始到函数体结束的片段（源码断言用）。
  ///
  /// 【注意】必须跳过参数表里的 `{`（Dart 命名参数 `{int startMs = 0}`），
  /// 否则会在签名处就把深度收回到 0，只截到一行。
  String extract(String src, String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThanOrEqualTo(0), reason: '未找到 $signature');
    // 先配平参数表的圆括号，再找函数体的 `{`
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
  // A. 删除在播资源 → 再播其他资源 → 播放/暂停失效
  // ═══════════════════════════════════════════════════════════════

  group('A 播放/暂停失效（Qt pause 属性跨 load 保持）', () {
    test('A1 stopPlayback 强制同步 mpv 的 pause=yes', () {
      final body = extract(mpvCpp, 'void MpvWindow::stopPlayback()');
      // 只改本地镜像是不够的：mpv 的 pause 属性必须一起写
      expect(body, contains('mpv_set_property_string(mpv_, "pause", "yes")'));
      expect(body, contains('paused_ = true'));
    });

    test('A2 stopPlayback 清掉 hasMedia 标志', () {
      final body = extract(mpvCpp, 'void MpvWindow::stopPlayback()');
      expect(body, contains('hasMedia_ = false'));
    });

    test('A3 load 强制起播（pause=no），覆盖继承的暂停态', () {
      final body = extract(mpvCpp, 'void MpvWindow::load(');
      expect(body, contains('mpv_set_property_string(mpv_, "pause", "no")'));
      expect(body, contains('hasMedia_ = true'));
      // 镜像同步 + 回传边沿（否则 QML 图标与真实状态错位）
      expect(body, contains('paused_ = false'));
      expect(body, contains('emit pausedChanged(false)'));
    });

    test('A4 loadfile 失败时不置 hasMedia（避免假就绪）', () {
      final body = extract(mpvCpp, 'void MpvWindow::load(');
      final failIdx = body.indexOf('lastError_ = QStringLiteral("loadfile');
      final mediaIdx = body.indexOf('hasMedia_ = true');
      expect(failIdx, greaterThan(0));
      // 失败分支必须 return，不能落到置位语句
      expect(body.substring(failIdx, mediaIdx), contains('return;'));
    });

    test('A5 hasMedia_ 是显式标志（不靠 paused_ 推断）', () {
      expect(mpvH, contains('bool hasMedia_ = false'));
      // 声明处必须写清「镜像与实际错位」这个真机根因
      expect(mpvH, contains('播放/暂停点了没反应'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 删除在播资源后显示占位文字
  // ═══════════════════════════════════════════════════════════════

  group('B 删空资源后占位文字', () {
    test('B1 适配器维护 _hasMedia（prepare 置位 / unload 清零）', () {
      expect(adapterDart, contains('bool _hasMedia = false'));
      final prepare =
          extract(adapterDart, 'Future<void> prepare({int startMs = 0})');
      expect(prepare, contains('_hasMedia = true'));
      final unload = extract(adapterDart, 'Future<void> unloadMedia()');
      expect(unload, contains('_hasMedia = false'));
      // 必须在发 stop 之前清零——Qt 回的 paused:true 不能被翻成 paused
      expect(unload.indexOf('_hasMedia = false'),
          lessThan(unload.indexOf("'type': 'stop'")));
    });

    test('B2 卸载态丢弃 playback 镜像（不再被 paused:true 翻回 paused）', () {
      final body = extract(adapterDart, 'void _applyPlayback(');
      expect(body, contains('if (!_hasMedia)'));
      // 卸载分支必须保持 stopped 且清空进度
      final branch = body.substring(body.indexOf('if (!_hasMedia)'));
      expect(branch, contains('AdapterPlaybackState.stopped'));
      expect(branch, contains('_positionMs = 0'));
      expect(branch, contains('_durationMs = 0'));
      expect(branch, contains('AdapterMediaStatus.unloaded'));
    });

    test('B3 暴露 hasMedia getter（playerReady 的唯一判据）', () {
      expect(adapterDart, contains('bool get hasMedia =>'));
      expect(playerScreen, contains('stateJson[\'playerReady\'] = qt.isAlive && qt.hasMedia'));
    });

    test('B4 playerReady 不再靠 position/duration 推断', () {
      // 旧判据 `qt.position >= 0 && (qt.duration > 0 || state != stopped)`
      // 在 stop 后仍为真 → 占位不显示
      expect(
        playerScreen,
        isNot(contains("qt.position >= 0 &&\n          (qt.duration > 0")),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 进房间初始窗口尺寸
  // ═══════════════════════════════════════════════════════════════

  group('C 进房间初始窗口不铺满整屏', () {
    test('C1 按工作区缩比（宽 82% / 高 80%）并设上限', () {
      final body = extract(mpvCpp, 'void MpvWindow::requestSplitLayout(');
      expect(body, contains('kSplitWidthRatio'));
      expect(body, contains('kSplitHeightRatio'));
      expect(body, contains('kSplitMaxWidth'));
    });

    test('C2 初始矩形居中（不再贴工作区左上角铺满）', () {
      final body = extract(mpvCpp, 'void MpvWindow::requestSplitLayout(');
      expect(body, contains('originX'));
      expect(body, contains('originY'));
      expect(body, contains('(work.width() - totalW) / 2'));
      expect(body, contains('(work.height() - totalH) / 2'));
    });

    test('C3 缩放后仍保证并排最小宽（面板 + 视频区）', () {
      final body = extract(mpvCpp, 'void MpvWindow::requestSplitLayout(');
      expect(body, contains('panelWidth + minVideoWidth'));
      // 高度不得低于 kMinHeight
      expect(body, contains('qMax(totalH, kMinHeight)'));
    });

    test('C4 常量取值合理（宽不超 1600，比例 < 1）', () {
      final maxW = RegExp(r'constexpr int kSplitMaxWidth = (\d+)')
          .firstMatch(mpvCpp)!
          .group(1)!;
      expect(int.parse(maxW), lessThanOrEqualTo(1600));
      final wRatio = RegExp(r'constexpr double kSplitWidthRatio = ([0-9.]+)')
          .firstMatch(mpvCpp)!
          .group(1)!;
      final hRatio = RegExp(r'constexpr double kSplitHeightRatio = ([0-9.]+)')
          .firstMatch(mpvCpp)!
          .group(1)!;
      expect(double.parse(wRatio), lessThan(1.0));
      expect(double.parse(hRatio), lessThan(1.0));
      expect(double.parse(wRatio), greaterThanOrEqualTo(0.6));
      expect(double.parse(hRatio), greaterThanOrEqualTo(0.6));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // D. 并排两窗同层
  // ═══════════════════════════════════════════════════════════════

  group('D 并排两窗永远同层（全屏除外）', () {
    test('D1 Qt 侧用 HWND_TOPMOST / HWND_NOTOPMOST', () {
      final body = extract(mpvCpp, 'void MpvWindow::setTopmost(');
      expect(body, contains('HWND_TOPMOST'));
      expect(body, contains('HWND_NOTOPMOST'));
      // 去重：同值不重复 SetWindowPos
      expect(body, contains('if (topmost_ == topmost) return;'));
    });

    test('D2 置顶是持久层级属性（不是周期性 raise）', () {
      expect(mpvH, contains('Q_INVOKABLE void setTopmost(bool topmost)'));
      expect(mpvH, contains('一半被盖'));
    });

    test('D3 IPC 命令 setTopmost 已接通', () {
      expect(mainCpp, contains('QLatin1String("setTopmost")'));
      expect(mainCpp, contains('mpv.setTopmost('));
      expect(adapterDart, contains("'type': 'setTopmost'"));
    });

    test('D4 Dart 侧进房置顶、退房取消', () {
      final body = extract(playerScreen, 'Future<void> _applyRoomTopmost(');
      expect(body, contains('qt.setTopmost(enabled)'));
      expect(body, contains('windowManager.setAlwaysOnTop(panelTopmost)'));
      // 进房
      expect(playerScreen, contains('unawaited(_applyRoomTopmost(true))'));
      // 退房
      final exit = extract(playerScreen, 'Future<void> _exitRoomSplitLayout()');
      expect(exit, contains('_applyRoomTopmost(false)'));
    });

    test('D5 全屏是唯一例外（全屏时关闭两窗置顶）', () {
      final body = extract(playerScreen, 'void _wireRoomQtAdapter');
      // 全屏回调里按 !fullscreen 应用
      expect(body, contains('_applyRoomTopmost(!fullscreen)'));
    });

    test('D6 Qt 已退出时不留面板单独置顶（否则挡住别的软件）', () {
      final body = extract(playerScreen, 'Future<void> _applyRoomTopmost(');
      // Qt 存活判定单独提出
      expect(body, contains('final qtAlive = qt != null && qt.isAlive;'));
      // 面板置顶必须以 Qt 存活为前提
      expect(body, contains('final panelTopmost = enabled && qtAlive;'));
      expect(body, contains('windowManager.setAlwaysOnTop(panelTopmost)'));
    });

    test('D7 抬升窗口不破坏置顶层（HWND_TOP 会降级）', () {
      // Win32 语义：SetWindowPos(HWND_TOP) 把窗口插入**非置顶组**最前，
      // 置顶窗会被降回普通层 → 两窗同层失效。
      final raise = extract(mpvCpp, 'void MpvWindow::raiseToFront()');
      expect(raise, contains('topmost_ ? HWND_TOPMOST : HWND_TOP'));
      // main.cpp 的 forceForeground 同理（按 exstyle 判定）
      final fgStart = mainCpp.indexOf('const auto forceForeground');
      expect(fgStart, greaterThan(0));
      final fg = mainCpp.substring(fgStart, fgStart + 1200);
      expect(fg, contains('WS_EX_TOPMOST'));
      expect(fg, contains('topmost ? HWND_TOPMOST : HWND_TOP'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // E. main.cpp 格式与语法完整性
  // ═══════════════════════════════════════════════════════════════

  group('E main.cpp 命令分发完整性', () {
    test('E1 startSystemMove 与 startSystemResize 分支不再挤在同一行', () {
      expect(mainCpp, isNot(contains('mpv.startSystemMove();                         } else if')));
      expect(mainCpp, contains('mpv.startSystemMove();\n'));
    });

    test('E2 setTopmost 分支在 setHostFullscreen 之后', () {
      final fsIdx = mainCpp.indexOf('QLatin1String("setHostFullscreen")');
      final topIdx = mainCpp.indexOf('QLatin1String("setTopmost")');
      expect(fsIdx, greaterThan(0));
      expect(topIdx, greaterThan(fsIdx));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // F. 适配器 setTopmost 行为
  // ═══════════════════════════════════════════════════════════════

  group('F 适配器 setTopmost', () {
    test('F1 disposed 后不再发命令', () {
      final body = extract(adapterDart, 'void setTopmost(bool topmost)');
      expect(body, contains('if (_disposed) return;'));
    });

    test('F2 hasMedia 在 disposed 后为 false（避免残留判据）', () {
      expect(adapterDart, contains('bool get hasMedia => _hasMedia && !_disposed'));
    });
  });
}

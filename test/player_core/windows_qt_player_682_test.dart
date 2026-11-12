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
/// ## 4. 并排两窗必须同层（但**不置顶**）
///
/// 【683 需求澄清】用户要的是「两窗在 z-order 里始终相邻、不被拆散」，
/// **不是**「压在所有软件之上」。682 误实现成了 `HWND_TOPMOST`，房间
/// 开着时把别的软件全盖住 → 用户明确否掉：「要灵活，我只要求了两窗口
/// 同一层，没说固定最上层」。
///
/// 现在：Qt 窗激活 → `HWND_TOP` 抬到非置顶层最前 + 发 `raised` 帧 →
/// Dart 把面板也抬上来。切到别的软件时两窗一起被正常盖住。
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String mpvCpp;
  late String mpvH;
  late String mainCpp;
  late String pipeH;
  late String pipeCpp;
  late String pipeDart;
  late String adapterDart;
  late String playerScreen;

  setUpAll(() {
    mpvCpp = read('$dir/src/mpv_window.cpp');
    mpvH = read('$dir/src/mpv_window.h');
    mainCpp = read('$dir/src/main.cpp');
    pipeH = read('$dir/src/pipe_server.h');
    pipeCpp = read('$dir/src/pipe_server.cpp');
    pipeDart = read('lib/services/player/qt_player_pipe.dart');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
    playerScreen = read('lib/screens/player/player_screen.dart');
  });

  /// 剔除注释行（`//` 与 `///`）——注释里会提到旧写法「说明为什么改」，
  /// 直接用 `contains` 会误判成「代码里还在用」。
  String codeOnly(String src) => src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      })
      .join('\n');

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
  // D. 并排两窗联动抬升（同层，但不置顶）
  // ═══════════════════════════════════════════════════════════════

  group('D 并排两窗同层但不置顶（683 需求澄清）', () {
    test('D1 任何地方都不得用 HWND_TOPMOST（会永久压住别的软件）', () {
      // 用户明确要求：「要灵活，我只要求了两窗口同一层，没说固定最上层」
      expect(codeOnly(mpvCpp), isNot(contains('HWND_TOPMOST')));
      expect(codeOnly(mainCpp), isNot(contains('HWND_TOPMOST')));
      expect(codeOnly(mpvCpp), isNot(contains('HWND_NOTOPMOST')));
    });

    test('D2 setTopmost 退化为「联动模式开关」（不改窗口层级）', () {
      final body = extract(mpvCpp, 'void MpvWindow::setTopmost(');
      expect(body, contains('topmost_ = topmost'));
      // 关键：不得再调 SetWindowPos
      expect(body, isNot(contains('SetWindowPos')));
    });

    test('D3 Qt 侧提供 raiseTogether（HWND_TOP 联动抬升）', () {
      expect(mpvH, contains('Q_INVOKABLE void raiseTogether()'));
      final body = extract(mpvCpp, 'void MpvWindow::raiseTogether()');
      expect(body, contains('HWND_TOP'));
      expect(body, contains('emit raisedToFront()'));
      expect(body, isNot(contains('HWND_TOPMOST')));
    });

    test('D4 Qt 窗激活时联动抬升（activeChanged 钩子）', () {
      final attach = extract(mpvCpp, 'bool MpvWindow::attach(');
      expect(attach, contains('activeChanged'));
      expect(attach, contains('emit raisedToFront()'));
      // 失活不处理（让用户正常切走）
      expect(attach, contains('if (!host_->isActive()) return;'));
    });

    test('D5 raised 帧接通 IPC（Qt → Dart）', () {
      expect(mainCpp, contains('MpvWindow::raisedToFront'));
      expect(mainCpp, contains('pipe.sendRaised()'));
      expect(pipeH, contains('void sendRaised()'));
      expect(pipeCpp, contains('QStringLiteral("raised")'));
      expect(pipeDart, contains("type == 'raised'"));
    });

    test('D6 Dart 侧收到 raised → 抬面板（不置顶、不抢焦点）', () {
      final body = extract(playerScreen, 'Future<void> _raisePanelWithQt(');
      // `show(inactive: true)` = 提到最前但不抢键盘焦点
      expect(body, contains('windowManager.show(inactive: true)'));
      // 绝不能置顶
      expect(body, isNot(contains('setAlwaysOnTop(true)')));
      // 不能 focus()——会把焦点从用户刚点的 Qt 窗抢走
      expect(body, isNot(contains('windowManager.focus()')));
      expect(playerScreen, contains('adapter.onRaised'));
    });

    test('D7 进房开联动、退房关联动', () {
      final body = extract(playerScreen, 'Future<void> _applyRoomTopmost(');
      expect(body, contains('qt.setTopmost(enabled)'));
      expect(playerScreen, contains('unawaited(_applyRoomTopmost(true))'));
      final exit = extract(playerScreen, 'Future<void> _exitRoomSplitLayout()');
      expect(exit, contains('_applyRoomTopmost(false)'));
    });

    test('D8 主动清掉历史 setAlwaysOnTop 残留（升级用户不再被压住）', () {
      final body = codeOnly(
          extract(playerScreen, 'Future<void> _applyRoomTopmost('));
      // 只允许 false
      expect(body, contains('windowManager.setAlwaysOnTop(false)'));
      expect(body, isNot(contains('setAlwaysOnTop(true)')));
    });

    test('D9 全屏仍按 !fullscreen 开关联动', () {
      final body = extract(playerScreen, 'void _wireRoomQtAdapter');
      expect(body, contains('_applyRoomTopmost(!fullscreen)'));
    });

    test('D10 抬升窗口只用 HWND_TOP（不破坏层级语义）', () {
      final raise = extract(mpvCpp, 'void MpvWindow::raiseToFront()');
      expect(raise, contains('HWND_TOP'));
      expect(codeOnly(raise), isNot(contains('HWND_TOPMOST')));
      // main.cpp 的 forceForeground 同理
      final fgStart = mainCpp.indexOf('const auto forceForeground');
      expect(fgStart, greaterThan(0));
      final fg = codeOnly(mainCpp.substring(fgStart, fgStart + 1200));
      expect(fg, contains('HWND_TOP'));
      expect(fg, isNot(contains('HWND_TOPMOST')));
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

    test('F3 适配器 setTopmost 只发联动开关（注释说明不置顶）', () {
      final body = extract(adapterDart, 'void setTopmost(bool topmost)');
      expect(body, contains("'type': 'setTopmost'"));
      // 只是开关，不改层级；Dart 侧注释需写明用户要求
      expect(adapterDart, contains('不置顶'));
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 656：Windows 播放器窗口（Qt Quick + libmpv）。
///
/// ## 目标
///
/// 把 Windows 播放器从「只有视频、没有任何控件」变成带完整控件的窗口，
/// 同时保住 HDR 直出。Flutter 仍是唯一逻辑权威（Emby / 房间同步 / RTM /
/// 弹幕拉取），Qt 只做「渲染 + 控件」。
///
/// ## 为什么不用 QML 渲染视频
///
/// libmpv 的 render API 只有 OpenGL 与软件后端，没有 D3D11。把视频画进
/// QML 就得走 OpenGL FBO → mpv 先转 SDR RGBA → **HDR 直出必然丢失**。
/// 所以 mpv 自己拥有一个 HWND（`wid`），QML 只做控件层。
///
/// ## 为什么用 TCP 而不是命名管道
///
/// 最初设计用 Windows `CreateNamedPipe`，但 **Dart 无法连接命名管道**——
/// `Socket.connect` 的 `InternetAddressType.unix` 只支持 Unix domain
/// socket；命名管道必须走 `CreateFile`（原生 API），Dart 没有内置支持。
/// 改用 TCP 只绑 127.0.0.1 + 一次性 token 校验，安全性等价。
///
/// ## 协议复用
///
/// 不重新设计协议：直接消费 Flutter 侧已有的 `NativePlayerState`
/// （87 字段）与 `NativePlayerCommand`（35 种），与安卓/鸿蒙原生 UI
/// 用的是同一份。
void main() {
  const dir = 'native/windows_qt_player';
  String read(String p) => File(p).readAsStringSync();

  late String cmake;
  late String mainCpp;
  late String mpvCpp;
  late String mpvH;
  late String pipeCpp;
  late String stateH;
  late String stateCpp;
  late String mainQml;
  late String topBar;
  late String bottomBar;
  late String pipeDart;
  late String adapterDart;
  late String workflow;

  setUpAll(() {
    cmake = read('$dir/CMakeLists.txt');
    mainCpp = read('$dir/src/main.cpp');
    mpvCpp = read('$dir/src/mpv_window.cpp');
    mpvH = read('$dir/src/mpv_window.h');
    pipeCpp = read('$dir/src/pipe_server.cpp');
    stateH = read('$dir/src/player_state.h');
    stateCpp = read('$dir/src/player_state.cpp');
    mainQml = read('$dir/src/qml/Main.qml');
    topBar = read('$dir/src/qml/TopBar.qml');
    bottomBar = read('$dir/src/qml/BottomBar.qml');
    pipeDart = read('lib/services/player/qt_player_pipe.dart');
    adapterDart = read('lib/services/player/qt_player_adapter.dart');
    workflow = read('.github/workflows/windows-qt-player.yml');
  });

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  group('① HDR：mpv 直出到自己的 HWND（不能画进 QML）', () {
    test('wid 在 mpv_initialize 之前设置', () {
      final widIdx = mpvCpp.indexOf('mpv_set_option_string(mpv_, "wid"');
      final initIdx = mpvCpp.indexOf('mpv_initialize(mpv_)');
      expect(widIdx, greaterThan(-1));
      expect(initIdx, greaterThan(-1));
      expect(widIdx, lessThan(initIdx),
          reason: 'wid 在 init 之后设置无效，mpv 会自己开窗口');
    });

    test('HDR 选项与 Flutter 插件一致', () {
      expect(mpvCpp, contains('"vo", "gpu-next"'));
      expect(mpvCpp, contains('"d3d11-output-mode", "window"'));
      expect(mpvCpp, contains('"d3d11-output-format", "rgb10_a2"'));
      expect(mpvCpp, contains('"target-colorspace-hint", "yes"'));
      expect(mpvCpp, contains('"target-prim", "bt.2020"'));
    });

    test('HDR 判据读 video-out-params（不是 video-params）', () {
      // video-params 描述**片源**，HDR 片源恒为 pq/bt.2020——用它判断会把
      // 「tone map 成 SDR」误判成功。video-out-params 才是实际输出。
      expect(mpvCpp, contains('"video-out-params"'));
      expect(mpvCpp, contains('bool MpvWindow::hdrOutput() const'));
    });

    test('原生子窗口要让出控件区域（Win32 硬规则）', () {
      expect(mpvH, contains('setOverlayInsets'));
      final body = stripComments(mpvCpp);
      expect(body, contains('insetTop_'));
      expect(body, contains('insetBottom_'));
    });
  });

  group('② IPC：TCP localhost（Dart 连不了 Windows 命名管道）', () {
    test('Qt 侧用 QTcpServer 绑 loopback', () {
      expect(pipeCpp, contains('QTcpServer'));
      expect(pipeCpp, contains('QHostAddress::LocalHost'));
    });

    test('Dart 侧用 Socket.connect 连 loopback', () {
      expect(pipeDart, contains('Socket.connect'));
      expect(pipeDart, contains('InternetAddress.loopbackIPv4'));
    });

    test('首帧必须 auth 且 token 匹配（防同机误连）', () {
      expect(pipeCpp, contains('"auth"'));
      expect(pipeCpp, contains('token != token_'));
      expect(pipeDart, contains("'type': 'auth'"));
      expect(pipeDart, contains('Random.secure()'));
    });

    test('NDJSON 分帧（每帧一个 JSON + 换行）', () {
      expect(pipeCpp, contains("indexOf('\\n'"));
      expect(pipeDart, contains('LineSplitter'));
    });

    test('端口由 Flutter 选好传给 Qt（避免竞态）', () {
      expect(pipeDart, contains("'--port'"));
      // QCommandLineParser 的选项名不带前导 `--`，用户输入时才有。
      expect(mainCpp, contains('{"port"'));
    });
  });

  group('③ 协议复用（不重新设计）', () {
    test('Qt 解析 NativePlayerState 的关键字段', () {
      for (final key in [
        'positionMs',
        'durationMs',
        'paused',
        'volume',
        'speed',
        'title',
        'engineLabel',
        'episodes',
        'tracks',
      ]) {
        expect(stateCpp, contains('"$key"'),
            reason: 'PlayerState 必须解析 $key');
      }
    });

    test('Qt 发送的 command 用 NativePlayerCommand 的 type 名', () {
      for (final type in [
        'togglePlay',
        'seekTo',
        'seekRelative',
        'setVolume',
        'setSpeed',
        'selectAudio',
        'selectSubtitle',
        'selectEpisode',
      ]) {
        // QML 里用 `{"type": "togglePlay"}` 或 `'togglePlay'` 两种写法都可能
        final found = mainQml.contains('"$type"') || mainQml.contains("'$type'");
        expect(found, isTrue, reason: 'QML 必须能发出 $type');
      }
    });

    test('状态只在字段真的变化时发信号（20Hz 推送下关键）', () {
      expect(stateCpp, contains('bool assign(T& target, const T& value)'));
      expect(stateCpp, contains('if (dirty) emit changed();'));
    });
  });

  group('④ 控件：复刻 Windows Flutter 播放器', () {
    test('顶栏含返回/标题/网速/内核/解码/比例/倍速/全屏', () {
      for (final icon in [
        '\\ue5c4',  // arrow_back
        '\\ue322',  // memory
        '\\ue3c9',  // high_quality
        '\\ue3c4',  // aspect_ratio
        '\\ue9e4',  // speed
        '\\ue5d0',  // fullscreen
      ]) {
        expect(topBar, contains(icon), reason: '顶栏缺图标 $icon');
      }
      expect(topBar, contains('playerState.title'));
      expect(topBar, contains('playerState.networkSpeedText'));
    });

    test('底栏含进度条/时间/播放暂停/音量/字幕/音轨/选集/倍速/全屏', () {
      expect(bottomBar, contains('SeekBar'));
      expect(bottomBar, contains('formatTime'));
      expect(bottomBar, contains('playerState.paused'));
      expect(bottomBar, contains('playerState.volume'));
      expect(bottomBar, contains('playerState.speed'));
      expect(bottomBar, contains('subtitleCount'));
      expect(bottomBar, contains('audioCount'));
      expect(bottomBar, contains('episodeCount'));
    });

    test('面板复用一套 UI 服务四个场景', () {
      final panel = read('$dir/src/qml/Panel.qml');
      expect(panel, contains('property var items'));
      expect(mainQml, contains('openEpisodePanel'));
      expect(mainQml, contains('openAudioPanel'));
      expect(mainQml, contains('openSubtitlePanel'));
      expect(mainQml, contains('openSpeedPanel'));
    });

    test('Material Icons 字体已打包（与 Flutter 同字形）', () {
      expect(cmake, contains('MaterialIcons-Regular.otf'));
      expect(File('$dir/fonts/MaterialIcons-Regular.otf').existsSync(), isTrue);
      expect(mainQml, contains('FontLoader'));
    });

    test('控件 5 秒无操作自动隐藏（播放中）', () {
      expect(mainQml, contains('interval: 5000'));
      expect(mainQml, contains('controlsVisible'));
    });
  });

  group('⑤ Flutter 侧适配器：只做代理', () {
    test('QtPlayerAdapter 实现 PlayerAdapter 接口', () {
      expect(adapterDart, contains('class QtPlayerAdapter implements PlayerAdapter'));
    });

    test('状态读本地缓存（高频读取不产生 IPC 往返）', () {
      expect(adapterDart, contains('int get position => _positionMs;'));
      expect(adapterDart, contains('int get duration => _durationMs;'));
    });

    test('渲染相关方法全是空实现（Qt 自己管）', () {
      expect(adapterDart, contains('Future<int> updateTexture'));
      expect(adapterDart, contains('=> 0'));
      expect(adapterDart, contains('void renderVideo() {}'));
    });

    test('进程退出时通知上层（回详情页）', () {
      expect(adapterDart, contains('onProcessExited'));
      expect(adapterDart, contains('_pipe.onDisconnected'));
    });

    test('isDisposed 守卫（644 崩溃教训）', () {
      expect(adapterDart, contains('bool get isDisposed => _disposed;'));
      expect(adapterDart, contains('if (_disposed) return;'));
    });
  });

  group('⑥ 构建与 CI（654 踩过的三个坑）', () {
    test('CMake 校验 LIBMPV_DIR 与 client.h', () {
      expect(cmake, contains('LIBMPV_DIR'));
      expect(cmake, contains('include/mpv/client.h'));
    });

    test('CI 用 Ninja + vcvars64（不能挑到 MinGW gcc）', () {
      expect(workflow, contains('-G Ninja'));
      expect(workflow, contains('vcvars64.bat'));
      expect(workflow, contains('vswhere'));
    });

    test('CI 用 QT_ROOT_DIR（不用 steps.install-qt.outputs.qt-dir）', () {
      expect(workflow, contains(r'$env:QT_ROOT_DIR'));
      final cmdLines = workflow
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(cmdLines, isNot(contains('steps.install-qt.outputs.qt-dir')));
    });

    test('CI 捆绑 MSVC CRT（纯净系统否则闪退）', () {
      expect(workflow, contains('Microsoft.VC'));
      expect(workflow, contains('Redist'));
    });

    test('CI 校验产物含 exe / libmpv / Qt6 关键 DLL', () {
      for (final f in [
        'himi_qt_player.exe',
        'libmpv-2.dll',
        'Qt6Core.dll',
        'Qt6Quick.dll',
        'Qt6Qml.dll',
        'Qt6Network.dll',
      ]) {
        expect(workflow, contains(f), reason: 'CI 未校验 $f');
      }
    });
  });

  group('⑦ QML 用到的属性必须都在 PlayerState 声明', () {
    test('playerState.xxx 全部有 Q_PROPERTY', () {
      final declared = RegExp(r'Q_PROPERTY\([^ ]+ ([a-zA-Z]+)')
          .allMatches(stateH)
          .map((m) => m.group(1)!)
          .toSet();
      final used = <String>{};
      for (final src in [mainQml, topBar, bottomBar]) {
        for (final m in RegExp(r'playerState\.([a-zA-Z]+)').allMatches(src)) {
          used.add(m.group(1)!);
        }
      }
      final missing = used.difference(declared);
      expect(missing, isEmpty,
          reason: 'QML 用到但 C++ 未声明的属性: $missing');
    });
  });

  group('⑧ 旧的 Qt spike 已删除', () {
    test('native/windows_qt_client 不存在', () {
      expect(Directory('native/windows_qt_client').existsSync(), isFalse);
    });

    test('旧 spike 的 CI 与测试已删除', () {
      expect(File('.github/workflows/windows-qt-client.yml').existsSync(),
          isFalse);
      expect(File('test/ci/windows_qt_spike_654_test.dart').existsSync(),
          isFalse);
    });
  });

  group('⑨ 真机回归：Qt 窗口没出现（三个 bug）', () {
    final screen =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('单人播放路径（_loadStream）也接入 Qt', () {
      // 【真机现象】任务管理器里只有 HIMI / HIMI Player，没有
      // himi_qt_player.exe —— 656 首版只把 _startQtPlayer 挂在
      // _playFromUrl（房间观众路径），单人点「开始播放」走的是
      // _loadStream，那里没接 → Qt 从不启动。
      final start = screen.indexOf('Future<bool> _loadStream({');
      expect(start, greaterThan(-1), reason: '找不到 _loadStream');
      final end = screen.indexOf('Future<', start + 10);
      final body = screen.substring(start, end > 0 ? end : start + 12000);
      expect(body, contains('_startQtPlayer'),
          reason: '单人播放必须也能拉起 Qt 播放器');
    });

    test('启动子进程用 detached（不能 detachedWithStdio）', () {
      // 【真机现象】同样看不到 himi_qt_player.exe。根因是
      // detachedWithStdio 会创建 stdout/stderr 管道，而 Dart 从不读取
      // → 缓冲区（约 4KB）写满 → Qt 的 qInfo 阻塞 → 主线程卡死
      // → IPC 5 秒超时 → 静默回退 646。
      final codeLines = pipeDart
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeLines, contains('ProcessStartMode.detached'));
      expect(codeLines, isNot(contains('detachedWithStdio')),
          reason: 'detachedWithStdio 的管道不读会阻塞子进程');
    });

    test('Qt 窗口不用 FramelessWindowHint（否则无法拖动缩放）', () {
      final codeLines = mainQml
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeLines, isNot(contains('FramelessWindowHint')),
          reason: '无边框窗口没有标题栏，用户无法拖动/缩放/最小化');
      expect(codeLines, contains('flags: Qt.Window'));
    });
  });
}

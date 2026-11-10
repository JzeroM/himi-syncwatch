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
    test('顶栏含返回/标题/网速/内核胶囊/显示调节/解码/比例', () {
      // 659：图标改为走 Icons 单例（与 Flutter NativePlayerIcons 同码点）。
      // 662：照 Flutter `player_top_bar.dart` 修正——
      //   解码图标是 memory（原 highQuality 是「HD」错字形）；
      //   新增 tune（显示调节）；倍速/全屏**不在顶栏**（桌面倍速在底栏、
      //   全屏只在底栏，用户明确）。
      for (final icon in [
        'Icons.arrowBack',
        'Icons.memory',
        'Icons.tune',
      ]) {
        expect(topBar, contains(icon), reason: '顶栏缺 $icon');
      }
      expect(topBar, contains('playerState.title'));
      expect(topBar, contains('playerState.networkSpeedText'));
      // 内核胶囊是纯文字（Flutter Text(kernelLabel)）
      expect(topBar, contains('playerState.engineLabel'));
      // 顶栏不得有倍速/全屏/解码旧图标（全屏按钮只在底栏；比例映射
      // 里的 `return Icons.fullscreen` 是 cover 模式图标，不算按钮）
      expect(topBar, isNot(contains('Icons.speed')));
      expect(topBar, isNot(contains('icon: Icons.fullscreen')));
      expect(topBar, isNot(contains('Icons.highQuality')));
    });

    test('底栏含进度条/时间/播放暂停/音量/字幕/音轨/选集/倍速/全屏', () {
      // 662：滑杆为 PlayerSlider（EvolveUI ESlider 封装）
      expect(bottomBar, contains('PlayerSlider'));
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

    test('图标字体为 FontAwesome（EvolveUI 生态；662 换字体）', () {
      // 用户决策：Qt 播放器图标换 FontAwesome（与 EvolveUI 组件同字形）。
      // Flutter/安卓/鸿蒙仍是 Material Icons，两侧语义一一对应。
      expect(cmake, contains('Font Awesome 6 Free-Solid-900.otf'));
      expect(
        File('$dir/third_party/evolveui/assets/fonts/'
                'fontawesome-free-6.7.2-desktop/otfs/'
                'Font Awesome 6 Free-Solid-900.otf')
            .existsSync(),
        isTrue,
      );
      expect(mainQml, contains('FontLoader'));
      expect(mainQml, contains('id: iconFont'));
    });

    test('控件 5 秒无操作自动隐藏（播放中）', () {
      // 659：时长改为走 Theme.autoHideMs（与 Flutter NativePlayerTheme 同值）
      expect(mainQml, contains('interval: Theme.autoHideMs'));
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
      // 662：扫描全部 QML（新增的 DisplayAdjustPanel 等也要核对）
      final qmlFiles = Directory('$dir/src/qml')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))
          .toList();
      expect(qmlFiles.length, greaterThanOrEqualTo(10),
          reason: 'src/qml 的 QML 文件数不对，路径变了?');
      for (final f in qmlFiles) {
        for (final m
            in RegExp(r'playerState\.([a-zA-Z]+)').allMatches(f.readAsStringSync())) {
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

  group('⑩ 真机回归：QML 加载失败（qrc 路径错位）', () {
    test('CMakeLists 给每个 QML 设了 QT_RESOURCE_ALIAS', () {
      // 【真机报错】手动跑 exe：
      //   QQmlApplicationEngine failed to load component
      //   qrc:/qt/qml/HimiPlayer/Main.qml: 此文件或目录不存在
      //
      // 坑 1：QML_FILES 写成 `src/qml/Main.qml`，qt_add_qml_module 会
      // **原样保留相对路径**，注册成 `.../HimiPlayer/src/qml/Main.qml`。
      // 用 QT_RESOURCE_ALIAS 抹掉目录前缀。
      expect(cmake, contains('QT_RESOURCE_ALIAS'));
      for (final name in [
        'Main',
        'TopBar',
        'BottomBar',
        'PlayerSlider',
        'ControlButton',
        'Panel',
      ]) {
        expect(cmake, contains(name), reason: '别名循环里缺 $name');
      }
      // EvolveUI vendor 组件按 evolveui/ 子目录别名注册
      // （CMake 用参数化模板，注意 raw 字符串防插值/转义）
      expect(cmake, contains(r'QT_RESOURCE_ALIAS "evolveui/${_qml}.qml"'));
      for (final name in ['ETheme', 'EButton', 'ESlider', 'ECard', 'ELoader']) {
        expect(cmake, contains(name), reason: 'EvolveUI 组件缺 $name');
      }
    });

    test('别名设置必须在 qt_add_qml_module 之前', () {
      final aliasIdx = cmake.indexOf('QT_RESOURCE_ALIAS');
      final moduleIdx = cmake.indexOf('qt_add_qml_module(himi_qt_player');
      expect(aliasIdx, greaterThan(-1));
      expect(moduleIdx, greaterThan(-1));
      expect(aliasIdx, lessThan(moduleIdx),
          reason: '别名晚于 qt_add_qml_module 就不生效了');
    });

    test('显式设置 RESOURCE_PREFIX /qt/qml（默认是 /）', () {
      // 【658 真机退出码 -3】坑 2：RESOURCE_PREFIX 默认是 `/`，
      // 不设置时 qmldir 里是 `prefer :/HimiPlayer/`，
      // 实际路径 `qrc:/HimiPlayer/Main.qml`，
      // 与代码里的 `qrc:/qt/qml/HimiPlayer/Main.qml` 差 `/qt/qml`。
      expect(cmake, contains('RESOURCE_PREFIX /qt/qml'));
    });

    test('CMake 的 RESOURCE_PREFIX 与 main.cpp 加载路径一致', () {
      // 只看非注释行，避免匹配到说明文字。
      final cmakeCode = cmake
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      final prefixMatch =
          RegExp(r'RESOURCE_PREFIX\s+(\S+)').firstMatch(cmakeCode);
      expect(prefixMatch, isNotNull, reason: '必须显式设置 RESOURCE_PREFIX');
      final prefix = prefixMatch!.group(1)!;   // 形如 /qt/qml

      final urlMatch =
          RegExp(r'qrc:([^"]*)/Main\.qml').firstMatch(mainCpp);
      expect(urlMatch, isNotNull, reason: '找不到 main.cpp 里的 QML 加载路径');
      final urlPrefix = urlMatch!.group(1)!;   // 形如 /qt/qml/HimiPlayer

      expect(urlPrefix, startsWith(prefix),
          reason: '加载路径 $urlPrefix 必须以 RESOURCE_PREFIX $prefix 开头，'
              '否则运行时 QML 加载失败（退出码 -3）');
    });

    test('启动时同时探测两个可能的 qrc 前缀', () {
      // 万一前缀又写错，日志里能直接看出实际注册在哪个前缀下。
      expect(mainCpp, contains(':/qt/qml/HimiPlayer'));
      expect(mainCpp, contains(':/HimiPlayer'));
    });

    test('日志同时写控制台和文件（detached 模式下 stdout 全丢）', () {
      expect(mainCpp, contains('qInstallMessageHandler'));
      expect(mainCpp, contains('himi_qt_player.log'));
      // 658 首版只写文件，手动跑 exe 时一行输出都没有 → 必须也写 stderr
      expect(mainCpp, contains('stderr'));
    });

    test('logger 在 main 开头就装上（后面的错误才能落盘）', () {
      final mainIdx = mainCpp.indexOf('int main(int argc, char* argv[])');
      final installIdx = mainCpp.indexOf('installLogger();', mainIdx);
      final parserIdx = mainCpp.indexOf('QCommandLineParser parser;', mainIdx);
      expect(installIdx, greaterThan(mainIdx));
      expect(parserIdx, greaterThan(installIdx),
          reason: 'logger 要早于参数解析，否则解析失败时没日志');
    });
  });

  group('⑪ 真机回归：关闭播放器后 Flutter 变手机布局', () {
    final screen =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('退出播放器时保证窗口不小于桌面断点', () {
      // 【真机现象】关闭播放器后 Flutter 主界面变成底部胶囊导航
      // （手机布局）。根因：`window_manager.setFullScreen(false)` 会恢复
      // 到「进入全屏前的窗口 bounds」，若那时窗口已被缩小，退出后就
      // 落在 < kShellDesktopBreakpoint(1000) 的宽度。
      expect(screen, contains('kShellDesktopBreakpoint'),
          reason: '退出全屏后要检查窗口宽度');
      expect(screen, contains('windowManager.setSize'));
    });

    test('断点常量确实来自 shell 布局定义（单一来源）', () {
      final shell = File('lib/screens/shell/shell_side_drawer.dart')
          .readAsStringSync();
      expect(shell, contains('kShellDesktopBreakpoint = 1000'));
      expect(screen, contains('show kShellDesktopBreakpoint'));
    });
  });

  group('⑫ 真机回归：全黑 + Component is not ready（缺 qt.conf）', () {
    test('CMake 生成 qt.conf（否则 Qt 去编译机绝对路径找 QML 模块）', () {
      // 【真机现象】窗口弹出但全黑，控制台刷满
      //   QWARN QmlComponent: Component is not ready
      //
      // 根因：windeployqt 拷了 qml/ 目录，但没有 qt.conf → Qt 按编译期
      // 写死的绝对路径（D:/a/himi-syncwatch/.../qml）找模块，用户机器
      // 上没有 → `import QtQuick.Controls.Basic` 全失败。
      expect(cmake, contains('qt.conf'));
      expect(cmake, contains('Qml2Imports = ./qml'));
      expect(cmake, contains('Prefix = .'));
    });

    test('Theme / Icons 注册为 QML 单例', () {
      expect(cmake, contains('QT_QML_SINGLETON_TYPE TRUE'));
      expect(cmake, contains('src/qml/Theme.qml'));
      expect(cmake, contains('src/qml/Icons.qml'));
      // 单例属性必须在 qt_add_qml_module 之前设置
      final singletonIdx = cmake.indexOf('QT_QML_SINGLETON_TYPE');
      final moduleIdx = cmake.indexOf('qt_add_qml_module(himi_qt_player');
      expect(singletonIdx, lessThan(moduleIdx));
    });
  });

  group('⑬ UI 功能一致（布局结构 + 命令链路；样式走 EvolveUI）', () {
    // 662 起样式**不再**追 Flutter 像素一致（用户决策：组件库换
    // EvolveUI，「布局差不多，功能一致」），因此本组只锁**功能**：
    // 按钮齐全、右组顺序、命令链路、面板场景。
    final topBar = read('$dir/src/qml/TopBar.qml');
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final mainQmlSrc = read('$dir/src/qml/Main.qml');

    test('顶栏按钮齐全：返回/标题/网速/内核胶囊/显示调节/解码/比例', () {
      for (final token in [
        'Icons.arrowBack',
        'playerState.title',
        'playerState.networkSpeedText',
        'playerState.engineLabel',
        'Icons.tune',
        'Icons.memory',
        'playerState.videoFit',
      ]) {
        expect(topBar, contains(token), reason: '顶栏缺 $token');
      }
      // 倍速/全屏不在顶栏（桌面倍速在底栏；全屏只在底栏，用户明确）
      expect(topBar, isNot(contains('Icons.speed')));
      expect(topBar, isNot(contains('icon: Icons.fullscreen')));
    });

    test('底栏右组顺序：弹幕→多版本→字幕→音轨→选集→倍速→全屏', () {
      final order = [
        'Icons.danmakuOn',
        'Icons.highQuality',
        'Icons.subtitles',
        'Icons.audioTrack',
        'Icons.playlistPlay',
        'Icons.speed',
        'icon: Icons.fullscreen',
      ];
      var cursor = -1;
      for (final token in order) {
        final idx = bottomBar.indexOf(token);
        expect(idx, greaterThan(cursor),
            reason: '右组顺序不对：$token 应在前一项之后');
        cursor = idx;
      }
    });

    test('多版本按钮：仅非房间且多版本显示，角标=版本数', () {
      expect(bottomBar, contains('!playerState.isRoom && playerState.versionCount > 1'));
      expect(bottomBar, contains('playerState.versionCount.toString()'));
      expect(bottomBar, contains('versionClicked'));
      expect(mainQmlSrc, contains('openVersionPanel'));
    });

    test('倍速是图标 + 文字标签（非角标）', () {
      expect(bottomBar, contains('function formatSpeed'));
      final speedBlock = bottomBar.split('Icons.speed')[1];
      expect(speedBlock.split('ControlButton').first, isNot(contains('badge:')),
          reason: '倍速应是文字标签，不是图标角标');
    });

    test('视频区：左缘锁钮 + 左下角 Logo', () {
      expect(mainQmlSrc, contains('Icons.lockOpen'));
      expect(mainQmlSrc, contains('"type": "toggleLock"'));
      expect(mainQmlSrc, contains('!playerState.locked'));
      expect(mainQmlSrc, contains('EpisodeLogo'));
    });

    test('面板场景齐全（选集/音轨/字幕/倍速/版本/解码/显示调节）', () {
      for (final fn in [
        'openEpisodePanel',
        'openAudioPanel',
        'openSubtitlePanel',
        'openSpeedPanel',
        'openVersionPanel',
        'openDecodePanel',
        'openAdjustPanel',
      ]) {
        expect(mainQmlSrc, contains(fn), reason: '缺面板入口 $fn');
      }
    });

    test('自动隐藏 5 秒（Theme.autoHideMs）', () {
      expect(mainQmlSrc, contains('interval: Theme.autoHideMs'));
      expect(mainQmlSrc, contains('controlsVisible'));
    });
  });

  group('⑭ 660：照 Flutter 截图对齐的细节', () {
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final themeQml = read('$dir/src/qml/Theme.qml');
    final mainQmlSrc = read('$dir/src/qml/Main.qml');
    final stateH = read('$dir/src/player_state.h');
    final stateCpp = read('$dir/src/player_state.cpp');

    test('底栏是两行（进度条 + 控制条）', () {
      expect(bottomBar, contains('PlayerSlider'));
      expect(bottomBar, contains('skipPrevious'));
      expect(bottomBar, contains('skipNext'));
      expect(bottomBar, contains('Icons.brightness'));
    });

    test('音量滑杆 96 宽 + 数值 28（Flutter 规格）', () {
      expect(themeQml, contains('fpSliderWidth: 96'));
      expect(themeQml, contains('fpVolumeValueWidth: 28'));
    });

    test('亮度滑杆用黄色 #FFD54F（Flutter 规格）', () {
      expect(themeQml, contains('fpBrightnessIcon: "#FFD54F"'));
    });

    test('进度条 track 4 / thumb 6（Flutter 规格）', () {
      expect(themeQml, contains('fpSeekTrackHeight: 4'));
      expect(themeQml, contains('fpSeekThumbRadius: 6'));
    });

    test('PlayerSlider：EvolveUI ESlider 封装（点击跳转 + 绑定保护）', () {
      final slider = read('$dir/src/qml/PlayerSlider.qml');
      expect(slider, contains('import "evolveui" as EUI'));
      expect(slider, contains('EUI.ESlider'));
      // ESlider 只能拖手柄 → 必须补轨道点击
      expect(slider, contains('MouseArea'));
      // ESlider 拖动赋值会打断外部绑定 → 必须用 Binding 保护
      expect(slider, contains('Binding {'));
      expect(slider, contains('when: !slider.isPressed'));
    });

    test('Main.qml 有 Logo 组件', () {
      expect(mainQmlSrc, contains('EpisodeLogo'));
    });

    test('PlayerState 有 brightness 与 logoUrl', () {
      expect(stateH, contains('Q_PROPERTY(double brightness'));
      expect(stateH, contains('Q_PROPERTY(QString logoUrl'));
      expect(stateCpp, contains('"brightness"'));
    });

    test('图标码点全为 FontAwesome（BMP 内，无 5 位码点问题）', () {
      // 662 换 FontAwesome 后所有码点在 BMP 内，\uXXXX 转义即可；
      // 不得再出现 String.fromCharCode/fromCodePoint 拼接（660 的
      // 5 位码点花屏就是那条路线的回归）。
      final iconsQml = read('$dir/src/qml/Icons.qml');
      final codeLines = iconsQml
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeLines, isNot(contains('String.fromCharCode')));
      expect(codeLines, isNot(contains('String.fromCodePoint')));
      // 码点必须落在 Font Awesome Private Use Area（U+F000~U+F8FF）
      final escapes =
          RegExp(r'\\u([0-9a-fA-F]{4})').allMatches(codeLines).toList();
      expect(escapes.length, greaterThan(30), reason: '图标码点数量不对');
      for (final m in escapes) {
        final cp = int.parse(m.group(1)!, radix: 16);
        expect(cp, inInclusiveRange(0xF000, 0xF8FF),
            reason: '码点 U+${m.group(1)} 不在 FontAwesome PUA 区');
      }
    });

    test('NativePlayerState 有 brightness 字段', () {
      final ns = File(
        'lib/services/player/native/native_player_state.dart',
      ).readAsStringSync();
      expect(ns, contains('this.brightness = 0.5'));
      expect(ns, contains("'brightness': brightness"));
    });

    test('Qt 亮度回调链路连通', () {
      final adapterSrc =
          File('lib/services/player/qt_player_adapter.dart').readAsStringSync();
      final screenSrc =
          File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(adapterSrc, contains('onBrightnessChanged'));
      expect(adapterSrc, contains("'setBrightness'"));
      expect(screenSrc, contains('adapter.onBrightnessChanged'));
    });
  });

  group('⑮ 662：复刻 Flutter 播放器 UI（多版本/锁钮/显示调节/命令链路）', () {
    final topBar = read('$dir/src/qml/TopBar.qml');
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final mainQml = read('$dir/src/qml/Main.qml');
    final stateH = read('$dir/src/player_state.h');
    final adapterSrc =
        File('lib/services/player/qt_player_adapter.dart').readAsStringSync();
    final screenSrc =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('滑杆统一走 PlayerSlider（旧 GlassSlider 已移除）', () {
      // 662：GlassSlider.qml 删除，滑杆职责并入 PlayerSlider
      // （EvolveUI ESlider 封装）：点击跳转、绑定保护、连续 moved/
      // 松手 finished 信号。
      expect(File('$dir/src/qml/GlassSlider.qml').existsSync(), isFalse);
      final slider = read('$dir/src/qml/PlayerSlider.qml');
      expect(slider, contains('signal moved(real v)'));
      expect(slider, contains('signal finished(real v)'));
    });

    test('顶栏画面比例图标随模式切换（fitScreen/cropSimple/zoomOutMap/aspectRatio）', () {
      for (final icon in [
        'Icons.fitScreen',
        'Icons.cropSimple',
        'Icons.zoomOutMap',
        'Icons.aspectRatio',
      ]) {
        expect(topBar, contains(icon), reason: '比例映射缺 $icon');
      }
    });

    test('顶栏按钮走 EvolveUI（ControlButton/EButton 封装）', () {
      // 样式组件库换 EvolveUI（用户决策），芯片/图标钮不再自制玻璃渐变
      expect(topBar, contains('ControlButton'));
      expect(topBar, contains('EUI.EButton'));
      expect(topBar, contains('import "evolveui" as EUI'));
    });

    test('底栏多版本按钮：highQuality + 角标版本数 + 仅非房间多版本', () {
      expect(bottomBar, contains('Icons.highQuality'));
      expect(bottomBar, contains('playerState.versionCount'));
      expect(bottomBar, contains('!playerState.isRoom && playerState.versionCount > 1'));
      expect(bottomBar, contains('versionClicked'));
      expect(mainQml, contains('openVersionPanel'));
    });

    test('底栏倍速是图标 + 文字标签（非角标）', () {
      expect(bottomBar, contains('function formatSpeed'));
      expect(bottomBar, contains('Icons.speed'));
      // 倍速不再用角标显示数值
      final speedBlock = bottomBar.split('Icons.speed')[1];
      expect(speedBlock.split('ControlButton').first,
          isNot(contains('badge:')),
          reason: '倍速应是文字标签，不是图标角标');
    });

    test('全屏按钮只在底栏（用户明确）', () {
      expect(bottomBar, contains('icon: Icons.fullscreen'));
      expect(topBar, isNot(contains('icon: Icons.fullscreen')));
    });

    test('左缘锁钮：圆形 black45 + lock_open/lock + toggleLock 回环', () {
      expect(mainQml, contains('Icons.lockOpen'));
      expect(mainQml, contains('Icons.lock'));
      expect(mainQml, contains('Qt.rgba(0, 0, 0, 0.45)'));
      expect(mainQml, contains('"type": "toggleLock"'));
      // 锁定态顶栏/底栏被 locked 门禁
      expect(mainQml, contains('!playerState.locked'));
    });

    test('版本面板发 selectVersion（Flutter SelectVersion 已有处理）', () {
      expect(mainQml, contains('"type": "selectVersion"'));
      final cmd = File(
        'lib/services/player/native/native_player_command.dart',
      ).readAsStringSync();
      expect(cmd, contains("case 'selectVersion'"));
    });

    test('解码面板三档（智能/硬解/软解）发 setDecodeMode 带 mode', () {
      expect(mainQml, contains('openDecodePanel'));
      expect(mainQml, contains('"type": "setDecodeMode", "mode": id'));
      expect(mainQml, contains('优先硬解，失败回退软解'));
    });

    test('解码档位转发 mpv hwdec（此前空实现切了不生效）', () {
      expect(adapterSrc, contains('set videoDecoders'));
      expect(adapterSrc, contains('resolveWindowsHwdec'));
      expect(adapterSrc, contains("'name': 'hwdec'"));
      expect(adapterSrc, contains("'type': 'setProperty'"));
    });

    test('显示调节面板：6 滑杆 + 2 恢复默认（adjustDisplay/resetDisplay）', () {
      final adjust = read('$dir/src/qml/DisplayAdjustPanel.qml');
      for (final key in [
        'subtitleScale',
        'subtitleMarginY',
        'subtitleDelayMs',
        'danmakuSpeed',
        'danmakuFontSize',
        'danmakuOpacity',
      ]) {
        expect(adjust, contains('"$key"'), reason: '显示调节缺 $key');
      }
      expect(adjust, contains('"subtitle"'));
      expect(adjust, contains('"danmaku"'));
      expect(mainQml, contains('"type": "adjustDisplay"'));
      expect(mainQml, contains('"type": "resetDisplay"'));
      // 六行滑杆全走 PlayerSlider（ESlider 封装，自带标签+数值列）
      expect('PlayerSlider'.allMatches(adjust).length, greaterThanOrEqualTo(6));
    });

    test('PlayerState 声明多版本/显示调节/锁定属性', () {
      for (final prop in [
        'Q_PROPERTY(QVariantList versions',
        'Q_PROPERTY(int versionCount',
        'Q_PROPERTY(int currentVersionIndex',
        'Q_PROPERTY(double subtitleScale',
        'Q_PROPERTY(int subtitleMarginY',
        'Q_PROPERTY(double subtitleDelayMs',
        'Q_PROPERTY(double danmakuSpeed',
        'Q_PROPERTY(double danmakuFontSize',
        'Q_PROPERTY(double danmakuOpacity',
        'Q_PROPERTY(bool locked',
      ]) {
        expect(stateH, contains(prop), reason: 'PlayerState 缺 $prop');
      }
      final stateCpp = read('$dir/src/player_state.cpp');
      expect(stateCpp, contains('"versions"'));
      expect(stateCpp, contains('"subtitleMarginY"'));
      expect(stateCpp, contains('"locked"'));
    });

    test('命令链路修复：Qt payload 命令转发 _handleNativeUiCommand', () {
      // 662 断点回归：此前命令只发 AdapterMediaEvent 无人消费，
      // 选集/字幕/音轨/多版本面板全是死按钮。
      expect(adapterSrc, contains('onNativeUiCommand'));
      expect(adapterSrc, contains('NativePlayerCommand.fromMap'));
      // 664 起命令桥经 QtPlayerSession 转发（fallback = 页面富处理）
      expect(screenSrc, contains('session.fallback = _handleNativeUiCommand'));
    });

    test('CMake 注册 DisplayAdjustPanel.qml', () {
      expect(cmake, contains('DisplayAdjustPanel'));
    });
  });
  group('⑯ EvolveUI 集成（vendor 零补丁 + 上下文注入 + 资源对齐）', () {
    final mainQml = read('$dir/src/qml/Main.qml');
    final evolveDir = Directory('$dir/src/qml/evolveui');

    test('vendor 组件齐全（ETheme/EButton/ESlider/ECard/ELoader）', () {
      for (final name in [
        'ETheme',
        'EButton',
        'ESlider',
        'ECard',
        'ELoader',
      ]) {
        expect(File('${evolveDir.path}/$name.qml').existsSync(), isTrue,
            reason: '缺 vendor 组件 $name');
      }
    });

    test('LICENSE / NOTICE 齐全（MIT 合规）', () {
      expect(File('$dir/third_party/evolveui/LICENSE').existsSync(), isTrue);
      final notice = read('$dir/third_party/evolveui/NOTICE.md');
      expect(notice, contains('EvolveUI'));
      expect(notice, contains('MIT'));
      expect(notice, contains('11f904c'));
    });

    test('FontAwesome 字体 + loader.gif 在资产目录', () {
      final assets = '$dir/third_party/evolveui/assets/fonts';
      expect(File('$assets/loader.gif').existsSync(), isTrue);
      expect(
        File('$assets/fontawesome-free-6.7.2-desktop/otfs/'
                'Font Awesome 6 Free-Solid-900.otf')
            .existsSync(),
        isTrue,
      );
    });

    test('资源路径与上游硬编码一致（PREFIX /new/prefix1，零补丁）', () {
      // EvolveUI 组件内写死 qrc:/new/prefix1/fonts/...，CMake 必须按
      // 同路径注册，组件源码才能零修改复用（NOTICE.md 约定 2）
      expect(cmake, contains('PREFIX "/new/prefix1"'));
      expect(cmake, contains('loader.gif'));
      // qt_add_resources 的 FILES 里是转义空格写法（raw 断言）
      expect(cmake, contains(r'Font\ Awesome\ 6\ Free-Solid-900.otf'));
      // Main.qml 的 FontLoader 走同一条路径
      expect(mainQml,
          contains('qrc:/new/prefix1/fonts/fontawesome-free-6.7.2-desktop/otfs/Font Awesome 6 Free-Solid-900.otf'));
    });

    test('主题/图标字体上下文注入（EvolveUI 约定）', () {
      // 组件内未声明的 theme/iconFont 由根文件 id 沿上下文链解析
      expect(mainQml, contains('EUI.ETheme {'));
      expect(mainQml, contains('id: theme'));
      expect(mainQml, contains('id: iconFont'));
      expect(mainQml, contains('isDark: true'));
      // 沿用 #6366F1 强调色
      expect(mainQml, contains('focusColor: "#6366F1"'));
    });

    test('CI 校验 QtQuick.Effects / Controls 部署（MultiEffect 依赖）', () {
      expect(workflow, contains(r'qml\QtQuick\Effects'));
      expect(workflow, contains(r'qml\QtQuick\Controls'));
    });

    test('全部 QML 图标用 iconFont（FontAwesome），不再引用 Material 字体', () {
      for (final f in evolveDir
          .listSync()
          .whereType<File>()
          .followedBy(
            Directory('$dir/src/qml').listSync().whereType<File>(),
          )) {
        final code = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('Material Icons'), isFalse,
            reason: '${f.path} 还在引用 Material Icons');
      }
    });
  });

  group('⑰ 662 真机截图瑕疵修复（白描边/蓝紫文本/图标码点/按钮底）', () {
    final iconsQml = read('$dir/src/qml/Icons.qml');
    final topBar = read('$dir/src/qml/TopBar.qml');
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final mainQml = read('$dir/src/qml/Main.qml');
    final slider = read('$dir/src/qml/PlayerSlider.qml');
    final controlBtn = read('$dir/src/qml/ControlButton.qml');

    test('danmakuOff 码点是 F4B3（fontTools 对 FA 6.7.2 字体核对过）', () {
      // 真机回归：此前写 F4B5——该码点**不在字体里**，无字形 →
      // 弹幕按钮整个空白（用户截图「弹幕按钮缺失」）。
      // fa-comment-slash 的真值是 U+F4B3。
      expect(iconsQml, contains(r'\uf4b3'));
      expect(iconsQml, isNot(contains(r'\uf4b5')));
    });

    test('滑杆不再带白色描边（ESlider 描边透明化）', () {
      // 真机回归：ESlider 的 backgroundVisible:false 只藏底色，
      // 描边仍画 1px 白 → 三条滑杆带白框。
      expect(slider, contains('backgroundVisible: true'));
      expect(slider, contains('borderColor: "transparent"'));
    });

    test('次级文本走 Theme.mutedText（禁用 getBorderColor(true) 高亮色）', () {
      // 真机回归：getBorderColor(true) 的 true 是「高亮态」→ 返回
      // focusColor(#6366F1)，时间/网速全变蓝紫。
      for (final f in [topBar, bottomBar, read('$dir/src/qml/Panel.qml'),
                       read('$dir/src/qml/DisplayAdjustPanel.qml')]) {
        expect(f, isNot(contains('getBorderColor(true)')));
      }
      expect(topBar, contains('Theme.mutedText'));
      expect(bottomBar, contains('Theme.mutedText'));
      final themeQml = read('$dir/src/qml/Theme.qml');
      expect(themeQml, contains('readonly property color mutedText'));
    });

    test('顶栏高亮由面板真实可见性驱动（无 openMenu 插销残留）', () {
      // 真机回归：字符串插销会残留——面板没显示图标却卡在高亮色。
      expect(mainQml, isNot(contains('openMenu')));
      expect(topBar, contains('decodeOpen'));
      expect(topBar, contains('adjustOpen'));
      expect(mainQml, contains('adjustOpen: adjustPanel.visible'));
      expect(mainQml, contains('decodeOpen: panel.visible'));
    });

    test('图标按钮底自绘（EButton backgroundVisible:false，深底疑云排除）', () {
      expect(controlBtn, contains('backgroundVisible: false'));
      expect(controlBtn, contains('hover.hovered'));
      // 字号档拉层级：36→xl(32) / 28→l(24) / 18→m(20)
      expect(controlBtn, contains('"xl"'));
      expect(controlBtn, contains('"l"'));
      expect(controlBtn, contains('"m"'));
    });

    test('倍速是图标 + 独立 Text 12px（EButton label 强制 bold 弃用）', () {
      expect(bottomBar, contains('Theme.captionSize'));
      final speedBlock = bottomBar.split('Icons.speed')[1];
      expect(speedBlock.split('ControlButton').first,
          isNot(contains('EUI.EButton')));
    });

    test('等待连接提示有深色底衬 + 白色文案（黑底可读）', () {
      expect(mainQml, contains('等待主程序连接'));
      expect(mainQml, contains('Qt.rgba(0, 0, 0, 0.55)'));
    });
  });
  group('⑱ 安装包整合（Qt 播放器随 setup.exe 分发）', () {
    final iss = read('scripts/windows/himi_sync.iss');
    final rel = read('.github/workflows/release.yml');

    test('Inno Setup 递归收录 Release 全目录（含 himi_qt_player 子目录）', () {
      expect(iss, contains(r'Release\*'));
      expect(iss, contains('recursesubdirs'));
    });

    test('release.yml 内联构建 Qt 并放入 Flutter 查找约定目录', () {
      expect(rel, contains("Release/himi_qt_player'"));
      expect(rel, contains('windeployqt'));
    });

    test('CRT 必须进 Qt 目录（DLL 搜索不含父目录，缺了纯净系统启动即败）', () {
      expect(rel, contains('vcruntime140.dll'));
      expect(rel, contains('Qt 目录已捆绑'));
    });

    test('CMake 中间产物不进安装包（build-qt 全拷后清理）', () {
      expect(rel, contains('CMake 中间产物不进安装包'));
      expect(rel, contains('build.ninja'));
      expect(rel, contains('Remove-Item'));
    });

    test('release 产物校验含 Qt exe / CRT / EvolveUI QML 插件', () {
      expect(rel, contains(r'himi_qt_player\himi_qt_player.exe'));
      expect(rel, contains(r'himi_qt_player\qml\QtQuick\Effects'));
      expect(rel, contains(r'himi_qt_player\HimiPlayer\evolveui'));
      expect(rel, contains(r'himi_qt_player\qt.conf'));
    });

    test('Qt 校验步骤必须在 Qt 构建之后（顺序反了会假失败）', () {
      // 663 真机回归：首版把校验放在「编译 Qt 播放器」之前 →
      // 校验时 himi_qt_player\ 还没生成 → 构建假失败。
      final buildIdx = rel.indexOf('- name: 编译 Qt 播放器');
      final verifyIdx = rel.indexOf('校验 Qt 播放器整合');
      expect(buildIdx, greaterThan(0), reason: '找不到 Qt 构建步骤');
      expect(verifyIdx, greaterThan(buildIdx),
          reason: 'Qt 校验必须排在 Qt 构建之后');
      // 且在 Inno 打包之前（打包后再校验就晚了）
      final innoIdx = rel.indexOf('- name: 编译 Inno Setup 安装包');
      expect(verifyIdx, lessThan(innoIdx),
          reason: 'Qt 校验必须排在 Inno 打包之前');
    });

    test('发布仍由 tag 门禁（workflow_dispatch 不会误发 Release）', () {
      expect(rel, contains("startsWith(github.ref, 'refs/tags/')"));
    });
  });
  group('⑲ 664：播不了/面板被盖/回详情页（headers·挖孔·本地化·会话）', () {
    final mainCpp = read('$dir/src/main.cpp');
    final mpvCpp = read('$dir/src/mpv_window.cpp');
    final mainQml = read('$dir/src/qml/Main.qml');
    final panelQml = read('$dir/src/qml/Panel.qml');
    final adjustQml = read('$dir/src/qml/DisplayAdjustPanel.qml');
    final elistQml = read('$dir/src/qml/evolveui/EList.qml');
    final session = read('lib/services/player/qt_player_session.dart');
    final screenSrc =
        File('lib/screens/player/player_screen.dart').readAsStringSync();

    test('headers 透传 mpv（Emby 流鉴权全靠 X-Emby-Token，丢则 401 黑屏）', () {
      expect(mainCpp, contains('"headers"'));
      expect(mainCpp, contains('mpv.load(url, headers)'));
      expect(mpvCpp, contains('http-header-fields'));
    });

    test('视频 HWND 挖孔（SetWindowRgn：浮层不被视频子窗口盖住）', () {
      // 真机回归：面板点不到/锁钮 Logo 不可见 = 子 HWND 盖住 QML
      expect(mpvCpp, contains('SetWindowRgn'));
      expect(mpvCpp, contains('CombineRgn'));
      expect(mainCpp, contains('setContextProperty("mpvWindow"'));
      expect(mainQml, contains('updateOverlayHoles'));
      expect(mainQml, contains('mpvWindow.setOverlayHoles'));
    });

    test('播放控件本地化（mpvWindow 直驱 + 通知 Flutter 双写）', () {
      expect(mainQml, contains('mpvWindow.togglePause()'));
      expect(mainQml, contains('mpvWindow.seekTo('));
      expect(mainQml, contains('mpvWindow.setVolume('));
      expect(mainQml, contains('mpvWindow.setSpeed('));
      expect(mainQml, contains('mpvWindow.selectTrack('));
    });

    test('切轨命令两头接通（main.cpp 处理 selectAudio/selectSubtitle）', () {
      expect(mainCpp, contains('"selectAudio"'));
      expect(mainCpp, contains('"selectSubtitle"'));
      expect(mpvCpp, contains('track-list'));
      expect(mpvCpp, contains('selectTrack'));
    });

    test('Qt 窗口出现即回详情页（会话常驻接管）', () {
      expect(screenSrc, contains('QtPlayerSession.attach'));
      expect(screenSrc, contains('addPostFrameCallback'));
      expect(screenSrc, contains('_safePopPlayerPage'));
      expect(session, contains('static QtPlayerSession? active'));
      expect(session, contains('resolveEpisode'));
      expect(session, contains('resolveVersion'));
    });

    test('会话 headless：显示调节/字幕样式/解码直驱 mpv 属性', () {
      expect(session, contains("'sub-scale'"));
      expect(session, contains("'sub-delay'"));
      expect(session, contains("'sub-pos'"));
      expect(session, contains('DecodeModeService.resolveDecoders'));
    });

    test('面板 EvolveUI 化（ECard 容器 + EList 行）', () {
      expect(panelQml, contains('EUI.ECard'));
      expect(panelQml, contains('EUI.EList'));
      expect(adjustQml, contains('EUI.ECard'));
      expect(adjustQml, contains('EUI.EList'));
    });

    test('EList 扩展 sub/selected（NOTICE 记录）', () {
      expect(elistQml, contains('model.sub'));
      expect(elistQml, contains('model.selected'));
      expect(cmake, contains('EList'));
      final notice = read('$dir/third_party/evolveui/NOTICE.md');
      expect(notice, contains('EList.qml'));
      expect(notice, contains('有扩展'));
    });
  });
}

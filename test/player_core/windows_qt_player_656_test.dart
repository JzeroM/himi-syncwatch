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
    mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
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
      // 669：HDR 晚绑定——setMpvString（init 前 option / init 后 property），
      // 运行时可重设（进程提前拉起，档位随媒体信息晚到）。
      expect(mpvCpp,
          contains('setMpvString("d3d11-output-format", QStringLiteral("rgb10_a2"))'));
      expect(mpvCpp,
          contains('setMpvString("target-colorspace-hint", QStringLiteral("yes"))'));
      expect(mpvCpp,
          contains('setMpvString("target-prim", QStringLiteral("bt.2020"))'));
      expect(mpvCpp, contains('void MpvWindow::setHdrMode(bool hdr, bool hlg)'));
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
    test('顶栏含返回/标题/网速/显示调节/解码/比例', () {
      // 659：图标改为走 Icons 单例（与 Flutter NativePlayerIcons 同码点）。
      // 662：照 Flutter `player_top_bar.dart` 修正——
      //   解码图标是 memory（原 highQuality 是「HD」错字形）；
      //   新增 tune（显示调节）；倍速/全屏**不在顶栏**（桌面倍速在底栏、
      //   全屏只在底栏，用户明确）。
      // 679：返回按钮已按用户要求移除（退出统一走 Flutter 面板窗关闭）
      for (final icon in [
        'Icons.memory',
        'Icons.tune',
      ]) {
        expect(topBar, contains(icon), reason: '顶栏缺 $icon');
      }
      expect(topBar, isNot(contains('Icons.arrowBack')),
          reason: '679：返回按钮已移除');
      expect(topBar, contains('playerState.title'));
      expect(topBar, contains('playerState.networkSpeedText'));
      // 667：内核胶囊已删（Qt 恒 MPV，用户要求去引擎控件）
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
      // 672：patchValue 是 Q_INVOKABLE **方法**（非属性），排除方法调用
      missing.removeWhere((m) => m == 'patchValue');
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

    test('679：宿主窗口改为无边框（去掉最小化/最大化/关闭三钮）', () {
      // 用户要求：Qt 窗不要系统窗口控件。无边框后拖动/缩放由
      // TopBar 拖拽区（startSystemMove）+ startSystemResize 接管。
      final codeLines = read('$dir/src/qml/Main.qml')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(codeLines, contains('flags: Qt.FramelessWindowHint'));
      expect(codeLines, isNot(contains('flags: Qt.Window\n')));
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
    final mainQmlSrc = (read('$dir/src/qml/Overlay.qml') + read('$dir/src/qml/Main.qml'));

    test('顶栏按钮齐全：标题/网速/显示调节/解码/比例（返回已移除）', () {
      for (final token in [
        'playerState.title',
        'playerState.networkSpeedText',
        'Icons.tune',
        'Icons.memory',
        'videoFitMode',
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
        // 677：全屏图标改为双向（全屏 / 退出全屏），按三元表达式定位
        'Icons.closeFullscreen',
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

    test('视频区：左下角 Logo（668 锁钮已去除）', () {
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
    final mainQmlSrc = (read('$dir/src/qml/Overlay.qml') + read('$dir/src/qml/Main.qml'));
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
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
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
      // 样式组件库换 EvolveUI（用户决策），芯片/图标钮不再自制玻璃渐变。
      // 667：内核胶囊已删（Qt 恒 MPV），顶栏全走 ControlButton（EButton 封装）
      expect(topBar, contains('ControlButton'));
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
      // 677：图标改为双向三元表达式（全屏 / 退出全屏）
      expect(bottomBar, contains('Icons.fullscreen'));
      expect(bottomBar, contains('Icons.closeFullscreen'));
      expect(topBar, isNot(contains('Icons.fullscreen')));
      expect(topBar, isNot(contains('Icons.closeFullscreen')));
    });

    test('668 锁钮已去除（含 locked 门禁清理）', () {
      expect(mainQml, isNot(contains('lockButton')));
      expect(mainQml, isNot(contains('"type": "toggleLock"')));
      expect(mainQml, isNot(contains('!playerState.locked')));
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
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
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
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
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
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
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

    test('控件悬浮层架构（透明顶层窗 + mpvWindow 上下文）', () {
      expect(mainCpp, contains('setContextProperty("mpvWindow"'));
      expect(mainCpp, contains('setDefaultAlphaBuffer(true)'));
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

    test('面板 EvolveUI 化（ECard 容器 + modelData 行）', () {
      // 665：Panel 行弃用 EList（缺失角色报错 → 空面板），改 modelData
      // 自绘行；容器保持 ECard。DisplayAdjustPanel 仍用 EList（恢复默认行）。
      expect(panelQml, contains('EUI.ECard'));
      expect(panelQml, contains('modelData.display'));
      expect(adjustQml, contains('EUI.ECard'));
      expect(adjustQml, contains('恢复默认'));
      expect(adjustQml, isNot(contains('EUI.EList')));
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
  group('⑳ 665：视频满铺全窗（控件带挖孔，观感同 Flutter）', () {
    final mainCpp = read('$dir/src/main.cpp');
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));

    test('inset 归零：视频满铺（不再被上下让位逼出横向黑边）', () {
      // 真机回归：48/96 inset 把视频压成中间一块 → 「被控件包裹」。
      expect(mainCpp, contains('setOverlayInsets(0, 0)'));
    });

    test('668：挖孔退役，控件走透明悬浮窗（真合成零黑底）', () {
      expect(mpvCpp, isNot(contains('SetWindowRgn')));
      expect(mainQml, isNot(contains('setOverlayHoles')));
    });
  });
  group('㉑ 665：功能全量对齐 Flutter（面板/手势/弹幕/自动下一集）', () {
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
    final panelQml = read('$dir/src/qml/Panel.qml');
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final topBar = read('$dir/src/qml/TopBar.qml');
    final mpvCpp = read('$dir/src/mpv_window.cpp');
    final stateH = read('$dir/src/player_state.h');

    test('面板行 modelData 渲染（空面板回归：EList 缺失角色报错）', () {
      expect(panelQml, contains('modelData.display'));
      expect(panelQml, contains('modelData.sub'));
      expect(panelQml, contains('modelData.selected'));
    });

    test('无 ✕ 关闭钮：toggle 收回 + 点空白收回', () {
      expect(panelQml, isNot(contains('Icons.close')));
      // 入口函数首行 toggle（再点同控件收回）
      expect(mainQml, contains('if (panelOpen && panel.title === "字幕") { closePanels(); return }'));
      expect(mainQml, contains('if (adjustOpen) { closePanels(); return }'));
      // 点视频区：有面板→收回；无→切换控件（Flutter _onVideoAreaTap）
      expect(mainQml, contains('if (root.panelOpen || root.adjustOpen)'));
      expect(mainQml, contains('function closePanels()'));
    });

    test('手势：双击播放暂停 + 右键标记（672 拖拽类全去除）', () {
      expect(mainQml, contains('onDoubleClicked'));
      expect(mainQml, contains('tapTimer'));
      // 拖拽 seek/音量/亮度按用户要求去除
      expect(mainQml, isNot(contains('seekAccum')));
      expect(mainQml, isNot(contains('startVolume')));
      expect(mainQml, contains('Qt.RightButton'));
    });

    test('面板内容对齐：倍速标题/本地字幕行/选集卡片/内核面板', () {
      expect(mainQml, contains('panel.title = "倍速"'));
      expect(mainQml, contains('加载本地字幕文件...'));
      expect(mainQml, contains('subDialog'));
      expect(mainQml, contains('panel.cardMode = true'));
      expect(mainQml, isNot(contains('openKernelPanel')));
    });

    test('播完自动下一集 + 所有剧集播放完毕提示', () {
      expect(mainQml, contains('onPlaybackEnded'));
      expect(mainQml, contains('所有剧集播放完毕'));
    });

    test('弹幕 ASS 旁路（secondary-sid 双字幕轨）', () {
      expect(mpvCpp, contains('setDanmakuAss'));
      expect(mpvCpp, contains('secondary-sid'));
      expect(mpvCpp, contains('sub-add'));
      expect(mainQml, contains('buildDanmakuAss'));
      expect(mainQml, contains('onDanmakuChanged'));
      expect(stateH, contains('Q_PROPERTY(QVariantList danmakuItems'));
    });

    test('跳过片头/片尾胶囊（片段字段 + skipSegmentClicked）', () {
      expect(stateH, contains('Q_PROPERTY(qint64 segmentIntroEndMs'));
      expect(stateH, contains('Q_PROPERTY(qint64 segmentOutroStartMs'));
      expect(bottomBar, contains('跳过片头'));
      expect(bottomBar, contains('skipSegmentClicked'));
      expect(mainQml, contains('skipSegmentLocal'));
    });

    test('画面比例本地循环（panscan/video-aspect-override/video-unscaled）', () {
      expect(mainQml, contains('cycleVideoFitLocal'));
      expect(mainQml, contains('"panscan"'));
      expect(mainQml, contains('"video-aspect-override"'));
      expect(mainQml, contains('"video-unscaled"'));
      expect(topBar, contains('videoFitMode'));
    });

    test('视频窗口点击穿透（手势落到 QML 的前提）', () {
      expect(mpvCpp, contains('WS_EX_TRANSPARENT'));
    });

    test('本地字幕 + 命令通道（sub-add 走 file:// URL）', () {
      expect(mpvCpp, contains('MpvWindow::command'));
      expect(mainQml, contains('"sub-add"'));
    });
  });
  group('㉒ 667：透明控件层/面板排版/恢复默认/去引擎/点击修复', () {
    final mainQml = (read('$dir/src/qml/Overlay.qml')
        + read('$dir/src/qml/Main.qml')
        + read('$dir/src/qml/PlayerShortcuts.qml')
        + read('$dir/src/qml/VideoGestures.qml'));
    final topBar = read('$dir/src/qml/TopBar.qml');
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final adjustQml = read('$dir/src/qml/DisplayAdjustPanel.qml');
    final logoQml = read('$dir/src/qml/EpisodeLogo.qml');
    final mpvCpp = read('$dir/src/mpv_window.cpp');

    test('挖孔机制全退役（668 起悬浮层真合成）', () {
      expect(mpvCpp, isNot(contains('CreateRoundRectRgn')));
    });

    test('ASS 渐变遮罩已退役（669：玻璃条自画渐变，防顶/底双重压暗）', () {
      expect(mainQml, isNot(contains('pushScrim')));
      expect(mainQml, isNot(contains('Style: Scrim')));
      // 弹幕开关只增减弹幕行（重生成，不藏轨）
      expect(mainQml, contains('danmakuOn ? playerState.danmakuItems : []'));
      expect(mainQml, contains('danmakuBuildTimer.restart()'));
    });

    test('液态玻璃材质（渐变玻璃条/玻璃卡/玻璃滑杆）', () {
      expect(topBar, contains('Theme.barGradientSolid'));
      expect(bottomBar, contains('Theme.barBottomSolid'));
      expect(adjustQml, contains('cardColor: Qt.rgba(0.07, 0.07, 0.09, 0.72)'));
      expect(logoQml, isNot(contains('radius: 10')));
    });

    test('面板排版修复：不能 top+bottom 双锚（撑满高=行漂中部根因）', () {
      // Panel 实例只锚 top，高度由内容自适应
      expect(mainQml, isNot(contains('anchors.bottom: bottomBar.top\n        anchors.rightMargin: Theme.panelRight\n        anchors.topMargin: Theme.panelTopOffset\n        anchors.bottomMargin: 8\n        visible: root.panelOpen')));
    });

    test('显示调节两个恢复默认（自绘行，默认值同 Flutter）', () {
      expect(adjustQml, contains('subResetMouse'));
      expect(adjustQml, contains('dmResetMouse'));
      expect(adjustQml, contains('"恢复默认"'));
      // Flutter 默认：字幕 1.00×/22px/0.0s、弹幕 0.70×/0.50×/80%
      expect(adjustQml, contains('playerState.subtitleMarginY === 22'));
      expect(adjustQml, contains('playerState.danmakuOpacity - 0.8'));
    });

    test('引擎控件已删（Qt 恒 MPV）', () {
      final code = topBar
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('engineLabel')));
      expect(code, isNot(contains('kernel')));
      expect(mainQml, isNot(contains('openKernelPanel')));
    });

    test('点击唤出不立马隐藏（按下瞬间快照判定）', () {
      expect(mainQml, contains('property bool wasVisible'));
      // 669：显隐走共享态 playerState.controlsVisible（双窗手势都能唤出）
      expect(mainQml, contains('wasVisible = playerState.controlsVisible'));
      expect(mainQml, contains('if (videoArea.wasVisible)'));
    });
  });
  group('㉓ 668：液态玻璃播放器（透明悬浮层真合成）', () {
    final overlayQml = read('$dir/src/qml/Overlay.qml');
    final mainQmlSrc = read('$dir/src/qml/Main.qml');
    final shortcuts = read('$dir/src/qml/PlayerShortcuts.qml');
    final mainCpp = read('$dir/src/main.cpp');
    final mpvH = read('$dir/src/mpv_window.h');

    test('透明悬浮层窗口（Qt.Tool|Frameless + 透明底 = 逐像素合成）', () {
      expect(overlayQml, contains('Qt.Tool | Qt.FramelessWindowHint'));
      expect(overlayQml, contains('color: "transparent"'));
      expect(mainCpp, contains('setDefaultAlphaBuffer(true)'));
      expect(mainCpp, contains('Overlay.qml'));
    });

    test('悬浮层恒贴附宿主客户区（移动/缩放/最小化同步）', () {
      expect(mainCpp, contains('MapWindowPoints'));
      expect(mainCpp, contains('syncTimer'));
      expect(mainCpp, contains('overlay->raise()'));
    });

    test('全屏/退出走宿主窗口（控件在悬浮层）', () {
      expect(mpvH, contains('toggleHostFullscreen'));
      expect(overlayQml, contains('mpvWindow.toggleHostFullscreen'));
    });

    test('快捷键两窗共用（焦点任一窗都有效）', () {
      expect(shortcuts, contains('mpvWindow.togglePause'));
      expect(mainQmlSrc, contains('PlayerShortcuts'));
      expect(overlayQml, contains('PlayerShortcuts'));
    });

    test('液态玻璃：滑杆半透明轨道 + 面板玻璃卡', () {
      final slider = read('$dir/src/qml/PlayerSlider.qml');
      expect(slider, contains('Qt.rgba(1, 1, 1, 0.14)'));
      expect(read('$dir/src/qml/Panel.qml'),
          contains('cardColor: Qt.rgba(0.07, 0.07, 0.09, 0.72)'));
    });

    test('视频宿主窗口极简（只承载视频+标题+快捷键）', () {
      expect(mainQmlSrc, contains('ApplicationWindow'));
      expect(mainQmlSrc, isNot(contains('BottomBar')));
    });
  });
  group('㉔ 668 CI 修复：main.cpp 编译错误回归', () {
    final mainCpp = read('$dir/src/main.cpp');

    test('Qt 枚举双冒号（Qt::FramelessWindowHint，笔误 Qt. 编译失败）', () {
      expect(mainCpp, contains('Qt::Tool | Qt::FramelessWindowHint'));
      expect(mainCpp, isNot(contains('Qt.FramelessWindowHint')));
    });

    test('mpv_node 无 map 成员（NODE_MAP 同用 u.list）', () {
      // 673 CI：shinchiro client.h 的 mpv_node 联合体只有
      // string/flag/int64/double_/list/ba——u.map 编译不过（C2039）
      final mpvCpp6 = read('$dir/src/mpv_window.cpp');
      expect(mpvCpp6, isNot(contains('t.u.map')));
      expect(mpvCpp6, contains('t.u.list->keys'));
    });

    test('WId 就是 quintptr（reinterpret_cast 同型转换编译不过）', () {
      // Qt 6 的 WId = quintptr，reinterpret_cast<quintptr>(winId()) 非法
      expect(mainCpp, isNot(contains('reinterpret_cast<quintptr>')));
    });

    test('最小化判定走 visibility（QWindow 没有 isMinimized）', () {
      expect(mainCpp, contains('QWindow::Minimized'));
      // 只查代码行（注释里允许出现 isMinimized 说明文字）
      final code = mainCpp
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('isMinimized')));
    });
  });
  group('㉕ 669：悬浮层可见性根治 + 起播直接弹 Qt 窗口', () {
    final overlayQml = read('$dir/src/qml/Overlay.qml');
    final hostQml = read('$dir/src/qml/Main.qml');
    final gestures = read('$dir/src/qml/VideoGestures.qml');
    final mainCpp2 = read('$dir/src/main.cpp');
    final mpvH2 = read('$dir/src/mpv_window.h');
    final stateH2 = read('$dir/src/player_state.h');
    final screen = read('lib/screens/player/player_screen.dart');
    final qtAdapter = read('lib/services/player/qt_player_adapter.dart');

    test('A1 owned 窗根治 z-order（owned 窗永远盖住宿主 = 结构性保证）', () {
      expect(mainCpp2, contains('setTransientParent(host)'));
      expect(mainCpp2, contains('GWLP_HWNDPARENT'));
    });

    test('A2 手势双窗共用（VideoGestures 两份实例 + 共享显隐态）', () {
      expect(gestures, contains('tapTimer'));
      expect(gestures, contains('onDoubleClicked'));
      expect(hostQml, contains('VideoGestures'));
      expect(overlayQml, contains('VideoGestures'));
      // 控件显隐共享态（任一实例点击都能唤出）
      expect(stateH2, contains('controlsVisible'));
      expect(stateH2, contains('WRITE setControlsVisible'));
    });

    test('A3 透明渲染保障（D3D11 后端 + 隐藏创建→显示 + alpha 底）', () {
      expect(mainCpp2, contains('QSGRendererInterface::Direct3D11'));
      expect(overlayQml, contains('visible: false'));
      expect(mainCpp2, contains('overlay->show()'));
      // alpha≈0 全窗底：堵死透明像素点击穿透
      expect(overlayQml, contains('Qt.rgba(0, 0, 0, 0.004)'));
    });

    test('A4 自检日志（alphaBuffer/几何/QML 就绪落盘）', () {
      expect(mainCpp2, contains('alphaBufferSize'));
      expect(mainCpp2, contains('[overlay] 创建完成'));
      expect(overlayQml, contains('[overlay] QML 就绪'));
    });

    test('A5 渐变遮罩退役（玻璃条自画渐变）', () {
      expect(overlayQml, isNot(contains('pushScrim')));
    });

    test('B1 起播直接弹 Qt 窗口（预启动单飞 + 首帧隐藏播放页）', () {
      expect(screen, contains('_qtLaunchSingleFlight'));
      expect(screen, contains('_ensureQtPlayerProcess'));
      expect(screen, contains('if (_qtUiHidden)'));
      // B5：房间不动（门禁只挂非房间路径）
      expect(screen, contains('widget.roomCode == null'));
    });

    test('B2 HDR 晚绑定（先 setHdrMode 再 load）', () {
      expect(qtAdapter, contains("'type': 'setHdrMode'"));
      expect(mpvH2, contains('Q_INVOKABLE void setHdrMode(bool hdr, bool hlg)'));
      expect(mainCpp2, contains('QLatin1String("setHdrMode")'));
      expect(screen, contains('adapter.setHdrMode(hdr: hdr, hlg: hlg)'));
    });

    test('B4 回退兜底（失败恢复 UI + 未交接关孤儿窗）', () {
      expect(screen, contains('_abandonQtTakeover'));
      expect(screen, contains('_qtHandedOver'));
      expect(screen, contains('MpvSessionPlatform.closeQtPlayer'));
    });
  });
  group('㉖ 670：QML 加载真根因回归 + CI 冒烟 + 启动预热', () {
    final mainCpp3 = read('$dir/src/main.cpp');
    final stateH3 = read('$dir/src/player_state.h');
    final overlayQml3 = read('$dir/src/qml/Overlay.qml');
    final hostQml3 = read('$dir/src/qml/Main.qml');
    final pipeDart3 = read('lib/services/player/qt_player_pipe.dart');
    final sessionPlat = read('lib/services/player/mpv_session_platform.dart');
    final mainDart = read('lib/main.dart');
    final relWorkflow = read('.github/workflows/release.yml');
    final qtWorkflow = read('.github/workflows/windows-qt-player.yml');

    test('真根因回归：用 ApplicationWindow 的文件必须 import Controls.Basic', () {
      // 670 真根因：Main.qml 缺 `import QtQuick.Controls.Basic` →
      // 「ApplicationWindow 不是一种类型」→ 进程加载即退 → 用户看到的
      // 全是回退窗（控件不可见/出窗慢的总根源）。
      expect(hostQml3, contains('import QtQuick.Controls.Basic'));
    });

    test('QML 类型-导入一致性（逐文件表驱动）', () {
      final rules = <String, String>{
        'ApplicationWindow': 'import QtQuick.Controls.Basic',
        'FileDialog': 'import QtQuick.Dialogs',
        'RowLayout': 'import QtQuick.Layouts',
        'ColumnLayout': 'import QtQuick.Layouts',
      };
      final qmlDir = Directory('$dir/src/qml');
      for (final f in qmlDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.qml')) continue;
        final body = f.readAsStringSync();
        rules.forEach((type, imp) {
          if (body.contains(RegExp('\b$type\b'))) {
            expect(body, contains(imp),
                reason: '${f.path} 用了 $type 但缺 $imp');
          }
        });
      }
    });

    test('CI 冒烟自检（--selftest：运行时 QML 加载错误 CI 直接红）', () {
      expect(mainCpp3, contains('selftest'));
      expect(mainCpp3, contains('[selftest] QML 加载通过'));
      // 必须是**纯开关**（无 valueName）：照抄 --hdr 三参会变成带值
      // 选项，裸 --selftest 报 "Missing value" 直接 exit(1)（670 CI 踩过）
      expect(mainCpp3,
          contains('parser.addOption({"selftest", "QML 加载冒烟自检后退出"});'));
      expect(mainCpp3, contains('parser.isSet("prewarm")'));
      // 两个 workflow 都要跑（Qt 专用构建 + 发布构建）
      expect(qtWorkflow, contains('--selftest'));
      expect(relWorkflow, contains('--selftest'));
    });

    test('启动预热（全局单飞 + 隐藏待命 + 秒出窗）', () {
      expect(sessionPlat, contains('ensureQtPlayer'));
      expect(sessionPlat, contains('prewarmQtPlayer'));
      expect(mainDart, contains('MpvSessionPlatform.prewarmQtPlayer()'));
      expect(pipeDart3, contains("'--prewarm'"));
      expect(mainCpp3, contains('prewarm'));
      // 首条 load = 媒体就绪 → 弹窗（秒出窗的落点）
      expect(mainCpp3, contains('showWindows()'));
    });

    test('预热防孤儿（管道断开未恢复即退出）', () {
      expect(mainCpp3, contains('管道断开且未恢复，退出'));
    });

    test('标题栏诊断码（截图即诊断：GLASS/SAFE:alpha0）', () {
      expect(stateH3, contains('windowDiag'));
      expect(hostQml3, contains('playerState.windowDiag'));
      expect(mainCpp3, contains('SAFE:alpha0'));
    });

    test('SAFE 深底降级（alpha 失效时保证控件可见）', () {
      expect(overlayQml3, contains('property bool safeMode'));
      expect(overlayQml3, contains('root.safeMode'));
      expect(mainCpp3, contains('setProperty("safeMode", true)'));
    });

    test('加载期控件常驻（playerReady 前不自动隐藏）', () {
      expect(overlayQml3, contains('playerState.playerReady'));
    });
  });
  group('㉗ 671：交互修复全集（弹幕不断供/滑杆/前台/缓存/面板）', () {
    final mainCpp4 = read('$dir/src/main.cpp');
    final overlay4 = read('$dir/src/qml/Overlay.qml');
    final panel4 = read('$dir/src/qml/Panel.qml');
    final bottom4 = read('$dir/src/qml/BottomBar.qml');
    final adjust4 = read('$dir/src/qml/DisplayAdjustPanel.qml');
    final eSlider4 = read('$dir/src/qml/evolveui/ESlider.qml');
    final pSlider4 = read('$dir/src/qml/PlayerSlider.qml');
    final screen4 = read('lib/screens/player/player_screen.dart');
    final session4 = read('lib/services/player/qt_player_session.dart');
    final adapter4 = read('lib/services/player/qt_player_adapter.dart');
    final pipe4 = read('lib/services/player/qt_player_pipe.dart');
    final plat4 = read('lib/services/player/mpv_session_platform.dart');

    test('弹幕不断供：到达即推送 + 播放页隐身存活（不立即 pop）', () {
      // 根因：弹幕到达不触发推送 + pop 后管线断供 → Qt 永远收不到弹幕
      expect(screen4, contains('if (!_disposed) _syncNativePanelData()'));
      expect(screen4, contains('不再立即 pop'));
      expect(screen4, isNot(contains('立即回详情页（下一帧 pop')));
      // 切集驱动页面管线重拉弹幕
      expect(session4, contains('onEpisodeSwitched'));
      expect(screen4, contains('_loadDanmaku()'));
    });

    test('会话替换退场（微任务判定自替换不误杀）', () {
      expect(session4, contains('old.onReplaced?.call()'));
      expect(screen4, contains('identical(_mySession, QtPlayerSession.active)'));
    });

    test('A1 死适配器不得复用（单飞缓存失效）', () {
      expect(plat4, contains('_qtLaunched'));
      expect(plat4, contains('launched.isAlive'));
      expect(adapter4, contains('bool get isAlive'));
      expect(pipe4, contains('bool get isClosed'));
      // closeQtPlayer 同步作废缓存
      expect(plat4, contains('_qtLaunchFuture = null;'));
    });

    test('A2 强制前台（Qt 窗口不再落在 Flutter 后面）', () {
      expect(mainCpp4, contains('SetForegroundWindow'));
      expect(mainCpp4, contains('AttachThreadInput'));
      expect(mainCpp4, contains('forceForeground()'));
    });

    test('A3 滑杆拖动即时跟随（平滑只在程序性跳转）', () {
      expect(eSlider4, contains('enabled: !root.isPressed'));
      expect(eSlider4, contains('function mapXToValue'));
      expect(pSlider4, contains('slider.mapXToValue'));  // 675 起收进 applyAt(x)
    });

    test('A4 播放镜像字段以 mpv 为准（图标不失配）', () {
      expect(mainCpp4, contains('filtered.remove(QStringLiteral("paused"))'));
      expect(mainCpp4, contains('filtered.remove(QStringLiteral("positionMs"))'));
    });

    test('A5 面板反馈链（倍速回传 + 状态回推）', () {
      // 677：倍速不再走 `forwardSpeed`（就地转发）——改为「上报意图」
      //（`_emitTransportIntent`），由播放页决定广播（房主）或丢弃（观众）。
      expect(adapter4, contains('_emitTransportIntent'));
      expect(adapter4, contains('onTransportIntent'));
      expect(screen4, contains('session.fallback = _handleNativeUiCommand'));
    });

    test('A6 root.hideTimer 笔误回归（id 不是 root 属性）', () {
      expect(overlay4, isNot(contains('root.hideTimer')));
    });

    test('B1 音量/亮度玻璃胶囊 + 数值无 %', () {
      expect(bottom4, contains('radius: 16'));
      expect(bottom4, contains('Math.round(playerState.volume * 100)'));
      expect(bottom4, contains('Math.round(playerState.brightness * 100)'));
      expect(bottom4, isNot(contains('valueSuffix: "%"')));
      expect(adjust4, isNot(contains('valueSuffix: "%"')));
    });

    test('B2 选集面板：横卡原始宽/列数控件/自动定位/纵向滚动条', () {
      expect(panel4, contains('cardWidth: 280'));
      expect(panel4, contains('maxColumns'));
      expect(panel4, contains('positionViewAtIndex'));
      expect(panel4, contains('vHandle'));  // 672：自绘固定长度滚动条
      expect(panel4, contains('root.columns - 1'));
      expect(panel4, contains('root.columns + 1'));
      // 总宽不超播放器宽（列数上限收紧）
      expect(panel4, contains('Math.floor(((parent ? parent.width : 1280)'));
    });
  });
  group('㉘ 672：滑杆镜像/轨道真相/滚轮/右键标记/滚动条', () {
    final state5 = read('$dir/src/player_state.h');
    final stateCpp5 = read('$dir/src/player_state.cpp');
    final mainCpp5 = read('$dir/src/main.cpp');
    final overlay5 = read('$dir/src/qml/Overlay.qml');
    final bottom5 = read('$dir/src/qml/BottomBar.qml');
    final gestures5 = read('$dir/src/qml/VideoGestures.qml');
    final panel5 = read('$dir/src/qml/Panel.qml');
    final mpvH5 = read('$dir/src/mpv_window.h');
    final settings5 = read('lib/screens/settings/intro_outro_settings_screen.dart');

    test('A1 patchValue 本地镜像（滑杆不跳位的根治）', () {
      expect(state5, contains('Q_INVOKABLE void patchValue'));
      expect(stateCpp5, contains('void PlayerState::patchValue'));
      expect(overlay5, contains('root.patchState("volume"'));
      expect(overlay5, contains('root.patchState("brightness"'));
      expect(overlay5, contains('root.patchState("positionMs"'));
    });

    test('A2 恢复默认全联动（一次镜像六值）', () {
      expect(overlay5, contains('patchState("subtitleScale", 1.0)'));
      expect(overlay5, contains('patchState("subtitleMarginY", 22)'));
      expect(overlay5, contains('patchState("danmakuOpacity", 0.8)'));
    });

    test('A3 面板点选即时镜像（勾选不冻结）', () {
      expect(overlay5, contains('patchState("speed"'));
      expect(overlay5, contains('patchState("decodeMode"'));
      expect(overlay5, contains('patchState("selectedAudioId"'));
      expect(overlay5, contains('patchState("currentVersionIndex"'));
    });

    test('B1 轨道选中真相对齐安卓/鸿蒙（顶层 id）', () {
      expect(state5, contains('selectedAudioId'));
      expect(state5, contains('selectedSubtitleId'));
      expect(mainCpp5, contains('selectedAudioId'));
      expect(mainCpp5, contains('activeTrackIndex'));
      expect(mpvH5, contains('activeTrackIndex'));
      // 默认「关闭字幕」打勾 + 空面板兜底
      expect(overlay5, contains('playerState.selectedSubtitleId <= 0'));
      expect(overlay5, contains('无可用音轨'));
    });

    test('C1 拖拽类手势全去除（seek/音量/亮度）', () {
      expect(gestures5, isNot(contains('seekAccum')));
      expect(gestures5, isNot(contains('startVolume')));
      expect(gestures5, isNot(contains('onPositionChanged: (mouse) => {\n            root.doShowControls()\n            if (!pressed')));
      // 双击暂停保留
      expect(gestures5, contains('onDoubleClicked'));
    });

    test('C2 滑杆选中态 + 滚轮调节', () {
      expect(bottom5, contains('signal sliderSelected'));
      expect(bottom5, contains('signal wheelAdjust'));
      expect(overlay5, contains('function adjustByWheel'));
      expect(gestures5, contains('wheelHandler'));
    });

    test('D1 跳过胶囊 skipPrompt 驱动 + 放音量右侧', () {
      expect(bottom5, contains('playerState.skipPrompt === "intro"'));
      expect(bottom5, contains('id: skipCapsule'));
      expect(overlay5, contains('"type": "skipSegment"'));
    });

    test('D2 右键画面任意位置标记（范围 ≤10% / ≥70%）', () {
      expect(gestures5, contains('Qt.RightButton'));
      expect(gestures5, contains('showSegmentMenu'));
      expect(overlay5, contains('function markSegment'));
      expect(overlay5, contains('dur * 0.10'));
      expect(overlay5, contains('dur * 0.70'));
      expect(overlay5, contains('"type": "setSegmentMark"'));
    });

    test('D3 设置页操作说明含 Windows 右键', () {
      expect(settings5, contains('鼠标右击'));
      expect(settings5, contains('10%'));
      expect(settings5, contains('70%'));
    });

    test('E 选集滚动条固定长度 + 加粗（自绘）', () {
      expect(panel5, contains('height: 96'));
      expect(panel5, contains('width: 10'));
      expect(panel5, contains('vHandle'));
    });
  });
  group('㉙ 673：封面加载提速（磁盘缓存/目标解码/预取）', () {
    final mainCpp6 = read('$dir/src/main.cpp');
    final panel6 = read('$dir/src/qml/Panel.qml');
    final overlay6 = read('$dir/src/qml/Overlay.qml');

    test('网络磁盘缓存（对齐安卓磁盘 LRU：重开面板秒开）', () {
      expect(mainCpp6, contains('QQmlNetworkAccessManagerFactory'));
      expect(mainCpp6, contains('QNetworkDiskCache'));
      expect(mainCpp6, contains('setNetworkAccessManagerFactory'));
      expect(mainCpp6, contains('64 * 1024 * 1024'));
    });

    test('卡片封面目标像素解码（sourceSize，对齐安卓 inSampleSize）', () {
      expect(panel6, contains('sourceSize: Qt.size('));
    });

    test('播放期封面预取（同尺寸预热缓存，首开面板秒开）', () {
      expect(overlay6, contains('Qt.size(544, 300)'));
      expect(overlay6, contains('model: playerState.episodes'));
    });
  });
  group('㉚ 674：patchValue 真凶回归/容错镜像/一列默认/TV 标记面板', () {
    final stateH7 = read('$dir/src/player_state.h');
    final overlay7 = read('$dir/src/qml/Overlay.qml');
    final bottom7 = read('$dir/src/qml/BottomBar.qml');
    final panel7 = read('$dir/src/qml/Panel.qml');

    test('A1 真凶回归：patchValue 必须在 public 区（私有 QML 调不到）', () {
      // 真机回归「所有控件几乎都失效」：Qt 6.8 QML 只暴露公开
      // Q_INVOKABLE，私有声明 → "patchValue is not a function"
      final pub = stateH7.indexOf('public:');
      final priv = stateH7.lastIndexOf('private:');
      final pv = stateH7.indexOf('Q_INVOKABLE void patchValue');
      expect(pv, greaterThan(pub), reason: 'patchValue 必须在 public: 之后');
      expect(pv, lessThan(priv), reason: 'patchValue 不得掉回 private: 之后');
    });

    test('A2 容错镜像（try/catch，镜像失效不杀处理器）', () {
      expect(overlay7, contains('function patchState'));
      expect(overlay7, contains('try {'));
      // helper 体内恰好一处直调（防replaceAll误伤成自递归——踩过）
      expect('playerState.patchValue('.allMatches(overlay7).length, 1);
    });

    test('A3 命令先行、镜像后置（handlePanelItem）', () {
      expect(overlay7,
          contains('pipeServer.sendCommand({"type": "selectEpisode", "index": id})\n            root.patchState("currentEpisodeIndex", id)'));
    });

    test('A4 Font.W600 警告修复（QML 未定义 → 数字 600）', () {
      expect(bottom7, isNot(contains('Font.W600')));
    });

    test('B1 选集面板默认一列', () {
      expect(panel7, contains('property int columns: 1'));
    });

    test('C TV 标记面板（复刻安卓 SegmentMarkPanel）', () {
      expect(overlay7, contains('片头 / 片尾'));
      expect(overlay7, contains('当前位置 " + segmentMenu.formatMs'));
      expect(overlay7, contains('设置片头'));
      expect(overlay7, contains('设置片尾'));
      // 行内范围红字警示（点前即知）
      expect(overlay7, contains('超出范围（片头 ≤10%）'));
      expect(overlay7, contains('超出范围（片尾 ≥70%）'));
      // 已有标记二次确认：更新/清除/取消
      expect(overlay7, contains('confirmIntro'));
      expect(overlay7, contains('"更新"'));
      expect(overlay7, contains('"清除"'));
      expect(overlay7, contains('"取消"'));
    });
  });
  group('㉛ 675：本地置顶/按住跟随/字幕接通/弹幕增强/图标语义', () {
    final stateH8 = read('$dir/src/player_state.h');
    final stateCpp8 = read('$dir/src/player_state.cpp');
    final mainCpp8 = read('$dir/src/main.cpp');
    final overlay8 = read('$dir/src/qml/Overlay.qml');
    final gestures8 = read('$dir/src/qml/VideoGestures.qml');
    final pslider8 = read('$dir/src/qml/PlayerSlider.qml');
    final bottom8 = read('$dir/src/qml/BottomBar.qml');

    test('A 镜像本地置顶（过期快照不覆盖本地 patch）', () {
      expect(stateCpp8, contains('localKeys_.insert(key)'));
      expect(stateCpp8, contains('for (const QString& k : localKeys_) json.remove(k)'));
      expect(mainCpp8, contains('state.applyJson(filtered, true)'));
    });

    test('B 滑杆按住跟随鼠标（按下即跳 + 全程跟随）', () {
      expect(pslider8, contains('id: trackDrag'));
      expect(pslider8, contains('slider.isPressed = true'));
      expect(pslider8, contains('applyAt(mouse.x)'));
      expect(pslider8, contains('preventStealing: true'));
    });

    test('C 字幕轨接通（type=sub 也入列，不再丢弃）', () {
      expect(stateCpp8, contains('QLatin1String("sub")'));
    });

    test('D 选中态点别处取消', () {
      expect(gestures8, contains('property var onTap'));
      expect(overlay8, contains('onTap: () => root.selectedSlider = ""'));
      expect(overlay8, contains('onPanelOpenChanged: if (panelOpen) selectedSlider = ""'));
    });

    test('E 弹幕增强（速度/透明度生效 + 防叠行）', () {
      expect(overlay8, contains('pickSlot'));
      expect(overlay8, contains('alphaTag'));
      expect(overlay8, contains('8.0 / speed'));
      expect(overlay8, contains('items.slice().sort'));
    });

    test('F 电影隐藏上下切集（episodeCount > 1）', () {
      expect('visible: playerState.episodeCount > 1'.allMatches(bottom8).length, 2);
    });

    test('G 自动隐藏修复（就绪判定补 durationMs）', () {
      expect(overlay8, contains('playerState.playerReady || playerState.durationMs > 0'));
    });

    test('H 手势图标语义（当前可执行动作 + 先算目标态）', () {
      expect(gestures8, contains('willBePlaying ? Icons.pauseCircle'));
      // 旧的反向表达式不得回归
      expect(gestures8, isNot(contains('playerState.paused ? Icons.playCircle')));
      // 底栏播放钮动作语义与 Flutter 一致
      expect(bottom8, contains('playerState.paused ? Icons.playCircle : Icons.pauseCircle'));
    });
  });
  group('㉜ 676：进度条时序/字幕接通/面板滚动/字幕全类型/弹幕即时/父进程守卫', () {
    final stateCpp9 = read('$dir/src/player_state.cpp');
    final mpvCpp9 = read('$dir/src/mpv_window.cpp');
    final mainCpp9 = read('$dir/src/main.cpp');
    final overlay9 = read('$dir/src/qml/Overlay.qml');
    final panel9 = read('$dir/src/qml/Panel.qml');
    final pslider9 = read('$dir/src/qml/PlayerSlider.qml');
    final session9 = read('lib/services/player/qt_player_session.dart');
    final pipe9 = read('lib/services/player/qt_player_pipe.dart');
    final mainDart9 = read('lib/main.dart');

    test('A 进度条松手时序：先 finished(拖动值) 再解绑', () {
      final releaseAt = pslider9.indexOf('onReleased: (mouse) =>');
      expect(releaseAt, greaterThan(0));
      final finishedAt =
          pslider9.indexOf('root.finished(v)', releaseAt);
      final unbindAt =
          pslider9.indexOf('slider.isPressed = false', releaseAt);
      expect(finishedAt, greaterThan(releaseAt));
      expect(unbindAt, greaterThan(finishedAt));
      // 旧 Connections 松手链（读到绑定回写的旧值 → 二次 seek）已删除
      expect(pslider9, isNot(contains('onIsPressedChanged')));
      // 映射兜底：不依赖 ESlider 内部 id 链
      expect(pslider9, contains('isNaN(v)'));
      expect(pslider9, contains('preventStealing: true'));
    });

    test('B 字幕轨类型归一（subtitle → mpv 的 sub）', () {
      expect(mpvCpp9, contains('QString mpvTrackType(const QString& type)'));
      expect(mpvCpp9,
          contains('type == QLatin1String("subtitle") ? QStringLiteral("sub")'));
      expect(mpvCpp9, contains('itemType != typeName'));
      expect(mpvCpp9, contains('trackType == typeName'));
      // 两个入口都走归一（selectTrack / activeTrackIndex）
      expect('const QString typeName = mpvTrackType(type);'
          .allMatches(mpvCpp9).length, greaterThanOrEqualTo(2));
      // Dart 侧字幕类型 'sub' 也入列（675 C 保留）
      expect(stateCpp9, contains('QLatin1String("sub")'));
      // 弹幕轨（sub-add 的外部字幕）不得计入面板序号
      expect(mpvCpp9, contains('itemFile == danmakuFile_'));
      expect(mpvCpp9, contains('trackFile == danmakuFile_'));
      // 加弹幕轨不得抢占用户主字幕（sub-add 不带 select + 恢复 sid）
      expect(mpvCpp9, contains('int64_t sidBefore = -1;'));
      expect(mpvCpp9, contains('mpv_set_property_string(mpv_, "sid",'));
      expect(mpvCpp9, isNot(contains('QStringLiteral("select")')));
      // 作用域守卫：restoreSid 是 setDanmakuAss 的局部 lambda——
      // 676 首版被误插到 selectTrack（后者无此标识符），CI 编译
      // C3861 挂掉。这里钉死：定义与全部调用都必须落在 setDanmakuAss
      // 函数体内，selectTrack 段内不得出现。
      final danmakuStart = mpvCpp9.indexOf('void MpvWindow::setDanmakuAss');
      final danmakuEnd = mpvCpp9.indexOf('void MpvWindow::setVolume');
      expect(danmakuStart, greaterThan(0));
      expect(danmakuEnd, greaterThan(danmakuStart));
      final danmakuBody = mpvCpp9.substring(danmakuStart, danmakuEnd);
      expect(danmakuBody, contains('const auto restoreSid'));
      expect(danmakuBody, contains('restoreSid();'));
      final selectStart = mpvCpp9.indexOf('void MpvWindow::selectTrack');
      expect(selectStart, greaterThan(0));
      expect(mpvCpp9.substring(selectStart, danmakuStart),
          isNot(contains('restoreSid')));
    });

    test('C 字幕/音轨面板可滚动 + 固定长度滚动条（够长才显示）', () {
      expect(panel9, contains('listAvailableHeight'));
      expect(panel9, contains('Math.min(root.rowsHeight'));
      expect(panel9, contains('id: listScroll'));
      expect(panel9, contains('list.contentHeight > list.height + 4'));
      expect(panel9, contains('id: listHandle'));
      expect(panel9, contains('height: 96'));
      expect(panel9, contains('list.contentY = (listHandle.y / span)'));
      expect(panel9, contains('boundsBehavior: Flickable.StopAtBounds'));
    });

    test('D 字幕大小/位置/延迟全类型生效（安卓映射 + ASS 覆盖）', () {
      // 位置公式对齐安卓：/4 + clamp(0,100)（22 → 95）
      expect(session9, contains('value.clamp(0, 200) / 4'));
      expect(session9, contains("adapter.setProperty('sub-pos', '95')"));
      // ASS 样式字幕吃 sub-scale
      expect(mpvCpp9,
          contains('mpv_set_option_string(mpv_, "sub-ass-override", "scale")'));
      // 次字幕轨（弹幕 ASS）不得被 strip（默认值会吃掉颜色/位置/透明度）
      expect(mpvCpp9,
          contains('"secondary-sub-ass-override", "no"'));
      // 三通道写入可诊断
      expect(mpvCpp9, contains('name.startsWith(QLatin1String("sub-"))'));
    });

    test('E 弹幕大小/速度/透明度变化即重建 ASS', () {
      expect(overlay9, contains('property string danmakuStyleSig'));
      expect(overlay9, contains('if (sig === root.danmakuStyleSig) return'));
      expect(overlay9, contains('root.danmakuStyleSig = sig'));
      // 三值都进签名
      expect(overlay9, contains('playerState.danmakuFontSize'));
      expect(overlay9, contains('playerState.danmakuSpeed'));
      expect(overlay9, contains('playerState.danmakuOpacity'));
    });

    test('F 关主窗口 → Qt 跟随退出（双保险）', () {
      // Qt 侧：父进程句柄守卫
      expect(mainCpp9, contains('QWinEventNotifier'));
      expect(mainCpp9, contains('::OpenProcess('));
      expect(mainCpp9, contains('SYNCHRONIZE'));
      expect(mainCpp9, contains('QCoreApplication::quit()'));
      expect(mainCpp9, contains('"parent-pid"'));
      expect(mainCpp9, contains('parser.value("parent-pid")'));
      // Dart 侧：启动带父 pid + 关窗主动收
      expect(pipe9, contains("'--parent-pid'"));
      expect(pipe9, contains(r"'$pid'"));
      expect(mainDart9, contains('_QtPlayerWindowCloseListener'));
      expect(mainDart9, contains('void onWindowClose()'));
      expect(mainDart9, contains('MpvSessionPlatform.closeQtPlayer()'));
    });
  });
}

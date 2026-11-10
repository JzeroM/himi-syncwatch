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
      // 659：图标改为走 Icons 单例（与 Flutter NativePlayerIcons 同码点），
      // 不再在 QML 里写死 \uXXXX。
      for (final icon in [
        'Icons.arrowBack',
        'Icons.memory',
        'Icons.highQuality',
        'Icons.aspectRatio',
        'Icons.speed',
        'Icons.fullscreen',
      ]) {
        expect(topBar, contains(icon), reason: '顶栏缺 $icon');
      }
      expect(topBar, contains('playerState.title'));
      expect(topBar, contains('playerState.networkSpeedText'));
    });

    test('底栏含进度条/时间/播放暂停/音量/字幕/音轨/选集/倍速/全屏', () {
      // 660：进度条改为 GlassSlider（照 Flutter 观感），不再是 SeekBar
      expect(bottomBar, contains('GlassSlider'));
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
        'SeekBar',
        'ControlButton',
        'Panel',
      ]) {
        expect(cmake, contains(name), reason: '别名循环里缺 $name');
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

  group('⑬ UI 与 Flutter 一致（逐项对齐 NativePlayerTheme）', () {
    final themeDart = File(
      'lib/services/player/native/native_player_theme.dart',
    ).readAsStringSync();
    final iconsDart = File(
      'lib/services/player/native/native_player_icons.dart',
    ).readAsStringSync();
    final themeQml = File('$dir/src/qml/Theme.qml').readAsStringSync();
    final iconsQml = File('$dir/src/qml/Icons.qml').readAsStringSync();

    /// 从 Dart 源码取 `static const double xxx = N;`
    String? dartDouble(String name) {
      final m = RegExp('static const double $name = ([0-9.]+);')
          .firstMatch(themeDart);
      return m?.group(1);
    }

    /// 从 QML 源码取 `readonly property real xxx: N`
    String? qmlReal(String name) {
      final m = RegExp('readonly property real $name: ([0-9.]+)')
          .firstMatch(themeQml);
      return m?.group(1);
    }

    test('关键尺寸逐值一致（顶栏/底栏/图标/进度条）', () {
      const pairs = <String, String>{
        'topBarHeight': 'topBarHeight',
        'topIconSize': 'topIconSize',
        'titleSize': 'titleSize',
        'captionSize': 'captionSize',
        'barPadH': 'barPadH',
        'barPadTop': 'barPadTop',
        'barPadBottom': 'barPadBottom',
        'seekTrackHeight': 'seekTrackHeight',
        'seekThumbRadius': 'seekThumbRadius',
        'transportPlaySize': 'transportPlaySize',
        'transportSideSize': 'transportSideSize',
        'controlIconSize': 'controlIconSize',
        'controlGap': 'controlGap',
      };
      pairs.forEach((dartName, qmlName) {
        final dartVal = dartDouble(dartName);
        final qmlVal = qmlReal(qmlName);
        expect(dartVal, isNotNull, reason: 'Dart 里找不到 $dartName');
        expect(qmlVal, isNotNull, reason: 'QML 里找不到 $qmlName');
        expect(qmlVal, dartVal,
            reason: '$qmlName 与 Flutter 的 $dartName 不一致'
                '（QML=$qmlVal, Dart=$dartVal）');
      });
    });

    test('面板尺寸逐值一致', () {
      const pairs = <String, String>{
        'panelMinWidth': 'panelMinWidth',
        'panelMaxWidth': 'panelMaxWidth',
        'panelRight': 'panelRight',
        'panelTopOffset': 'panelTopOffset',
        'panelPadH': 'panelPadH',
        'panelPadV': 'panelPadV',
        'panelTitleSize': 'panelTitleSize',
        'panelOptionSize': 'panelOptionSize',
      };
      pairs.forEach((dartName, qmlName) {
        final dartVal = dartDouble(dartName);
        final qmlVal = qmlReal(qmlName);
        expect(dartVal, isNotNull, reason: 'Dart 里找不到 $dartName');
        expect(qmlVal, dartVal,
            reason: '$qmlName 与 Flutter 的 $dartName 不一致');
      });
    });

    test('强调色一致（#6366F1）', () {
      expect(themeDart, contains('accent = Color(0xFF6366F1)'));
      expect(themeQml, contains('accent: "#6366F1"'));
    });

    test('图标码点与 NativePlayerIcons 一致（关键项）', () {
      // 【656 的教训】首版我凭记忆写码点（如 \ue5c4 当返回），
      // 那是 Flutter 的 Icons.arrow_back，与项目统一使用的
      // NativePlayerIcons.arrowBack = 0xE092 不是同一个字形。
      const pairs = <String, String>{
        'arrowBack': 'E092',
        'memory': 'E3DB',
        'highQuality': 'E30F',
        'aspectRatio': 'E0A3',
        'speed': 'E5E0',
        'fullscreen': 'E2CB',
        'playCircle': 'E4CD',
        'pauseCircle': 'E47E',
        'skipNext': 'E5BD',
        'subtitles': 'E619',
        'audioTrack': 'E0B6',
        'playlistPlay': 'E4D4',
        'danmakuOn': 'E17E',
        'volumeUp': 'E6C5',
        'volumeOff': 'E6C4',
        'check': 'E156',
        'close': 'E16A',
      };
      pairs.forEach((name, hex) {
        expect(iconsDart, contains(RegExp('$name = 0x$hex',
                caseSensitive: false)),
            reason: 'Dart 里 $name 不是 0x$hex');
        // QML 里是小写 \ue092 形式
        final lower = hex.toLowerCase();
        expect(iconsQml, contains('\\u$lower'),
            reason: 'QML 里 $name 应为 \\u$lower');
      });
    });

    test('渐变实端一致（black@0.85）', () {
      // Flutter: Colors.black.withValues(alpha: 0.85)
      // 0.85 × 255 ≈ 217 = 0xD9
      expect(themeQml, contains('barGradientSolid: "#D9000000"'));
      expect(themeQml, contains('barBottomSolid: "#D9000000"'));
      final screenSrc =
          File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(screenSrc, contains('Colors.black.withValues(alpha: 0.85)'));
    });

    test('角标分档一致（15/19/24）', () {
      expect(themeDart, contains('badgeMinSize = 15'));
      expect(themeDart, contains('badgeWideSize = 19'));
      expect(themeDart, contains('badgeXlSize = 24'));
      expect(themeQml, contains('badgeMinSize: 15'));
      expect(themeQml, contains('badgeWideSize: 19'));
      expect(themeQml, contains('badgeXlSize: 24'));
    });

    test('自动隐藏时长一致（5000ms）', () {
      expect(themeDart, contains('autoHideMs = 5000'));
      expect(themeQml, contains('autoHideMs: 5000'));
    });

    test('QML 不再硬编码颜色/尺寸（必须走 Theme）', () {
      for (final name in [
        'TopBar.qml',
        'BottomBar.qml',
        'SeekBar.qml',
        'ControlButton.qml',
        'Panel.qml',
      ]) {
        // 只看非注释行（注释里可以写「对应 Flutter 的 #6366F1」这类说明）
        final src = File('$dir/src/qml/$name')
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        // 允许 #000000（窗口底色）与 Qt.rgba(1,1,1,x)（hover 微调）
        final hardcoded = RegExp(r'#[0-9A-Fa-f]{6,8}').allMatches(src)
            .map((m) => m.group(0)!)
            .where((c) => c.toUpperCase() != '#000000')
            .toList();
        expect(hardcoded, isEmpty,
            reason: '$name 里还有硬编码颜色 $hardcoded，应改用 Theme.xxx');
      }
    });
  });

  group('⑭ 660：照 Flutter 截图对齐的细节', () {
    final bottomBar = read('$dir/src/qml/BottomBar.qml');
    final themeQml = read('$dir/src/qml/Theme.qml');
    final mainQmlSrc = read('$dir/src/qml/Main.qml');
    final stateH = read('$dir/src/player_state.h');
    final stateCpp = read('$dir/src/player_state.cpp');

    test('底栏是两行（进度条 + 控制条）', () {
      expect(bottomBar, contains('GlassSlider'));
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

    test('GlassSlider 多层绘制齐全', () {
      final slider = read('$dir/src/qml/GlassSlider.qml');
      expect(slider, contains('shadowBlur'));
      expect(slider, contains('createLinearGradient'));
      expect(slider, contains('arcTo'));
    });

    test('Main.qml 有 Logo 组件', () {
      expect(mainQmlSrc, contains('EpisodeLogo'));
    });

    test('PlayerState 有 brightness 与 logoUrl', () {
      expect(stateH, contains('Q_PROPERTY(double brightness'));
      expect(stateH, contains('Q_PROPERTY(QString logoUrl'));
      expect(stateCpp, contains('"brightness"'));
    });

    test('5 位码点用 fromCharCode', () {
      final iconsQml = read('$dir/src/qml/Icons.qml');
      expect(iconsQml, contains('String.fromCharCode(0xF07BF)'));
      expect(iconsQml, contains('String.fromCharCode(0xF04D2)'));
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
}

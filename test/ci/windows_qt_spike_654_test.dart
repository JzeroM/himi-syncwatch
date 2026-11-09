import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 654：Windows 播放器窗口 spike（Qt Quick + libmpv 直出）。
///
/// 【本轮唯一目的】验证一个致命假设：
///   mpv 用 `wid` 直出到 Qt 创建的 HWND 时，HDR 是否还在？
///
/// 若成立 → 继续 655~660 用 QML 做播放器 UI。
/// 若失败 → 改走路线 B（mpv 渲染进 QML 单窗，丢 HDR 换单窗）。
///
/// 本测试用**源码断言**锁定关键实现细节。这些细节每条都有明确的
/// 失败模式，不是形式化检查：
///
/// | 断言 | 一旦写错的后果 |
/// |---|---|
/// | `wid` 在 `mpv_initialize` 之前设置 | mpv 自己开一个黑窗，视频不在 Qt 窗口里 |
/// | HDR 判据读 `video-out-params` | 用 `video-params` 会把 tone map 误判成直出 |
/// | `target-colorspace-hint=yes` | 只设 rgb10_a2 不会切 DXGI 色彩空间 → 仍是 SDR |
/// | 不再强制 AGORA_RTM_SDK | spike 无法独立构建（旧版缺变量直接 FATAL_ERROR） |
void main() {
  const dir = 'native/windows_qt_client';
  String read(String p) => File(p).readAsStringSync();

  late String cmake;
  late String mainCpp;
  late String mpvH;
  late String mpvCpp;
  late String qml;
  late String workflow;

  setUpAll(() {
    cmake = read('$dir/CMakeLists.txt');
    mainCpp = read('$dir/src/main.cpp');
    mpvH = read('$dir/src/mpv_window.h');
    mpvCpp = read('$dir/src/mpv_window.cpp');
    qml = read('$dir/src/qml/Main.qml');
    workflow = read('.github/workflows/windows-qt-client.yml');
  });

  group('① 构建配置：不再依赖 RTM，改为依赖 libmpv', () {
    test('CMakeLists 不再要求 RTM SDK', () {
      // 注释里可以提到「不接 RTM」，但不能有真正的链接依赖。
      expect(cmake, isNot(contains('agora_rtm_sdk.dll.lib')));
      expect(cmake, isNot(contains(r'${AGORA_RTM_SDK}')));
      expect(cmake, isNot(contains('high_level_api')));
    });

    test('CMakeLists 要求 LIBMPV_DIR 且校验 client.h', () {
      expect(cmake, contains('LIBMPV_DIR'));
      expect(cmake, contains('include/mpv/client.h'));
    });

    test('CMakeLists 兼容 libmpv.dll.a 与 libmpv.lib 两种导入库', () {
      expect(cmake, contains('libmpv.dll.a'));
      expect(cmake, contains('libmpv.lib'));
    });

    test('CMakeLists 编译 mpv_window.cpp 且不再编译 rtm_engine.cpp', () {
      expect(cmake, contains('src/mpv_window.cpp'));
      expect(cmake, isNot(contains('src/rtm_engine.cpp')));
    });

    test('CMakeLists 把 libmpv-2.dll 拷到输出目录', () {
      expect(cmake, contains('libmpv-2.dll'));
      expect(cmake, contains('copy_if_different'));
    });
  });

  group('② wid 必须在 mpv_initialize 之前设置', () {
    test('mpv_set_option_string(wid) 出现在 mpv_initialize 之前', () {
      final widIdx = mpvCpp.indexOf('mpv_set_option_string(mpv_, "wid"');
      final initIdx = mpvCpp.indexOf('mpv_initialize(mpv_)');
      expect(widIdx, greaterThan(-1), reason: '必须设置 wid');
      expect(initIdx, greaterThan(-1), reason: '必须调用 mpv_initialize');
      expect(widIdx, lessThan(initIdx),
          reason: 'wid 在 init 之后设置无效，mpv 会自己开窗口');
    });

    test('wid 取的是视频窗口句柄（video_hwnd_）', () {
      final start = mpvCpp.indexOf('mpv_set_option_string(mpv_, "wid"');
      final block = mpvCpp.substring(start - 400, start + 200);
      expect(block, contains('video_hwnd_'));
      expect(block, contains('reinterpret_cast'));
    });

    test('子窗口是 WS_CHILD（挂在 Qt 主窗下，而非独立顶层窗）', () {
      expect(mpvCpp, contains('WS_CHILD'));
      expect(mpvCpp, contains('CreateWindowEx'));
    });

    test('两种挂载模式：Child 与 TopLevel', () {
      // Child = 最终架构形态；TopLevel = 排障用（排除 Qt 遮挡因素）。
      expect(mpvH, contains('enum class VideoMode'));
      expect(mpvH, contains('Child'));
      expect(mpvH, contains('TopLevel'));
      expect(mpvCpp, contains('VideoMode::Child'));
      expect(mpvCpp, contains('VideoMode::TopLevel'));
    });

    test('顶层模式用 WS_POPUP + WS_EX_TOOLWINDOW（不占任务栏）', () {
      final start = mpvCpp.indexOf('VideoMode::TopLevel');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(
        start,
        (start + 900).clamp(0, mpvCpp.length),
      );
      expect(body, contains('WS_POPUP'));
      expect(body, contains('WS_EX_TOOLWINDOW'));
    });
  });

  group('②-补 排障模式必须有意义（否则黑屏时无法归因）', () {
    test('main.cpp 支持 --video-top-level', () {
      // QCommandLineParser 的选项名不带前导 `--`，用户输入时才有。
      expect(mainCpp, contains('"video-top-level"'));
      expect(mainCpp, contains('VideoMode::TopLevel'));
      expect(mainCpp, contains('isSet("video-top-level")'));
    });

    test('验证步骤里给出「子窗黑屏 → 用顶层重跑」的判读表', () {
      final start = mpvCpp.indexOf('void MpvWindow::printVerifySteps() const');
      final body = mpvCpp.substring(
        start,
        (start + 3000).clamp(0, mpvCpp.length),
      );
      expect(body, contains('video-top-level'));
      expect(body, contains('Qt 遮挡'));
    });

    test('顶层模式同样让出底部 inset（排障时更需要看操作指引）', () {
      final start = mpvCpp.indexOf('void MpvWindow::syncGeometry()');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(
        start,
        (start + 1400).clamp(0, mpvCpp.length),
      );
      // 两个分支都应减去 bottomInset_
      final matches = RegExp(r'- bottomInset_').allMatches(body).length;
      expect(matches, greaterThanOrEqualTo(2),
          reason: 'Child 与 TopLevel 两种模式都要让出提示条高度');
    });
  });

  group('③ HDR 判据必须读 video-out-params（不是 video-params）', () {
    test('同时观察 video-out-params 与 video-params', () {
      expect(mpvCpp, contains('"video-out-params"'));
      expect(mpvCpp, contains('"video-params"'));
    });

    test('isHdrOutput 由 gamma + primaries 判定', () {
      expect(mpvCpp, contains('bool isHdrOutput('));
      final start = mpvCpp.indexOf('bool isHdrOutput(');
      final body = mpvCpp.substring(start, start + 500);
      expect(body, contains('pq'));
      expect(body, contains('hlg'));
      expect(body, contains('bt.2020'));
    });

    test('状态行区分 HDR10 与 SDR 两种结果', () {
      expect(mpvCpp, contains('HDR10'));
      expect(mpvCpp, contains('SDR'));
    });

    test('根因注释说明为何不能用 video-params', () {
      // 这条注释防止将来有人「简化」成只读 video-params。
      expect(mpvCpp, contains('video-out-params'));
      final idx = mpvCpp.indexOf('【为什么看 video-out-params');
      expect(idx, greaterThan(-1), reason: '必须保留判据根因注释');
    });

    test('nodeString 对空 map / 空 keys / 空 values 都做防护', () {
      final start = mpvCpp.indexOf('QString nodeString(');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(
        start,
        (start + 900).clamp(0, mpvCpp.length),
      );
      // 切片源的空窗期 mpv 会下发空 map，不判空会解引用空指针。
      expect(body, contains('MPV_FORMAT_NODE_MAP'));
      expect(body, contains('list->keys == nullptr'));
      expect(body, contains('list->values == nullptr'));
    });
  });

  group('④ HDR 选项与 Flutter 插件保持一致', () {
    test('开启时设 rgb10_a2 + target-colorspace-hint=yes', () {
      final start = mpvCpp.indexOf('void MpvWindow::applyHdrOptionsBeforeInit');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(start, start + 1600);
      expect(body, contains('rgb10_a2'));
      expect(body, contains('target-colorspace-hint'));
      expect(body, contains('bt.2020'));
      expect(body, contains('"pq"'));
    });

    test('关闭时把色彩相关选项复位为 auto/no', () {
      final start = mpvCpp.indexOf('void MpvWindow::applyHdrOptionsBeforeInit');
      final body = mpvCpp.substring(start, start + 1600);
      expect(body, contains('"auto"'));
      expect(body, contains('"no"'));
    });

    test('vo=gpu-next + d3d11 输出模式（HDR 直出的前提）', () {
      expect(mpvCpp, contains('"vo", "gpu-next"'));
      expect(mpvCpp, contains('"d3d11-output-mode", "window"'));
      expect(mpvCpp, contains('"gpu-api", "d3d11"'));
    });

    test('force-window=no（否则 mpv 会额外开窗）', () {
      expect(mpvCpp, contains('"force-window", "no"'));
    });
  });

  group('⑤ 验证辅助：让「HDR 是否直出」变成看一眼的动作', () {
    test('标题栏实时显示状态摘要', () {
      expect(mpvCpp, contains('void MpvWindow::refreshTitle()'));
      expect(mpvCpp, contains('setTitle'));
      expect(mpvH, contains('QString statusLine() const;'));
    });

    test('内置验证步骤打印（截图法 + A/B 对比）', () {
      expect(mpvCpp, contains('void MpvWindow::printVerifySteps() const'));
      final start = mpvCpp.indexOf('void MpvWindow::printVerifySteps() const');
      final body = mpvCpp.substring(
        start,
        (start + 2600).clamp(0, mpvCpp.length),
      );
      expect(body, contains('Win+Shift+S'));
      expect(body, contains('过曝'));
      expect(body, contains('10-bit'));
    });

    test('raw string 用自定义分隔符（否则 )" 会提前截断）', () {
      // 【会直接编译失败】文本里有 `"HDR10 ✓ (BT.2020/PQ)"`，其中的 `)"`
      // 会被默认终止符 R"( ... )" 误判为结束 → 字符串提前截断。
      final start = mpvCpp.indexOf('void MpvWindow::printVerifySteps() const');
      final body = mpvCpp.substring(
        start,
        (start + 3000).clamp(0, mpvCpp.length),
      );
      expect(body, contains('R"himi('),
          reason: '必须用自定义分隔符，默认 R"( 会被 )" 截断');
      expect(body, contains(')himi"'));
      // 整个文件里只应有一个终止符（多出来的说明字符串被截断了）
      expect(RegExp(r'\)himi"').allMatches(mpvCpp).length, 1);
    });

    test('H 键切 HDR（A/B 对比）', () {
      expect(mpvCpp, contains("case 'H':"));
      expect(mpvCpp, contains('setHdrEnabled(!hdrOn_)'));
    });

    test('F 键全屏、空格暂停、Esc 退出、S 打印帮助', () {
      expect(mpvCpp, contains("case 'F':"));
      expect(mpvCpp, contains('showFullScreen'));
      expect(mpvCpp, contains('VK_SPACE'));
      expect(mpvCpp, contains('VK_ESCAPE'));
      expect(mpvCpp, contains("case 'S':"));
    });

    test('查询显示器 HDR 能力（排除「系统没开 HDR」的误判）', () {
      expect(mpvCpp, contains('void MpvWindow::queryDisplayHdr()'));
      expect(mpvCpp, contains('IDXGIOutput6'));
      expect(mpvCpp, contains('DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020'));
      expect(mpvH, contains('bool displayHdr_'));
    });

    test('显示器 HDR 状态进入标题栏', () {
      final start = mpvCpp.indexOf('QString MpvWindow::statusLine() const');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(start, start + 1600);
      expect(body, contains('displayHdr_'));
      expect(body, contains('显示器 HDR'));
    });
  });

  group('⑥ 事件泵与资源生命周期', () {
    test('有 mpv_wait_event 定时泵（不泵则属性变更永不投递）', () {
      expect(mpvCpp, contains('void MpvWindow::pumpEvents()'));
      expect(mpvCpp, contains('mpv_wait_event'));
      expect(mpvCpp, contains('QTimer'));
    });

    test('请求了日志消息（否则 MPV_EVENT_LOG_MESSAGE 不会来）', () {
      expect(mpvCpp, contains('mpv_request_log_messages'));
    });

    test('析构先 quit + terminate_destroy 再销毁子窗口', () {
      final start = mpvCpp.indexOf('MpvWindow::~MpvWindow()');
      expect(start, greaterThan(-1));
      final body = mpvCpp.substring(start, start + 900);
      final quitIdx = body.indexOf('mpv_terminate_destroy');
      final destroyIdx = body.indexOf('DestroyWindow');
      expect(quitIdx, greaterThan(-1));
      expect(destroyIdx, greaterThan(-1));
      expect(quitIdx, lessThan(destroyIdx),
          reason: '先销毁 mpv 再销毁窗口，否则会往已释放的 HWND 里画');
    });

    test('窗口尺寸变化时子窗口跟随（syncGeometry）', () {
      expect(mpvCpp, contains('void MpvWindow::syncGeometry()'));
      expect(mpvCpp, contains('GetClientRect'));
      expect(mpvCpp, contains('SetWindowPos'));
    });
  });

  group('⑦ 原生子窗口会盖住 QML → 必须留出提示条高度', () {
    test('setBottomInset 存在且参与几何计算', () {
      expect(mpvH, contains('void setBottomInset(int px);'));
      final start = mpvCpp.indexOf('void MpvWindow::syncGeometry()');
      final body = mpvCpp.substring(start, start + 700);
      expect(body, contains('bottomInset_'));
    });

    test('main.cpp 在挂载后设置 inset，全屏时归零', () {
      expect(mainCpp, contains('setBottomInset'));
      expect(mainCpp, contains('FullScreen'));
      final idx = mainCpp.indexOf('visibilityChanged');
      expect(idx, greaterThan(-1), reason: '全屏切换时要同步 inset');
    });

    test('QML 全屏时隐藏提示条', () {
      expect(qml, contains('fullScreen'));
      expect(qml, contains('visibility === Window.FullScreen'));
    });
  });

  group('⑧ spike 刻意不接 Flutter / IPC / RTM', () {
    test('main.cpp 不引用 RTM', () {
      expect(mainCpp, isNot(contains('rtmEngine')));
      expect(mainCpp, isNot(contains('RtmEngine')));
      expect(mainCpp, isNot(contains('agora')));
    });

    test('rtm_engine 源文件已从仓库移除', () {
      expect(File('$dir/src/rtm_engine.h').existsSync(), isFalse);
      expect(File('$dir/src/rtm_engine.cpp').existsSync(), isFalse);
    });

    test('片源从命令行传入（不接 Flutter）', () {
      expect(mainCpp, contains('QCommandLineParser'));
      expect(mainCpp, contains('positionalArguments'));
    });

    test('支持 --no-hdr 启动参数做 A/B 对比', () {
      expect(mainCpp, contains('no-hdr'));
      expect(mainCpp, contains('isSet("no-hdr")'));
    });
  });

  group('⑨ CI 工作流可独立构建 spike', () {
    test('工作流为手动触发（不参与正式发版）', () {
      expect(workflow, contains('workflow_dispatch'));
    });

    test('安装 Qt 6 且使用 msvc2022_64 架构', () {
      expect(workflow, contains('install-qt-action'));
      expect(workflow, contains('win64_msvc2022_64'));
      expect(workflow, contains('QT_VERSION'));
    });

    test('用 Ninja 生成器（windows-latest 已升级 VS2026）', () {
      // 写死 "Visual Studio 17 2022" 会报 "could not find any instance of
      // Visual Studio"（v1.5.75 的 654 spike 实测失败）。
      expect(workflow, contains('-G Ninja'));
      final cmdLines = workflow
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(cmdLines, isNot(contains('-G "Visual Studio 17 2022"')));
    });

    test('必须用 vcvars64 初始化 MSVC（否则 Ninja 会挑到 MinGW gcc）', () {
      // 【实测失败】改用 Ninja 后 CMake 默认挑 PATH 里的 gcc（runner 预装
      // MinGW），而 Qt 是 MSVC 构建 → ABI 不兼容，链接期报
      // "undefined reference to __imp__ZNK9QJSEngine8hasErrorEv"。
      expect(workflow, contains('vcvars64.bat'));
      expect(workflow, contains('vswhere'));
      expect(workflow, contains('Microsoft.VisualStudio.Component.VC.Tools.x86.x64'));
    });

    test('Qt 路径用 QT_ROOT_DIR 环境变量', () {
      // `steps.install-qt.outputs.qt-dir` 在本版本 action 里为空，
      // 会让 CMAKE_PREFIX_PATH 变成空串 → 找不到 Qt。
      expect(workflow, contains(r'$env:QT_ROOT_DIR'));
      final cmdLines = workflow
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(cmdLines, isNot(contains('steps.install-qt.outputs.qt-dir')));
    });

    test('下载 shinchiro mpv dev 包并提供 LIBMPV_DIR', () {
      expect(workflow, contains('shinchiro'));
      expect(workflow, contains('mpv-dev-x86_64'));
      expect(workflow, contains('LIBMPV_DIR'));
      expect(workflow, contains('client.h'));
    });

    test('不再下载 Agora RTM SDK', () {
      expect(workflow, isNot(contains('AGORA_RTM_SDK_URL')));
      expect(workflow, isNot(contains('Agora_RTM_C')));
    });

    test('windeployqt 部署 QML 依赖（否则缺 Qt6Qml.dll）', () {
      expect(workflow, contains('windeployqt'));
      expect(workflow, contains('--qmldir'));
    });

    test('校验产物含 exe / libmpv / Qt6 关键 DLL', () {
      expect(workflow, contains('himi_qt_win.exe'));
      expect(workflow, contains('libmpv-2.dll'));
      expect(workflow, contains('Qt6Qml.dll'));
    });
  });
}

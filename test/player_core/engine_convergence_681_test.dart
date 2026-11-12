import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart'
    show PlayerEngine;
import 'package:himi_syncwatch/services/player/player_engine.dart';

/// 681：全平台播放引擎收敛 + 安卓/鸿蒙四项修复。
///
/// ## 引擎矩阵（用户明确要求）
///
/// | 平台 | 引擎 | 播放器内切换控件 |
/// |---|---|---|
/// | 安卓手机 | 仅 MPV | 移除 |
/// | 安卓 TV | MDK / Erika / MPV | 保留（底栏） |
/// | 鸿蒙 | 仅 MPV | 移除 |
/// | Windows | 仅 MPV | 移除 |
/// | iOS | 仅 Erika | 移除 |
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String playerScreen;
  late String engineSrc;
  late String androidHost;
  late String androidView;
  late String ohosView;
  late String configScreen;
  late String kernelPanel;

  setUpAll(() {
    playerScreen = read('lib/screens/player/player_screen.dart');
    engineSrc = read('lib/services/player/player_engine.dart');
    androidHost = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/AndroidNativePlayerHost.kt');
    androidView = read('android/app/src/main/kotlin/com/himi/syncwatch/'
        'nativeplayer/NativePlayerScreenView.kt');
    ohosView = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
        'native/HimiNativePlayerView.ets');
    configScreen = read('lib/screens/settings/engine_config_screen.dart');
    kernelPanel =
        read('lib/screens/player/widgets/player_kernel_panel.dart');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    PlayerEngineFactory.debugIsOhosOverride = null;
  });

  // ═══════════════════════════════════════════════════════════════
  // R. 引擎矩阵
  // ═══════════════════════════════════════════════════════════════

  group('R 引擎矩阵', () {
    test('R1 安卓手机仅 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.supportedEngines(),
          <PlayerEngine>[PlayerEngine.mpv]);
      expect(PlayerEngineFactory.isSingleEngine(tvMode: false), isTrue);
    });

    test('R2 安卓 TV 保留三引擎', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.supportedEngines(tvMode: true), <PlayerEngine>[
        PlayerEngine.mdk,
        PlayerEngine.erika,
        PlayerEngine.mpv,
      ]);
      expect(PlayerEngineFactory.isSingleEngine(tvMode: true), isFalse);
    });

    test('R3 鸿蒙仅 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = true;
      expect(PlayerEngineFactory.supportedEngines(),
          <PlayerEngine>[PlayerEngine.mpv]);
      expect(PlayerEngineFactory.isSingleEngine(), isTrue);
    });

    test('R4 Windows 仅 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlayerEngineFactory.supportedEngines(),
          <PlayerEngine>[PlayerEngine.mpv]);
      expect(PlayerEngineFactory.isSingleEngine(), isTrue);
    });

    test('R5 iOS 仅 Erika', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerEngineFactory.supportedEngines(),
          <PlayerEngine>[PlayerEngine.erika]);
      expect(PlayerEngineFactory.isSingleEngine(), isTrue);
    });

    test('R6 安卓手机老存档 mdk/erika 回退 MPV', () {
      PlayerEngineFactory.debugIsOhosOverride = false;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.resolveSelectedEngine('mdk'), PlayerEngine.mpv);
      expect(
          PlayerEngineFactory.resolveSelectedEngine('erika'), PlayerEngine.mpv);
      // TV 下保持
      expect(PlayerEngineFactory.resolveSelectedEngine('mdk', tvMode: true),
          PlayerEngine.mdk);
    });

    test('R7 播放器内引擎控件单引擎时隐藏', () {
      // 顶栏
      expect(playerScreen, contains('showKernelButton: !settings.tvMode'));
      expect(playerScreen, contains('isSingleEngine(tvMode: settings.tvMode)'));
      // 底栏（TV）
      expect(playerScreen, contains('isSingleEngine(tvMode: true)'));
      // 菜单守卫
      expect(playerScreen, contains('void _toggleKernelMenu()'));
      final guard = playerScreen.substring(
        playerScreen.indexOf('void _toggleKernelMenu()'),
        playerScreen.indexOf('void _toggleKernelMenu()') + 400,
      );
      expect(guard, contains('isSingleEngine'));
    });

    test('R8 设置页单引擎不渲染 TabBar', () {
      expect(configScreen, contains('_engines.length <= 1'));
      expect(configScreen, contains('? null'));
      // 传 tvMode
      expect(configScreen, contains('tvMode: ref.read(settingsProvider).tvMode'));
    });

    test('R9 内核面板跟随 tvMode', () {
      expect(kernelPanel, contains('final bool tvMode'));
      expect(kernelPanel, contains('supportedEngines(tvMode: tvMode)'));
    });

    test('R10 引擎工厂源码：Windows 分支只有 MPV', () {
      final winStart = engineSrc.indexOf('case TargetPlatform.windows:');
      final winEnd = engineSrc.indexOf('default:', winStart);
      final block = engineSrc.substring(winStart, winEnd);
      expect(block, contains('PlayerEngine.mpv'));
      expect(block, isNot(contains('PlayerEngine.mdk')));
      expect(block, isNot(contains('PlayerEngine.erika')));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // S. 安卓：缝隙 + 分享后不从头播放
  // ═══════════════════════════════════════════════════════════════

  group('S 安卓修复', () {
    test('S1 视频窗 +1px 覆盖，消除缝隙漏底光', () {
      // 横屏
      expect(androidHost,
          contains('targetW = (screenW - inset + 1).coerceAtLeast(1)'));
      // 竖屏
      expect(androidHost,
          contains('targetH = (screenH - inset + 1).coerceAtLeast(1)'));
    });

    test('S2 资源面板从视频右缘铺到屏幕右缘（不依赖 dp(320) 相等）', () {
      // 面板布局改为 MATCH_PARENT + leftMargin
      expect(androidView, contains('FrameLayout.LayoutParams.MATCH_PARENT'));
      expect(androidView, contains('leftMargin = leftMargin'));
      // 左缘 = 视频区宽 - 1（盖住视频那 1px）
      expect(androidView, contains('(availableW - 1).coerceAtLeast(0)'));
      // 不再用固定 dp(ROOM_PANEL_WIDTH) 定位
      expect(androidView,
          isNot(contains('lp(dp(NPTheme.ROOM_PANEL_WIDTH), LayoutParams.MATCH_PARENT, Gravity.END)')));
    });

    test('S3 安卓 suspend 用 alpha=0 隐藏（不销毁 surface）', () {
      final idx = androidHost.indexOf('fun suspend() {');
      expect(idx, greaterThan(0));
      final body = androidHost.substring(idx, idx + 1600);
      expect(body, isNot(contains('surf.hide()')));
      expect(body, isNot(contains('ctrl.hide()')));
      expect(body, contains('alpha = 0f'));
      expect(body, contains('FLAG_NOT_TOUCHABLE'));
    });

    test('S4 安卓 resume 恢复 alpha 并重申分栏', () {
      final idx = androidHost.indexOf('fun resume() {');
      expect(idx, greaterThan(0));
      final body = androidHost.substring(idx, idx + 1600);
      expect(body, contains('alpha = 1f'));
      expect(body, contains('clearFlags'));
      expect(body, contains('applyVideoInsetRight(lastVideoInsetPx)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // V. 鸿蒙竖屏隐藏系统栏
  // ═══════════════════════════════════════════════════════════════

  group('V 鸿蒙竖屏状态栏', () {
    late String plugin;

    setUpAll(() {
      plugin = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
          'plugin/HimiMpvOhosPlugin.ets');
    });

    test('V1 双 API 兜底隐藏系统栏', () {
      expect(plugin, contains('hideSystemBars'));
      // ① 整体开关（横屏可靠）
      expect(plugin, contains('setWindowSystemBarEnable([])'));
      // ② 逐项开关（竖屏可靠）
      expect(plugin, contains("setSpecificSystemBarEnabled('status', false)"));
      expect(plugin,
          contains("setSpecificSystemBarEnabled('navigationIndicator', false)"));
    });

    test('V2 两个 API 都失败才记 error', () {
      final idx = plugin.indexOf('private async hideSystemBars');
      expect(idx, greaterThan(0));
      final body = plugin.substring(idx, idx + 1400);
      expect(body, contains('anyOk'));
      expect(body, contains('hilog.error'));
    });

    test('V3 转屏后重新隐藏（房间模式同样生效）', () {
      // View 里方向变化时调 Host
      expect(ohosView, contains('refreshSystemBarsHidden'));
      expect(ohosView, contains('wasPortrait !== this.portrait'));
      // Host 里实现
      final host = read('plugins/himi_mpv_ohos/ohos/src/main/ets/components/'
          'native/HimiMpvNativeHost.ets');
      expect(host, contains('refreshSystemBarsHidden()'));
      expect(host, contains('registerNativeWindow'));
      // 插件在开窗/关窗时注册与清空
      expect(plugin, contains('registerNativeWindow(win)'));
      expect(plugin, contains('registerNativeWindow(null)'));
    });

    test('V4 房间与非房间共用同一原生窗口（都生效）', () {
      // 鸿蒙只有一个原生子窗口名，房间模式复用 → 隐藏逻辑天然覆盖
      expect(plugin, contains("NATIVE_UI_WINDOW_NAME = 'himi_native_player'"));
      final creates =
          RegExp(r'createSubWindow').allMatches(plugin).length;
      expect(creates, 1, reason: '只有一个原生子窗口，房间/非房间共用');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // U. 三端未播放占位文字一致
  // ═══════════════════════════════════════════════════════════════

  group('U 未播放占位（三端一致）', () {
    const text = '请从资源面板选择要播放的内容';

    test('U1 三端文案完全相同', () {
      expect(androidView, contains(text));
      expect(ohosView, contains(text));
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains(text), reason: 'Windows 此前完全没有占位');
    });

    test('U2 三端图标一致（play_circle 64）', () {
      // 安卓
      expect(androidView, contains('ICON_PLAY_CIRCLE, 64f'));
      // 鸿蒙
      expect(ohosView, contains('ICON_PLAY_CIRCLE'));
      expect(ohosView, contains('.fontSize(64)'));
      // Windows
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains('Icons.playCircle'));
      expect(overlay, contains('font.pixelSize: 64'));
    });

    test('U3 三端字号/颜色一致（14 / 白38，图标白24）', () {
      // 安卓
      expect(androidView, contains('NPTheme.WHITE_38'));
      expect(androidView, contains('COMPLEX_UNIT_SP, 14f'));
      // 鸿蒙
      expect(ohosView, contains("'#61FFFFFF'"));
      expect(ohosView, contains('.fontSize(14)'));
      // Windows
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains('Theme.white38'));
      expect(overlay, contains('font.pixelSize: 14'));
      expect(overlay, contains('Theme.white24'));
    });

    test('U4 三端间距 16 + 黑底居中', () {
      expect(androidView, contains('it.topMargin = dp(16)'));
      expect(ohosView, contains('.margin({ top: 16 })'));
      expect(ohosView, contains('.backgroundColor(Color.Black)'));
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      expect(overlay, contains('spacing: 16'));
      expect(overlay, contains('color: "#000000"'));
    });

    test('U5 Qt 占位不抢手势且层级在控件之下', () {
      final overlay = read('native/windows_qt_player/src/qml/Overlay.qml');
      final idx = overlay.indexOf('id: placeholder');
      expect(idx, greaterThan(0));
      final block = overlay.substring(idx, idx + 1200);
      expect(block, contains('z: -1'));
      expect(block, contains('visible: !playerState.playerReady'));
    });

    test('U6 Qt 房间态 playerReady 用 Qt 真实播放态（不被空闲引擎污染）', () {
      // Qt 接管时 `_player` 是空闲引擎（_prepared 恒 false）→ 直接用它
      // 会让占位永远显示，即使 mpv 正在播。
      final body = playerScreen.substring(
        playerScreen.indexOf('qt.pushNativeState(') - 900,
        playerScreen.indexOf('qt.pushNativeState('),
      );
      expect(body, contains("stateJson['playerReady']"));
      expect(body, contains('qt.isAlive'));
      expect(body, contains('qt.duration'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // T. 鸿蒙：亮度手势 + 比例缩放
  // ═══════════════════════════════════════════════════════════════

  group('T 鸿蒙修复', () {
    test('T1 亮度用 getLastWindow（不依赖窗口名）', () {
      expect(ohosView, contains('window.getLastWindow(getContext(this))'));
      // 去注释后判定（注释里提到旧写法是「说明为什么改」）
      final codeOnly = ohosView
          .split('\n')
          .where((l) {
            final t = l.trimLeft();
            return !t.startsWith('//') && !t.startsWith('*') &&
                !t.startsWith('/*');
          })
          .join('\n');
      expect(codeOnly, isNot(contains("findWindow('himi_native_player')")));
      expect(ohosView, contains('private hostWindow: window.Window | null'));
      expect(ohosView, contains('ensureHostWindow'));
    });

    test('T2 亮度失败回滚（不再静默吞掉）', () {
      final idx = ohosView.indexOf('private async applyWindowBrightness');
      expect(idx, greaterThan(0));
      final body = ohosView.substring(idx, idx + 900);
      expect(body, contains('hilog.error'));
      // 失败回滚到拖动起点，避免「指示器变了但屏幕没变」
      expect(body, contains('this.brightness01 = this.dragBaseBrightness'));
    });

    test('T3 亮度写入是异步（拖动不阻塞）', () {
      expect(ohosView, contains('this.applyWindowBrightness().catch('));
    });

    test('T4 videoFitW/H 按 videoFit 四档分支', () {
      final wIdx = ohosView.indexOf('private videoFitW(): number {');
      expect(wIdx, greaterThan(0));
      final wBody = ohosView.substring(wIdx, wIdx + 900);
      expect(wBody, contains("case 'cover':"));
      expect(wBody, contains("case 'fill':"));
      expect(wBody, contains("case 'none':"));
      expect(wBody, contains('switch (this.videoFit)'));

      final hIdx = ohosView.indexOf('private videoFitH(): number {');
      expect(hIdx, greaterThan(0));
      final hBody = ohosView.substring(hIdx, hIdx + 900);
      expect(hBody, contains("case 'cover':"));
      expect(hBody, contains("case 'fill':"));
      expect(hBody, contains("case 'none':"));
    });

    test('T5 none 档放开裁剪（原始尺寸可溢出）', () {
      expect(ohosView, contains('.clip(false)'));
    });
  });
}

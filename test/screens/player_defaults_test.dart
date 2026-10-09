import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

void main() {
  test('播放器默认音量与亮度均为 80', () {
    expect(kPlayerDefaultVolume, closeTo(0.8, 1e-9));
    expect(kPlayerDefaultBrightness, closeTo(0.8, 1e-9));
    expect((kPlayerDefaultVolume * 100).round(), equals(80));
  });

  test('Emby 播放进度上报间隔为 3 秒', () {
    expect(PlayerScreen.playbackReportInterval, const Duration(seconds: 3));
  });

  testWidgets('PlayerScreen.focusWithin：判定焦点是否在热键层子树内', (tester) async {
    final hotkey = FocusNode(debugLabel: 'hotkey');
    final inControls = FocusNode(debugLabel: 'inControls');
    final other = FocusNode(debugLabel: 'other');
    addTearDown(hotkey.dispose);
    addTearDown(inControls.dispose);
    addTearDown(other.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          // 热键层子树（模拟 PlayerHotkey 包裹控制条焦点）
          Focus(
            focusNode: hotkey,
            child: Focus(focusNode: inControls, child: const SizedBox()),
          ),
          // 其他路由/分支（模拟底部弹窗焦点，不应被抢）
          Focus(focusNode: other, child: const SizedBox()),
        ],
      ),
    ));
    await tester.pump();

    expect(PlayerScreen.focusWithin(hotkey, hotkey), isTrue,
        reason: 'root 自身视为在子树内');
    expect(PlayerScreen.focusWithin(hotkey, inControls), isTrue,
        reason: '控制条内焦点应回落热键层');
    expect(PlayerScreen.focusWithin(hotkey, other), isFalse,
        reason: '其他路由焦点不能被抢');
    expect(PlayerScreen.focusWithin(hotkey, null), isFalse, reason: '空焦点安全');
  });

  testWidgets('shouldHideControlsNow：5 秒无操作一律隐藏（TV 要求）', (tester) async {
    // 语义变更（v1.1.122）：无论焦点是否在控制条/选择器面板上，5 秒到期
    // 都隐藏全部控件。
    expect(PlayerScreen.controlsAutoHideAfter, const Duration(seconds: 5));
  });

  test('selectorPanelWidth：0.42×屏宽，钳制 260~320（滑杆行程更长）', () {
    expect(PlayerScreen.selectorPanelWidth(1200), 320.0, reason: '超宽封顶');
    expect(PlayerScreen.selectorPanelWidth(800), 320.0, reason: '336→封顶 320');
    expect(PlayerScreen.selectorPanelWidth(700), 294.0, reason: '中间值 0.42×');
    expect(PlayerScreen.selectorPanelWidth(500), 260.0, reason: '210→托底 260');
    expect(PlayerScreen.selectorPanelWidth(360), 260.0, reason: '竖屏托底');
  });

  test('selectorPanelBox：常规面板避开顶栏与控制条', () {
    final box = PlayerScreen.selectorPanelBox(
      fullBleed: false,
      safeTop: 24,
      safeBottom: 34,
    );
    expect(box.top, 72.0, reason: 'safeTop + 48');
    expect(box.bottom, 150.0, reason: '116 + safeBottom');
    expect(box.right, 12.0);
  });

  test('selectorPanelBox：选集面板上下右三边贴边（v1.1.175）', () {
    final box = PlayerScreen.selectorPanelBox(
      fullBleed: true,
      safeTop: 24,
      safeBottom: 34,
    );
    expect(box.top, 0.0);
    expect(box.bottom, 0.0);
    expect(box.right, 0.0);
  });

  test('rotateButtonIcon：语义直白的旋转图标，非 screen_lock 系', () {
    expect(PlayerScreen.rotateButtonIcon, Icons.screen_rotation_alt);
    expect(PlayerScreen.rotateButtonIcon, isNot(Icons.screen_lock_landscape));
    expect(PlayerScreen.rotateButtonIcon, isNot(Icons.screen_lock_portrait));
  });

  group('waitUntil（surface 绑定等待原语）', () {
    test('ready 已满足：立即返回 true，不轮询', () async {
      var polls = 0;
      final ok = await PlayerScreen.waitUntil(
        () {
          polls++;
          return true;
        },
        timeout: const Duration(milliseconds: 100),
      );
      expect(ok, isTrue);
      expect(polls, 1, reason: '首查即满足不应继续轮询');
    });

    test('ready 延迟满足：轮询至 true', () async {
      var calls = 0;
      final ok = await PlayerScreen.waitUntil(
        () => ++calls >= 3,
        timeout: const Duration(seconds: 2),
        pollMs: const Duration(milliseconds: 1),
      );
      expect(ok, isTrue);
      expect(calls, greaterThanOrEqualTo(3));
    });

    test('超时未满足：返回 false 不永久挂起', () async {
      final ok = await PlayerScreen.waitUntil(
        () => false,
        timeout: const Duration(milliseconds: 30),
        pollMs: const Duration(milliseconds: 5),
      );
      expect(ok, isFalse, reason: 'surface 创建失败时不能卡死起播链（超时兜底放行）');
    });
  });

  group('resolveVideoSize（SurfaceView 尺寸回退源）', () {
    test('无效尺寸（宽高<=0）返回 null', () {
      expect(PlayerScreen.resolveVideoSize(width: 0, height: 1080), isNull);
      expect(PlayerScreen.resolveVideoSize(width: 1920, height: -1), isNull);
      expect(PlayerScreen.resolveVideoSize(width: 0, height: 0), isNull);
    });

    test('正常尺寸直传；par 归一化高度，par<=0 视为 1', () {
      expect(PlayerScreen.resolveVideoSize(width: 1920, height: 1080),
          const Size(1920, 1080));
      expect(PlayerScreen.resolveVideoSize(width: 1920, height: 1080, par: 2.0),
          const Size(1920, 540));
      expect(PlayerScreen.resolveVideoSize(width: 1920, height: 1080, par: 0),
          const Size(1920, 1080),
          reason: 'par<=0 防御性按 1 处理，避免除零');
    });

    test('rotation 90/270 交换宽高，180 不交换', () {
      expect(
          PlayerScreen.resolveVideoSize(
              width: 1920, height: 1080, rotation: 90),
          const Size(1080, 1920));
      expect(
          PlayerScreen.resolveVideoSize(
              width: 1920, height: 1080, rotation: 270),
          const Size(1080, 1920));
      expect(
          PlayerScreen.resolveVideoSize(
              width: 1920, height: 1080, rotation: 180),
          const Size(1920, 1080));
    });
  });

  group('surfaceViewNeedsRemount（切集零重建判定，v1.1.82 根修）', () {
    test('同分辨率切集：false——view/surface/EGL 上下文全程复用', () {
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'surfaceView',
          oldSize: const Size(3840, 2160),
          newSize: const Size(3840, 2160),
        ),
        isFalse,
        reason: '拆建 view 会让 mdk renderer 永久丢帧、画面定格首帧',
      );
    });

    test('分辨率变化：true——走两阶段 detach→settle→attach', () {
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'surfaceView',
          oldSize: const Size(1920, 1080),
          newSize: const Size(3840, 2160),
        ),
        isTrue,
      );
    });

    test('texture/tunnel 档：false（无 platform view 拆建）', () {
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'texture',
          oldSize: const Size(1920, 1080),
          newSize: const Size(3840, 2160),
        ),
        isFalse,
      );
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'tunnel',
          oldSize: const Size(1920, 1080),
          newSize: const Size(3840, 2160),
        ),
        isFalse,
      );
    });

    test('首播（oldSize=null）/ 尺寸未探得（newSize=null）：false', () {
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'surfaceView',
          oldSize: null,
          newSize: const Size(3840, 2160),
        ),
        isFalse,
        reason: '首播 view 尚未挂载，直接 setState 挂载即可',
      );
      expect(
        PlayerScreen.surfaceViewNeedsRemount(
          output: 'surfaceView',
          oldSize: const Size(1920, 1080),
          newSize: null,
        ),
        isFalse,
        reason: '探测失败走重试链，不拆现有 view',
      );
    });
  });

  group('TV 控件可见性', () {
    test('横竖屏按钮：移动端显示，TV 隐藏，桌面端隐藏', () {
      expect(
        PlayerScreen.showRotateButton(tvMode: false, mobilePlatform: true),
        isTrue,
        reason: '移动端非 TV 需要旋转控制',
      );
      expect(
        PlayerScreen.showRotateButton(tvMode: true, mobilePlatform: true),
        isFalse,
        reason: 'TV 全程横屏无需旋转控制',
      );
      expect(
        PlayerScreen.showRotateButton(tvMode: false, mobilePlatform: false),
        isFalse,
        reason: '桌面端无旋转控制',
      );
      expect(
        PlayerScreen.showRotateButton(tvMode: true, mobilePlatform: false),
        isFalse,
      );
    });

    test('倍速键位置：手机本地单人顶栏；TV/桌面本地单人底栏；房间都不显示', () {
      // 手机本地单人：顶栏显示、底栏隐藏
      expect(
        PlayerScreen.showTopSpeedButton(
            tvMode: false, mobilePlatform: true, isRoom: false),
        isTrue,
      );
      expect(
        PlayerScreen.showBottomSpeedButton(
            tvMode: false, mobilePlatform: true, isRoom: false),
        isFalse,
      );
      // TV 本地单人：底栏显示、顶栏隐藏
      expect(
        PlayerScreen.showTopSpeedButton(
            tvMode: true, mobilePlatform: true, isRoom: false),
        isFalse,
      );
      expect(
        PlayerScreen.showBottomSpeedButton(
            tvMode: true, mobilePlatform: true, isRoom: false),
        isTrue,
      );
      // 桌面本地单人：底栏显示、顶栏隐藏
      expect(
        PlayerScreen.showTopSpeedButton(
            tvMode: false, mobilePlatform: false, isRoom: false),
        isFalse,
      );
      expect(
        PlayerScreen.showBottomSpeedButton(
            tvMode: false, mobilePlatform: false, isRoom: false),
        isTrue,
      );
      // 房间联播：房主节奏接管，顶/底栏都不显示
      expect(
        PlayerScreen.showTopSpeedButton(
            tvMode: false, mobilePlatform: true, isRoom: true),
        isFalse,
      );
      expect(
        PlayerScreen.showBottomSpeedButton(
            tvMode: false, mobilePlatform: true, isRoom: true),
        isFalse,
      );
    });

    test('解码按钮：非 TV 显示，TV 隐藏（解码模式仅走设置页）', () {
      expect(PlayerScreen.showDecodeButton(tvMode: false), isTrue);
      expect(PlayerScreen.showDecodeButton(tvMode: true), isFalse);
    });
  });

  group('showLogoInControls（控制条标题艺术字，房间模式不加 logo）', () {
    test('单人 + 有 logo → 显示', () {
      expect(
        PlayerScreen.showLogoInControls(
            logoUrl: 'https://emby.test/Items/m1/Images/Logo?tag=L1',
            isRoom: false),
        isTrue,
      );
    });

    test('房间模式 → 不显示', () {
      expect(
        PlayerScreen.showLogoInControls(
            logoUrl: 'https://emby.test/Items/m1/Images/Logo?tag=L1',
            isRoom: true),
        isFalse,
      );
    });

    test('无 logo / 空串 → 不显示', () {
      expect(PlayerScreen.showLogoInControls(logoUrl: null, isRoom: false),
          isFalse);
      expect(
          PlayerScreen.showLogoInControls(logoUrl: '', isRoom: false), isFalse);
    });
  });
}

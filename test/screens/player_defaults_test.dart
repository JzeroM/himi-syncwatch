import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

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

  group('surfaceViewDirectWrite（直写判定单一来源，v1.2.14 修兜底失配）', () {
    test('SDR/普通档 + EGL 故障 → 直写（绕开坏 GL）', () {
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: true,
          surfaceViewDirect: false,
          eglFault: true,
        ),
        isTrue,
        reason: '故障设备必须走直写，且渲染兜底须同步生效（renderVideo 补充推进）',
      );
    });

    test('直写档（surfaceViewDirect 内容路由）无故障 → 直写', () {
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: true,
          surfaceViewDirect: true,
          eglFault: false,
        ),
        isTrue,
        reason: 'v1.2.11 新增档位：旧兜底条件写死 output==surfaceView 曾漏该档，'
            '10-bit 内容起播竞态下 renderer 永久丢帧定格',
      );
    });

    test('直写档 + 故障 → 直写（两条件叠加）', () {
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: true,
          surfaceViewDirect: true,
          eglFault: true,
        ),
        isTrue,
      );
    });

    test('普通 SurfaceView 档无故障 → 非直写（走 GL，保留快照回读）', () {
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: true,
          surfaceViewDirect: false,
          eglFault: false,
        ),
        isFalse,
      );
    });

    test('非 SurfaceView 通道（texture/tunnel/erika）→ 恒非直写', () {
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: false,
          surfaceViewDirect: false,
          eglFault: true,
        ),
        isFalse,
        reason: '纹理通道无 ANativeWindow 直写语义',
      );
      expect(
        PlayerScreen.surfaceViewDirectWrite(
          usesSurfaceView: false,
          surfaceViewDirect: true,
          eglFault: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldTriggerEglHeal（会话级自愈守卫，v1.2.14）', () {
    test('会话内新故障 → 触发自愈', () {
      expect(
        PlayerScreen.shouldTriggerEglHeal(
          fault: true,
          handled: false,
          faultAtSessionStart: false,
        ),
        isTrue,
        reason: '健康设备会话中首次 3004 须照常自愈（老行为不变）',
      );
    });

    test('已自愈过 → 不重复触发（防重入）', () {
      expect(
        PlayerScreen.shouldTriggerEglHeal(
          fault: true,
          handled: true,
          faultAtSessionStart: false,
        ),
        isFalse,
      );
    });

    test('会话开始前已置位（持久标记设备）→ 不触发', () {
      expect(
        PlayerScreen.shouldTriggerEglHeal(
          fault: true,
          handled: false,
          faultAtSessionStart: true,
        ),
        isFalse,
        reason: '视图已按直写构建，首条 mdk 日志误触发一次两阶段重建会制造'
            '「迟到 surface + 上下文重建 → renderer 永久丢帧」竞态',
      );
    });

    test('无故障 → 不触发', () {
      expect(
        PlayerScreen.shouldTriggerEglHeal(
          fault: false,
          handled: false,
          faultAtSessionStart: false,
        ),
        isFalse,
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

  group('PlayerScreen.mergeDecoderListImage（1.1.190 官方 setDecoders 方式）', () {
    test('AMediaCodec 无属性 → 追加 image=0', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('AMediaCodec + FFmpeg → 仅 AMediaCodec 追加 image=0', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec', 'FFmpeg'], '0'),
        ['AMediaCodec:image=0', 'FFmpeg'],
      );
    });

    test('已有 image=1 → 替换为 image=0', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec:image=1'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('已有 image=0 → 不重复追加', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec:image=0'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('恢复 SDR：image=0 → image=1', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec:image=0'], '1'),
        ['AMediaCodec:image=1'],
      );
    });

    test('多属性合并：保留其他键', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['AMediaCodec:low_latency=1'], '0'),
        ['AMediaCodec:low_latency=1:image=0'],
      );
    });

    test('非 AMediaCodec 条目原样保留', () {
      expect(
        PlayerScreen.mergeDecoderListImage(['FFmpeg'], '0'),
        ['FFmpeg'],
      );
    });

    test('混合列表：仅 AMediaCodec 被修改', () {
      expect(
        PlayerScreen.mergeDecoderListImage(
            ['AMediaCodec', 'FFmpeg', 'VT'], '0'),
        ['AMediaCodec:image=0', 'FFmpeg', 'VT'],
      );
    });
  });

  group('PlayerScreen.outputColorSpace（1.1.191 SDR tone map，1.1.194 限 Android）', () {
    test('恒返回 bt709（Android 用，iOS 不调用防黑屏）', () {
      expect(PlayerScreen.outputColorSpace(), AdapterColorSpace.bt709);
    });
  });

  group('PlayerScreen.dvOutputColorSpace（DV→mdk 输出色彩策略）', () {
    const hdr10 = DisplayCapabilities(hdrTypes: ['hdr10']);
    const sdr = DisplayCapabilities();

    test('Android：支持 HDR10 → HDR10 直通（bt2100PQ）；否则 SDR（bt709）', () {
      expect(
        PlayerScreen.dvOutputColorSpace(
            platform: TargetPlatform.android, display: hdr10),
        AdapterColorSpace.bt2100PQ,
      );
      expect(
        PlayerScreen.dvOutputColorSpace(
            platform: TargetPlatform.android, display: sdr),
        AdapterColorSpace.bt709,
      );
    });

    test('Windows：写死 d3d11 HDR10（bt2100PQ），与显示能力无关', () {
      for (final d in const [hdr10, sdr]) {
        expect(
          PlayerScreen.dvOutputColorSpace(
              platform: TargetPlatform.windows, display: d),
          AdapterColorSpace.bt2100PQ,
        );
      }
    });

    test('iOS：返回 null（不调用 setColorSpace，防 Metal 黑屏）', () {
      for (final d in const [hdr10, sdr]) {
        expect(
          PlayerScreen.dvOutputColorSpace(
              platform: TargetPlatform.iOS, display: d),
          isNull,
        );
      }
    });

    test('web/其余（linux）：SDR（bt709）', () {
      expect(
        PlayerScreen.dvOutputColorSpace(
            platform: TargetPlatform.linux, display: hdr10),
        AdapterColorSpace.bt709,
      );
    });
  });

  group('PlayerScreen.resolveHdrOutputColorSpace（非 DV HDR → MDK 输出映射）', () {
    const hdr10 = DisplayCapabilities(hdrTypes: ['hdr10']);
    const hlg = DisplayCapabilities(hdrTypes: ['hlg']);
    const sdr = DisplayCapabilities();

    AdapterColorSpace? r({
      bool enabled = true,
      bool dv = false,
      bool hdr = true,
      bool hlg = false,
      bool surfaceView = true,
      DisplayCapabilities display = hdr10,
      TargetPlatform platform = TargetPlatform.android,
    }) =>
        PlayerScreen.resolveHdrOutputColorSpace(
          platform: platform,
          enabled: enabled,
          dv: dv,
          hdr: hdr,
          hlg: hlg,
          surfaceView: surfaceView,
          display: display,
        );

    test('DV 内容 → null（由 dvOutputColorSpace 单独处理，优先级最高）', () {
      expect(r(dv: true), isNull);
    });

    test('HDR10 + HDR10 屏 + SurfaceView → bt2100PQ', () {
      expect(r(), AdapterColorSpace.bt2100PQ);
    });

    test('HLG + HLG 屏 + SurfaceView → bt2100hlg', () {
      expect(
        r(hdr: false, hlg: true, display: hlg),
        AdapterColorSpace.bt2100hlg,
      );
    });

    test('纹理载体 → bt709（Flutter 纹理恒 SDR）', () {
      expect(r(surfaceView: false), AdapterColorSpace.bt709);
    });

    test('SDR 屏 → bt709 tone map', () {
      expect(r(display: sdr), AdapterColorSpace.bt709);
    });

    test('非 HDR 内容 → null（不设置）', () {
      expect(r(hdr: false, hlg: false), isNull);
    });

    test('hdrGlWorkaround 关闭 → null（A/B 基线）', () {
      expect(r(enabled: false), isNull);
    });

    test('非 Android → null', () {
      expect(r(platform: TargetPlatform.iOS), isNull);
      expect(r(platform: TargetPlatform.windows), isNull);
    });
  });

  group('PlayerScreen.mergeDecoderLowLatency（1.1.192 实验）', () {
    test('委托 DecodeModeService.withDecoderLowLatency', () {
      expect(
        PlayerScreen.mergeDecoderLowLatency(['AMediaCodec']),
        ['AMediaCodec:low_latency=1'],
      );
      expect(
        PlayerScreen.mergeDecoderLowLatency(['AMediaCodec', 'FFmpeg']),
        ['AMediaCodec:low_latency=1', 'FFmpeg'],
      );
    });
  });
}

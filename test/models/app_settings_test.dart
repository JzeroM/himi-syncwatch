import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('effectiveAudioRenderer（音频后端生效值）', () {
    test('Windows 固定为自动，忽略存档的 Android 后端', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('aaudio'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('opensl'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('auto'), 'auto');
    });

    test('iOS 固定为自动——AudioTrack 是 Android 专属后端，设了会无声', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('aaudio'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('auto'), 'auto');
    });

    test('macOS/Linux 固定为自动', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'auto');

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(AppSettings.effectiveAudioRenderer('OpenSL'), 'auto');
    });

    test('Android 放行用户设置（AAudio/OpenSL/AudioTrack 专属平台）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'AudioTrack');
      expect(AppSettings.effectiveAudioRenderer('aaudio'), 'aaudio');
      expect(AppSettings.effectiveAudioRenderer('auto'), 'auto');
    });
  });

  group('AppSettings', () {
    test('默认值', () {
      const settings = AppSettings();
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.showNetworkSpeed, isTrue, reason: '网速显示默认开');
      expect(settings.stereoDownmix, isFalse);
      expect(settings.audioRenderer, equals('auto'));
      expect(settings.audioRendererUserSet, isFalse);
      expect(settings.eglFaultSeen, isFalse);
    });

    test('showNetworkSpeed：旧数据缺字段回退默认 true，可关闭并往返', () {
      expect(AppSettings.fromJson(const {}).showNetworkSpeed, isTrue);
      expect(
        const AppSettings().copyWith(showNetworkSpeed: false).showNetworkSpeed,
        isFalse,
      );
      final json = const AppSettings(showNetworkSpeed: false).toJson();
      expect(json['showNetworkSpeed'], isFalse);
      expect(AppSettings.fromJson(json).showNetworkSpeed, isFalse);
    });

    test('playbackSpeed：旧数据缺字段回退 1.0，可改档并往返', () {
      expect(AppSettings.fromJson(const {}).playbackSpeed, 1.0);
      expect(
        const AppSettings().copyWith(playbackSpeed: 1.5).playbackSpeed,
        1.5,
      );
      final json = const AppSettings(playbackSpeed: 2.5).toJson();
      expect(json['playbackSpeed'], 2.5);
      expect(AppSettings.fromJson(json).playbackSpeed, 2.5);
    });

    test('eglFaultSeen 旧数据缺字段 → 默认 false（未确认故障）', () {
      expect(AppSettings.fromJson(const {}).eglFaultSeen, isFalse);
      expect(
        AppSettings.fromJson(const {'videoOutput': 'surfaceView'}).eglFaultSeen,
        isFalse,
      );
    });

    test('eglFaultSeen toJson/fromJson 往返保留故障标记', () {
      final json = const AppSettings().copyWith(eglFaultSeen: true).toJson();
      expect(json['eglFaultSeen'], isTrue);
      expect(AppSettings.fromJson(json).eglFaultSeen, isTrue);
    });

    test('copyWith 透传 eglFaultSeen', () {
      const settings = AppSettings();
      expect(settings.copyWith(eglFaultSeen: true).eglFaultSeen, isTrue);
      // 未指定 → 保留原值，不被覆盖
      expect(
        settings
            .copyWith(eglFaultSeen: true)
            .copyWith(showSyncDebug: true)
            .eglFaultSeen,
        isTrue,
      );
      expect(settings.copyWith(showSyncDebug: true).eglFaultSeen, isFalse);
    });

    test('videoOutHdrAuto 旧数据缺字段 → 默认 false（tone map to sRGB）',
        () {
      expect(AppSettings.fromJson(const {}).videoOutHdrAuto, isFalse);
    });

    test('videoOutHdrAuto toJson/fromJson 往返（1.1.187 实验开关）', () {
      final json =
          const AppSettings().copyWith(videoOutHdrAuto: true).toJson();
      expect(json['videoOutHdrAuto'], isTrue);
      expect(AppSettings.fromJson(json).videoOutHdrAuto, isTrue);
      // 默认 false 也落盘
      expect(const AppSettings().toJson()['videoOutHdrAuto'], isFalse);
    });

    test('videoDecoderNoImage 旧数据缺字段 → 默认 false（保持 image=1）', () {
      expect(AppSettings.fromJson(const {}).videoDecoderNoImage, isFalse);
    });

    test('videoDecoderNoImage toJson/fromJson 往返（1.1.189 实验开关）', () {
      final json =
          const AppSettings().copyWith(videoDecoderNoImage: true).toJson();
      expect(json['videoDecoderNoImage'], isTrue);
      expect(AppSettings.fromJson(json).videoDecoderNoImage, isTrue);
      // 默认 false 也落盘
      expect(const AppSettings().toJson()['videoDecoderNoImage'], isFalse);
    });

    test('copyWith 透传 videoDecoderNoImage', () {
      const original = AppSettings();
      final copied = original.copyWith(videoDecoderNoImage: true);
      expect(copied.videoDecoderNoImage, isTrue);
      // 未指定时保留
      expect(copied.copyWith().videoDecoderNoImage, isTrue);
    });

    test('videoDecoderLowLatency 旧数据缺字段 → 默认 false（保持 low_latency=0）',
        () {
      expect(
          AppSettings.fromJson(const {}).videoDecoderLowLatency, isFalse);
    });

    test('videoDecoderLowLatency toJson/fromJson 往返（1.1.192 实验开关）', () {
      final json = const AppSettings()
          .copyWith(videoDecoderLowLatency: true)
          .toJson();
      expect(json['videoDecoderLowLatency'], isTrue);
      expect(AppSettings.fromJson(json).videoDecoderLowLatency, isTrue);
      // 默认 false 也落盘
      expect(
          const AppSettings().toJson()['videoDecoderLowLatency'], isFalse);
    });

    test('copyWith 透传 videoDecoderLowLatency', () {
      const original = AppSettings();
      final copied = original.copyWith(videoDecoderLowLatency: true);
      expect(copied.videoDecoderLowLatency, isTrue);
      // 未指定时保留
      expect(copied.copyWith().videoDecoderLowLatency, isTrue);
    });

    test('renderDepth8 旧数据缺字段 → 默认 false（保持 EGL_SDR_DEPTH=10）', () {
      expect(AppSettings.fromJson(const {}).renderDepth8, isFalse);
    });

    test('renderDepth8 toJson/fromJson 往返（1.1.193 实验开关）', () {
      final json = const AppSettings().copyWith(renderDepth8: true).toJson();
      expect(json['renderDepth8'], isTrue);
      expect(AppSettings.fromJson(json).renderDepth8, isTrue);
      // 默认 false 也落盘
      expect(const AppSettings().toJson()['renderDepth8'], isFalse);
    });

    test('copyWith 透传 renderDepth8', () {
      const original = AppSettings();
      final copied = original.copyWith(renderDepth8: true);
      expect(copied.renderDepth8, isTrue);
      // 未指定时保留
      expect(copied.copyWith().renderDepth8, isTrue);
    });

    // ── 1.1.196 实验开关：forceSdrOutput / renderClampHdrOnly ──

    test('forceSdrOutput 默认 true（防 bt2020_pq 表面黑屏），'
        'renderClampHdrOnly 默认 false', () {
      expect(const AppSettings().forceSdrOutput, isTrue);
      expect(const AppSettings().renderClampHdrOnly, isFalse);
      expect(AppSettings.fromJson(const {}).forceSdrOutput, isTrue);
      expect(AppSettings.fromJson(const {}).renderClampHdrOnly, isFalse);
    });

    test('forceSdrOutput toJson/fromJson 往返', () {
      final json =
          const AppSettings().copyWith(forceSdrOutput: false).toJson();
      expect(json['forceSdrOutput'], isFalse);
      expect(AppSettings.fromJson(json).forceSdrOutput, isFalse);
      expect(const AppSettings().toJson()['forceSdrOutput'], isTrue);
    });

    test('renderClampHdrOnly toJson/fromJson 往返', () {
      final json =
          const AppSettings().copyWith(renderClampHdrOnly: true).toJson();
      expect(json['renderClampHdrOnly'], isTrue);
      expect(AppSettings.fromJson(json).renderClampHdrOnly, isTrue);
      expect(const AppSettings().toJson()['renderClampHdrOnly'], isFalse);
    });

    test('copyWith 透传 forceSdrOutput / renderClampHdrOnly', () {
      final copied = const AppSettings()
          .copyWith(forceSdrOutput: false, renderClampHdrOnly: true);
      expect(copied.forceSdrOutput, isFalse);
      expect(copied.renderClampHdrOnly, isTrue);
      // 未指定时保留
      final again = copied.copyWith();
      expect(again.forceSdrOutput, isFalse);
      expect(again.renderClampHdrOnly, isTrue);
    });

    test('copyWith 保留未指定字段', () {
      const original = AppSettings(decodeMode: 'hw', stereoDownmix: true);
      final copied = original.copyWith(showSyncDebug: true);
      expect(copied.decodeMode, equals('hw'));
      expect(copied.stereoDownmix, isTrue);
      expect(copied.showSyncDebug, isTrue);
    });

    test('copyWith 修改字段', () {
      const original = AppSettings();
      final copied = original.copyWith(decodeMode: 'sw', stereoDownmix: true);
      expect(copied.decodeMode, equals('sw'));
      expect(copied.stereoDownmix, isTrue);
    });

    test('toJson 包含所有字段', () {
      const settings = AppSettings(
        decodeMode: 'hw',
        showSyncDebug: true,
        stereoDownmix: true,
        deepDiagnostics: true,
      );
      final json = settings.toJson();
      expect(json['decodeMode'], equals('hw'));
      expect(json['showSyncDebug'], isTrue);
      expect(json['stereoDownmix'], isTrue);
      expect(json['deepDiagnostics'], isTrue);
    });

    test('fromJson 解析所有字段', () {
      final json = {
        'decodeMode': 'hw',
        'showSyncDebug': true,
        'stereoDownmix': true,
        'deepDiagnostics': true,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('hw'));
      expect(settings.showSyncDebug, isTrue);
      expect(settings.stereoDownmix, isTrue);
      expect(settings.deepDiagnostics, isTrue);
    });

    test('deepDiagnostics 缺省为关闭', () {
      expect(const AppSettings().deepDiagnostics, isFalse);
      expect(AppSettings.fromJson(const {}).deepDiagnostics, isFalse);
    });

    test('copyWith 透传 deepDiagnostics', () {
      const settings = AppSettings();
      expect(settings.copyWith(deepDiagnostics: true).deepDiagnostics, isTrue);
      // 未指定时保持原值
      expect(settings.copyWith(showSyncDebug: true).deepDiagnostics, isFalse);
      expect(
        settings
            .copyWith(deepDiagnostics: true)
            .copyWith(showSyncDebug: true)
            .deepDiagnostics,
        isTrue,
      );
    });

    test('fromJson 默认值', () {
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.stereoDownmix, isFalse);
      expect(settings.audioRenderer, equals('auto'));
    });

    test('旧版落盘默认 AudioTrack 迁移为 auto（用户未手动设置过）', () {
      final settings = AppSettings.fromJson({'audioRenderer': 'AudioTrack'});
      expect(settings.audioRenderer, equals('auto'));
      expect(settings.audioRendererUserSet, isFalse);
    });

    test('用户主动选择的 AudioTrack 保留（已标记手动设置过）', () {
      final settings = AppSettings.fromJson({
        'audioRenderer': 'AudioTrack',
        'audioRendererUserSet': true,
      });
      expect(settings.audioRenderer, equals('AudioTrack'));
      expect(settings.audioRendererUserSet, isTrue);
    });

    test('用户主动选择的其他后端保留（AAudio 不受迁移影响）', () {
      final settings = AppSettings.fromJson({'audioRenderer': 'AAudio'});
      expect(settings.audioRenderer, equals('AAudio'));
    });

    test('toJson/fromJson 往返保留手动设置标记', () {
      final json = const AppSettings()
          .copyWith(audioRenderer: 'OpenSL', audioRendererUserSet: true)
          .toJson();
      final settings = AppSettings.fromJson(json);
      expect(settings.audioRenderer, equals('OpenSL'));
      expect(settings.audioRendererUserSet, isTrue);
    });

    test('fromJson 兼容旧版 bool hardwareDecoding', () {
      final json = {'hardwareDecoding': true};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
    });

    test('fromJson 兼容旧版 false hardwareDecoding', () {
      final json = {'hardwareDecoding': false};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('sw'));
    });

    test('fromJson 兼容旧版 hw+ 迁移到 auto', () {
      final json = {'decodeMode': 'hw+'};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
    });

    test('toJson/fromJson 往返保持一致', () {
      const original = AppSettings(
        decodeMode: 'hw',
        showSyncDebug: true,
        stereoDownmix: true,
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.decodeMode, equals(original.decodeMode));
      expect(restored.showSyncDebug, equals(original.showSyncDebug));
      expect(restored.stereoDownmix, equals(original.stereoDownmix));
    });

    test('hardwareDecoding getter', () {
      const autoSettings = AppSettings(decodeMode: 'auto');
      expect(autoSettings.hardwareDecoding, isTrue);

      const hwSettings = AppSettings(decodeMode: 'hw');
      expect(hwSettings.hardwareDecoding, isTrue);

      const swSettings = AppSettings(decodeMode: 'sw');
      expect(swSettings.hardwareDecoding, isFalse);
    });

    test('glassUi 缺省为开启', () {
      expect(const AppSettings().glassUi, isTrue);
      expect(AppSettings.fromJson(const {}).glassUi, isTrue);
    });

    test('copyWith 透传 glassUi', () {
      const settings = AppSettings();
      expect(settings.copyWith(glassUi: false).glassUi, isFalse);
      expect(settings.copyWith(decodeMode: 'hw').glassUi, isTrue);
    });

    test('toJson/fromJson 往返保持 glassUi', () {
      const original = AppSettings(glassUi: false);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.glassUi, isFalse);

      const enabled = AppSettings();
      expect(AppSettings.fromJson(enabled.toJson()).glassUi, isTrue);
    });

    test('tvMode 缺省为关闭', () {
      expect(const AppSettings().tvMode, isFalse);
      expect(AppSettings.fromJson(const {}).tvMode, isFalse);
    });

    test('copyWith 透传 tvMode', () {
      const settings = AppSettings();
      expect(settings.copyWith(tvMode: true).tvMode, isTrue);
      expect(settings.copyWith(decodeMode: 'hw').tvMode, isFalse);
    });

    test('toJson/fromJson 往返保持 tvMode', () {
      const original = AppSettings(tvMode: true);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.tvMode, isTrue);

      const disabled = AppSettings();
      expect(AppSettings.fromJson(disabled.toJson()).tvMode, isFalse);
    });

    test('themeColor 缺省为 null（跟随默认底色）', () {
      expect(const AppSettings().themeColor, isNull);
      expect(AppSettings.fromJson(const {}).themeColor, isNull);
    });

    test('copyWith 设置与显式清空 themeColor', () {
      const settings = AppSettings();
      final set = settings.copyWith(themeColor: 0xFF6366F1);
      expect(set.themeColor, equals(0xFF6366F1));

      // 其他字段更新不清掉 themeColor
      final kept = set.copyWith(decodeMode: 'hw');
      expect(kept.themeColor, equals(0xFF6366F1));

      // 显式清空为 null（依赖 unsetValue 哨兵区分「未传」）
      final cleared = kept.copyWith(themeColor: null);
      expect(cleared.themeColor, isNull);

      // 未传 themeColor 的 copyWith 不改变原值
      expect(set.copyWith(decodeMode: 'sw').themeColor, equals(0xFF6366F1));
    });

    test('toJson/fromJson 往返保持 themeColor', () {
      const withColor = AppSettings(themeColor: 0xFF22D3EE);
      expect(withColor.toJson()['themeColor'], equals(0xFF22D3EE));
      expect(
        AppSettings.fromJson(withColor.toJson()).themeColor,
        equals(0xFF22D3EE),
      );

      const withoutColor = AppSettings();
      expect(withoutColor.toJson().containsKey('themeColor'), isFalse);
      expect(AppSettings.fromJson(withoutColor.toJson()).themeColor, isNull);
    });
  });

  group('玻璃可调参数（v1.1.84）', () {
    test('默认全 null（渲染走 glassParamSpecs 应用默认，v1.1.85）', () {
      const s = AppSettings();
      expect(s.glassBlur, isNull);
      expect(s.glassThickness, isNull);
      expect(s.glassEdgeZone, isNull);
      expect(s.glassSaturation, isNull);
      expect(s.glassChromatic, isNull);
      expect(s.glassLightIntensity, isNull);
      expect(s.glassRefractiveIndex, isNull);
    });

    test('json roundtrip：写入读回', () {
      const s = AppSettings(
        glassBlur: 8.5,
        glassThickness: 30,
        glassEdgeZone: 22,
        glassSaturation: 2.0,
        glassChromatic: 0.05,
        glassLightIntensity: 0.8,
        glassRefractiveIndex: 1.4,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.glassBlur, 8.5);
      expect(back.glassThickness, 30);
      expect(back.glassEdgeZone, 22);
      expect(back.glassSaturation, 2.0);
      expect(back.glassChromatic, 0.05);
      expect(back.glassLightIntensity, 0.8);
      expect(back.glassRefractiveIndex, 1.4);
    });

    test('缺字段 → null；存盘 int → double 归一', () {
      expect(AppSettings.fromJson(const {}).glassBlur, isNull);
      expect(AppSettings.fromJson(const {}).glassEdgeZone, isNull);
      final fromInt = AppSettings.fromJson(const {'glassBlur': 10});
      expect(fromInt.glassBlur, 10.0);
      expect(fromInt.glassBlur, isA<double>());
      final edgeFromInt = AppSettings.fromJson(const {'glassEdgeZone': 22});
      expect(edgeFromInt.glassEdgeZone, 22.0);
      expect(edgeFromInt.glassEdgeZone, isA<double>());
    });

    test('toJson 仅输出非 null 字段（默认态不落盘）', () {
      expect(const AppSettings().toJson().containsKey('glassBlur'), isFalse);
      expect(
          const AppSettings().toJson().containsKey('glassThickness'), isFalse);
      expect(const AppSettings(glassBlur: 7).toJson()['glassBlur'], 7);
    });

    test('copyWith：未传保留，显式 null 清空（unsetValue 语义）', () {
      const s = AppSettings(glassBlur: 5, tvMode: true);
      expect(s.copyWith().glassBlur, 5, reason: '未传保留');
      expect(s.copyWith(decodeMode: 'hw').glassBlur, 5, reason: '无关字段');
      expect(s.copyWith(glassBlur: null).glassBlur, isNull,
          reason: '显式 null 恢复包默认');
    });
  });

  group('videoOutput（视频输出通道）', () {
    test('默认 texture', () {
      expect(const AppSettings().videoOutput, 'texture');
      expect(AppSettings.fromJson(const {}).videoOutput, 'texture');
    });

    test('copyWith 透传 videoOutput', () {
      const settings = AppSettings();
      expect(
        settings.copyWith(videoOutput: 'surfaceView').videoOutput,
        'surfaceView',
      );
      // 未指定时保持原值
      expect(
        settings
            .copyWith(videoOutput: 'surfaceView')
            .copyWith(decodeMode: 'hw')
            .videoOutput,
        'surfaceView',
      );
      expect(settings.copyWith(decodeMode: 'hw').videoOutput, 'texture');
    });

    test('toJson/fromJson 往返保持 videoOutput', () {
      const original = AppSettings(videoOutput: 'tunnel');
      expect(
        AppSettings.fromJson(original.toJson()).videoOutput,
        'tunnel',
      );
    });

    test('fromJson 非法值回退 texture（不落三档之外的值）', () {
      expect(
        AppSettings.fromJson({'videoOutput': 'hdmi'}).videoOutput,
        'texture',
      );
      expect(
        AppSettings.fromJson({'videoOutput': 42}).videoOutput,
        'texture',
      );
    });

    test('surfaceViewDirect 档：白名单放行 + 往返 + getter', () {
      expect(
        AppSettings.fromJson({'videoOutput': 'surfaceViewDirect'}).videoOutput,
        'surfaceViewDirect',
      );
      const original = AppSettings(videoOutput: 'surfaceViewDirect');
      expect(
        AppSettings.fromJson(original.toJson()).videoOutput,
        'surfaceViewDirect',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(original.usesSurfaceView, isTrue);
      expect(original.surfaceViewDirect, isTrue);
      // surfaceView 也算 SurfaceView 系列，但非直写
      const sv = AppSettings(videoOutput: 'surfaceView');
      expect(sv.usesSurfaceView, isTrue);
      expect(sv.surfaceViewDirect, isFalse);
      // 非 SurfaceView 系列
      expect(const AppSettings(videoOutput: 'texture').usesSurfaceView, isFalse);
      expect(const AppSettings(videoOutput: 'tunnel').usesSurfaceView, isFalse);

      expect(AppSettings.isSurfaceViewMode('surfaceView'), isTrue);
      expect(AppSettings.isSurfaceViewMode('surfaceViewDirect'), isTrue);
      expect(AppSettings.isSurfaceViewMode('tunnel'), isFalse);
      expect(AppSettings.isSurfaceViewMode('texture'), isFalse);
    });

    test('surfaceViewDirect 非 Android 归一 texture（不可用）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const s = AppSettings(videoOutput: 'surfaceViewDirect');
      expect(s.usesSurfaceView, isFalse);
      expect(s.surfaceViewDirect, isFalse);
    });

    test('routeVideoOutput：HDR 时直写档降级为同载体 GL（mdk#361）', () {
      // HDR + 直写 → 同载体 GL
      expect(AppSettings.routeVideoOutput('surfaceViewDirect', isHdr: true),
          'surfaceView');
      expect(AppSettings.routeVideoOutput('tunnel', isHdr: true), 'texture');
      // HDR + 本就 GL → 不变
      expect(AppSettings.routeVideoOutput('surfaceView', isHdr: true),
          'surfaceView');
      expect(
          AppSettings.routeVideoOutput('texture', isHdr: true), 'texture');
      // SDR → 原样（直写保留）
      expect(AppSettings.routeVideoOutput('surfaceViewDirect', isHdr: false),
          'surfaceViewDirect');
      expect(AppSettings.routeVideoOutput('tunnel', isHdr: false), 'tunnel');
    });

    test('isHdrPixelFormat：识别 10/16-bit 像素格式', () {
      expect(AppSettings.isHdrPixelFormat('p010le'), isTrue);
      expect(AppSettings.isHdrPixelFormat('p210le'), isTrue);
      expect(AppSettings.isHdrPixelFormat('yuv420p10le'), isTrue);
      expect(AppSettings.isHdrPixelFormat('P010LE'), isTrue);
      expect(AppSettings.isHdrPixelFormat('nv12'), isFalse);
      expect(AppSettings.isHdrPixelFormat(null), isFalse);
      expect(AppSettings.isHdrPixelFormat('yuv420p'), isFalse);
    });

    test('Android 放行用户档位，其余平台固定 texture', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveVideoOutput('surfaceView'), 'surfaceView');
      expect(AppSettings.effectiveVideoOutput('tunnel'), 'tunnel');

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AppSettings.effectiveVideoOutput('surfaceView'), 'texture');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AppSettings.effectiveVideoOutput('tunnel'), 'texture');
    });

    test('eglAwareVideoOutput：EGL 故障强制直写 SurfaceView，无故障按档位', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // 故障持久：任意档位归一 SurfaceView（含已是 surfaceView 的幂等）
      expect(
        AppSettings.eglAwareVideoOutput('texture', eglFault: true),
        'surfaceView',
      );
      expect(
        AppSettings.eglAwareVideoOutput('tunnel', eglFault: true),
        'surfaceView',
      );
      expect(
        AppSettings.eglAwareVideoOutput('surfaceView', eglFault: true),
        'surfaceView',
      );

      // 无故障：行为与 effectiveVideoOutput 一致
      expect(
        AppSettings.eglAwareVideoOutput('texture', eglFault: false),
        'texture',
      );
      expect(
        AppSettings.eglAwareVideoOutput('tunnel', eglFault: false),
        'tunnel',
      );

      // 非 Android：即使故障也归一 texture（无 SurfaceView 通道）
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        AppSettings.eglAwareVideoOutput('texture', eglFault: true),
        'texture',
      );
    });

    test('eglAwareVideoOutput userSet：手动改过输出则尊重，未手动仍归一', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // 故障 + 未手动 → 保守归一 SurfaceView（与旧行为一致）
      expect(
        AppSettings.eglAwareVideoOutput('texture', eglFault: true),
        'surfaceView',
      );
      expect(
        AppSettings.eglAwareVideoOutput('tunnel',
            eglFault: true, userSet: false),
        'surfaceView',
      );

      // 故障 + 已手动 → 尊重手动选择（texture 档对照实验逃生口）
      expect(
        AppSettings.eglAwareVideoOutput('texture',
            eglFault: true, userSet: true),
        'texture',
      );
      expect(
        AppSettings.eglAwareVideoOutput('tunnel',
            eglFault: true, userSet: true),
        'tunnel',
      );
      expect(
        AppSettings.eglAwareVideoOutput(
          'surfaceView',
          eglFault: true,
          userSet: true,
        ),
        'surfaceView',
      );

      // 无故障：userSet 不改变行为
      expect(
        AppSettings.eglAwareVideoOutput('texture',
            eglFault: false, userSet: true),
        'texture',
      );

      // 非 Android：手动选择也归一 texture（无 SurfaceView 通道）
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        AppSettings.eglAwareVideoOutput('texture',
            eglFault: true, userSet: true),
        'texture',
      );
    });

    test('eglFaultWriteBack：手动改过不写回，未手动才自动切档', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // 手动改过 → 一律不写回（尊重手动选择，逃生口）
      expect(
        AppSettings.eglFaultWriteBack('texture', userSet: true),
        isNull,
      );
      expect(
        AppSettings.eglFaultWriteBack('tunnel', userSet: true),
        isNull,
      );
      expect(
        AppSettings.eglFaultWriteBack('surfaceView', userSet: true),
        isNull,
      );

      // 未手动 → 非 SurfaceView 写回 surfaceView（老自愈行为）
      expect(
        AppSettings.eglFaultWriteBack('texture', userSet: false),
        'surfaceView',
      );
      expect(
        AppSettings.eglFaultWriteBack('tunnel', userSet: false),
        'surfaceView',
      );

      // 未手动 → 已在 surfaceView 幂等不写回
      expect(
        AppSettings.eglFaultWriteBack('surfaceView', userSet: false),
        isNull,
      );

      // 非 Android：无 SurfaceView 通道，一律不写回
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        AppSettings.eglFaultWriteBack('texture', userSet: false),
        isNull,
      );
    });

    test('videoOutputUserSet 往返与旧数据默认值', () {
      // toJson/fromJson 往返保留手动标记
      final json = const AppSettings()
          .copyWith(videoOutput: 'texture', videoOutputUserSet: true)
          .toJson();
      final settings = AppSettings.fromJson(json);
      expect(settings.videoOutput, 'texture');
      expect(settings.videoOutputUserSet, isTrue);

      // 旧数据无此字段 → 默认 false（未手动设置）
      expect(
        AppSettings.fromJson({'videoOutput': 'surfaceView'}).videoOutputUserSet,
        isFalse,
      );
      expect(const AppSettings().videoOutputUserSet, isFalse);
    });

    test('usesSurfaceView / textureTunnel 跟随生效值', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const surface = AppSettings(videoOutput: 'surfaceView');
      expect(surface.usesSurfaceView, isTrue);
      expect(surface.textureTunnel, isFalse);

      const tunnel = AppSettings(videoOutput: 'tunnel');
      expect(tunnel.usesSurfaceView, isFalse);
      expect(tunnel.textureTunnel, isTrue);

      const texture = AppSettings();
      expect(texture.usesSurfaceView, isFalse);
      expect(texture.textureTunnel, isFalse);
    });

    test('非 Android 平台存了 surfaceView 也不进 platform view 分支', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      const saved = AppSettings(videoOutput: 'surfaceView');
      expect(saved.usesSurfaceView, isFalse,
          reason: '非 Android 固定纹理通道，避免误走 SurfaceView 分支');
      expect(saved.textureTunnel, isFalse);
    });

    test('三档标签齐全', () {
      expect(AppSettings.videoOutputLabels.keys,
          containsAll(['texture', 'tunnel', 'surfaceView']));
      expect(AppSettings.videoOutputLabels['texture'], '纹理');
      expect(AppSettings.videoOutputLabels['surfaceView'], 'SurfaceView');
    });
  });

  group('renderCompatMode（渲染兼容模式）', () {
    test('默认关闭', () {
      expect(const AppSettings().renderCompatMode, isFalse);
      expect(AppSettings.fromJson(const {}).renderCompatMode, isFalse);
    });

    test('copyWith 透传 renderCompatMode', () {
      const settings = AppSettings();
      expect(
        settings.copyWith(renderCompatMode: true).renderCompatMode,
        isTrue,
      );
      expect(
        settings
            .copyWith(renderCompatMode: true)
            .copyWith(decodeMode: 'hw')
            .renderCompatMode,
        isTrue,
      );
      expect(settings.copyWith(decodeMode: 'hw').renderCompatMode, isFalse);
    });

    test('toJson/fromJson 往返保持 renderCompatMode', () {
      const original = AppSettings(renderCompatMode: true);
      expect(
        AppSettings.fromJson(original.toJson()).renderCompatMode,
        isTrue,
      );
    });

    test('effectiveRenderCompatMode：Android 放行、其余平台固定关闭', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveRenderCompatMode(true), isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(AppSettings.effectiveRenderCompatMode(true), isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AppSettings.effectiveRenderCompatMode(true), isFalse);
    });
  });

  group('categoryColumns（分类页每行海报数）', () {
    test('默认 null（自动跟随屏幕）', () {
      expect(const AppSettings().categoryColumns, isNull);
      expect(AppSettings.fromJson(const {}).categoryColumns, isNull);
    });

    test('copyWith：未传保留、显式 null 清回自动、数字覆盖', () {
      const withValue = AppSettings(categoryColumns: 8);

      expect(withValue.copyWith().categoryColumns, 8, reason: '未传应保留原值');
      expect(withValue.copyWith(categoryColumns: 10).categoryColumns, 10);
      expect(
        withValue.copyWith(categoryColumns: null).categoryColumns,
        isNull,
        reason: '显式 null 应回到自动（unsetValue 语义）',
      );
      expect(
        withValue.copyWith(decodeMode: 'hw').categoryColumns,
        8,
        reason: '无关字段更新不得丢值',
      );
    });

    test('toJson/fromJson 往返；null 不落键；double 归一为 int', () {
      expect(
        const AppSettings().toJson().containsKey('categoryColumns'),
        isFalse,
        reason: 'null（自动）不写盘',
      );

      final restored =
          AppSettings.fromJson(const AppSettings(categoryColumns: 6).toJson());
      expect(restored.categoryColumns, 6);

      expect(
        AppSettings.fromJson(const {'categoryColumns': 10}).categoryColumns,
        10,
      );
      expect(
        AppSettings.fromJson(const {'categoryColumns': 10.0}).categoryColumns,
        10,
        reason: '外部写成 double 也应归一',
      );
    });

    test('弹幕字段默认值（默认开 / 滚动上限 30 / 上限 500 / 大小 0.5 / 透明度 0.6）',
        () {
      const s = AppSettings();
      expect(s.danmakuDefaultOn, isTrue);
      expect(s.danmakuApiUrl, '');
      expect(s.danmakuScrollRows, 30);
      expect(s.danmakuTopRows, 4);
      expect(s.danmakuBottomRows, 4);
      expect(s.danmakuBlockTop, isFalse);
      expect(s.danmakuBlockBottom, isFalse);
      expect(s.danmakuBlockWords, '');
      expect(s.danmakuLimitCount, isFalse);
      expect(s.danmakuMaxCount, 500);
      expect(s.danmakuSpeed, 1.0);
      expect(s.danmakuFontSize, 0.5);
      expect(s.danmakuOpacity, 0.6);
    });

    test('旧数据缺弹幕字段回退默认', () {
      final s = AppSettings.fromJson(const {});
      expect(s.danmakuDefaultOn, isTrue);
      expect(s.danmakuApiUrl, '');
      expect(s.danmakuScrollRows, 30);
      expect(s.danmakuOpacity, 0.6);
    });

    test('弹幕字段 toJson/fromJson 往返', () {
      const custom = AppSettings(
        danmakuDefaultOn: false,
        danmakuApiUrl: 'http://10.0.0.2:9321/TOKEN',
        danmakuScrollRows: 6,
        danmakuTopRows: 2,
        danmakuBottomRows: 3,
        danmakuBlockTop: true,
        danmakuBlockBottom: true,
        danmakuBlockWords: '广告,刷屏',
        danmakuLimitCount: true,
        danmakuMaxCount: 800,
        danmakuSpeed: 1.5,
        danmakuFontSize: 0.8,
        danmakuOpacity: 0.6,
      );
      final back = AppSettings.fromJson(custom.toJson());
      expect(back.danmakuDefaultOn, isFalse);
      expect(back.danmakuApiUrl, 'http://10.0.0.2:9321/TOKEN');
      expect(back.danmakuScrollRows, 6);
      expect(back.danmakuTopRows, 2);
      expect(back.danmakuBottomRows, 3);
      expect(back.danmakuBlockTop, isTrue);
      expect(back.danmakuBlockBottom, isTrue);
      expect(back.danmakuBlockWords, '广告,刷屏');
      expect(back.danmakuLimitCount, isTrue);
      expect(back.danmakuMaxCount, 800);
      expect(back.danmakuSpeed, 1.5);
      expect(back.danmakuFontSize, 0.8);
      expect(back.danmakuOpacity, 0.6);
    });

    test('copyWith 透传弹幕字段；未指定保留原值', () {
      const base = AppSettings(danmakuApiUrl: 'http://a.b', danmakuSpeed: 1.2);
      final changed = base.copyWith(danmakuScrollRows: 8);
      expect(changed.danmakuScrollRows, 8);
      expect(changed.danmakuApiUrl, 'http://a.b');
      expect(changed.danmakuSpeed, 1.2);
      // update() 传空串可清空地址（'' 非 null 不回退）
      expect(base.copyWith(danmakuApiUrl: '').danmakuApiUrl, '');
    });

    test('fromJson 数值按范围钳制（行数/速度/透明度/上限）', () {
      final s = AppSettings.fromJson(const {
        'danmakuScrollRows': 99,
        'danmakuTopRows': 0,
        'danmakuBottomRows': 3.0,
        'danmakuSpeed': 99.0,
        'danmakuFontSize': 0.1,
        'danmakuOpacity': 5,
        'danmakuMaxCount': 10,
      });
      expect(s.danmakuScrollRows, AppSettings.danmakuRowsMax);
      expect(s.danmakuTopRows, AppSettings.danmakuRowsMin);
      expect(s.danmakuBottomRows, 3, reason: 'double 归一为 int');
      expect(s.danmakuSpeed, AppSettings.danmakuSpeedMax);
      expect(s.danmakuFontSize, AppSettings.danmakuFontSizeMin);
      expect(s.danmakuOpacity, AppSettings.danmakuOpacityMax);
      expect(s.danmakuMaxCount, AppSettings.danmakuMaxCountMin);
    });
  });
}

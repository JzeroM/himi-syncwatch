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
      expect(settings.stereoDownmix, isFalse);
      expect(settings.audioRenderer, equals('auto'));
      expect(settings.audioRendererUserSet, isFalse);
      expect(settings.eglFaultSeen, isFalse);
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
      expect(AppSettings.videoOutputLabels['texture'], '纹理（默认）');
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
}

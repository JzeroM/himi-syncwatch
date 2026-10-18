import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/player/mdk_player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PlayerEngineFactory.resolveErikaOutputMode（按内容路由）', () {
    test('非 HDR → SDR（全平台）', () {
      for (final p in TargetPlatform.values) {
        expect(
          PlayerEngineFactory.resolveErikaOutputMode(hdr: false, platform: p),
          ErikaOutputMode.sdr,
          reason: '$p',
        );
      }
    });

    test('HDR：Android → extendedLinear', () {
      expect(
        PlayerEngineFactory.resolveErikaOutputMode(
            hdr: true, platform: TargetPlatform.android),
        ErikaOutputMode.extendedLinear,
      );
    });

    test('HDR：iOS/macOS/其他 → auto（协商 EDR/HDR10）', () {
      for (final p in const [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(
          PlayerEngineFactory.resolveErikaOutputMode(hdr: true, platform: p),
          ErikaOutputMode.auto,
          reason: '$p',
        );
      }
    });
  });

  group('PlayerEngineFactory.supportedEngines（平台感知，TV 与手机一致）', () {
    test('Android/iOS/macOS 含 Erika；Linux 不含（首版无预编译）', () {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        final e = PlayerEngineFactory.supportedEngines();
        expect(e, contains(PlayerEngine.mdk), reason: '$p');
        expect(e, contains(PlayerEngine.erika), reason: '$p');
        expect(e, isNot(contains(PlayerEngine.mediaKit)), reason: '$p');
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final linux = PlayerEngineFactory.supportedEngines();
      expect(linux, contains(PlayerEngine.mdk));
      expect(linux, isNot(contains(PlayerEngine.erika)));
      expect(linux, isNot(contains(PlayerEngine.mediaKit)));
    });

    test('Windows：MDK + media_kit（无 Erika）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final e = PlayerEngineFactory.supportedEngines();
      expect(e, [PlayerEngine.mdk, PlayerEngine.mediaKit]);
      expect(e, isNot(contains(PlayerEngine.erika)));
    });
  });

  group('PlayerEngineFactory.isSupported', () {
    test('非 Windows 不支持 media_kit；Windows 支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.mediaKit),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.mediaKit),
        isTrue,
      );
    });

    test('Windows/Linux 不支持 Erika；Android 支持', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika),
        isFalse,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.isSupported(PlayerEngine.erika),
        isTrue,
      );
    });
  });

  group('PlayerEngineFactory.resolveEngineForContent（全自动路由）', () {
    PlayerEngine route(
      bool hdr,
      bool dv,
      bool renderable,
      TargetPlatform p,
    ) =>
        PlayerEngineFactory.resolveEngineForContent(
          hdr: hdr,
          dolbyVision: dv,
          erikaRenderable: renderable,
          platformOverride: p,
        );

    test('非 HDR：全平台恒 mdk（能力满足与否无关）', () {
      for (final p in TargetPlatform.values) {
        expect(route(false, false, true, p), PlayerEngine.mdk, reason: '$p');
        expect(route(false, false, false, p), PlayerEngine.mdk, reason: '$p');
      }
    });

    test('Dolby Vision：全平台恒 mdk（hdr 无关、能力无关、含 Windows）', () {
      for (final p in TargetPlatform.values) {
        for (final hdr in const [true, false]) {
          for (final renderable in const [true, false]) {
            expect(
              route(hdr, true, renderable, p),
              PlayerEngine.mdk,
              reason: '$p hdr=$hdr renderable=$renderable',
            );
          }
        }
      }
    });

    test('HDR（非 DV）+ Android/iOS 且 Erika 可渲染（Vulkan/GLES3 任一）→ erika',
        () {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(route(true, false, true, p), PlayerEngine.erika, reason: '$p');
      }
    });

    test('HDR（非 DV）+ Android/iOS 不可渲染（如 ES2-only 盒子）→ mdk 直写兜底',
        () {
      expect(route(true, false, false, TargetPlatform.android), PlayerEngine.mdk);
      expect(route(true, false, false, TargetPlatform.iOS), PlayerEngine.mdk);
    });

    test('HDR（非 DV）+ Windows → media_kit（能力参数不参与）', () {
      expect(
        route(true, false, false, TargetPlatform.windows),
        PlayerEngine.mediaKit,
      );
    });

    test('HDR（非 DV）+ macOS/Linux → mdk 兜底', () {
      for (final p in const [
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(route(true, false, true, p), PlayerEngine.mdk, reason: '$p');
      }
    });
  });

  group('MdkPlayerAdapter.seekFlags（TV seek 跳开头修复，v1.1.222）', () {
    test('keyFrame | inCache（对齐 fvp 默认缓存行为）', () {
      final flags = MdkPlayerAdapter.seekFlags;
      expect(flags.test(mdk.SeekFlag.keyFrame), isTrue);
      expect(flags.test(mdk.SeekFlag.inCache), isTrue);
      expect(flags.rawValue,
          mdk.SeekFlag.keyFrame | mdk.SeekFlag.inCache);
    });
  });

  group('MdkPlayerAdapter.lowLatencyProperties（起播加速，v1.1.222/v1.2.4）', () {
    test('fflags=+fastseek（去 nobuffer）/ analyzeduration=100ms / fpsprobesize=0',
        () {
      final props = MdkPlayerAdapter.lowLatencyProperties;
      expect(props['avformat.fflags'], '+fastseek',
          reason: '+nobuffer 会丢首个关键帧包导致起播卡顿，v1.2.4 移除');
      expect(props['avformat.analyzeduration'], '100000');
      expect(props['avformat.fpsprobesize'], '0');
    });

    test('段缓存属性键/值（v1.2.29 起由设置控制）', () {
      expect(MdkPlayerAdapter.demuxBufferRangesKey, 'demux.buffer.ranges');
      expect(MdkPlayerAdapter.demuxBufferRangesValue(0), '0'); // 关闭
      expect(MdkPlayerAdapter.demuxBufferRangesValue(8), '8');
    });
  });

  group('AppSettings.normalizeBufferMax（缓冲上限归一）', () {
    test('max>=min 原样返回', () {
      expect(AppSettings.normalizeBufferMax(minMs: 1000, maxMs: 4000), 4000);
      expect(AppSettings.normalizeBufferMax(minMs: 4000, maxMs: 4000), 4000);
    });

    test('max<min 抬到 min', () {
      expect(AppSettings.normalizeBufferMax(minMs: 3000, maxMs: 1000), 3000);
    });

    test('max==0（无限）不处理', () {
      expect(AppSettings.normalizeBufferMax(minMs: 3000, maxMs: 0), 0);
    });
  });
}

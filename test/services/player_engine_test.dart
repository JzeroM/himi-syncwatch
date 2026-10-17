import 'package:erika_flutter/erika_flutter.dart' show ErikaOutputMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
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
    test('非 HDR：全平台恒 mdk（能力满足与否无关）', () {
      for (final p in TargetPlatform.values) {
        expect(
          PlayerEngineFactory.resolveEngineForContent(
              hdr: false, erikaHdrCapable: true, platformOverride: p),
          PlayerEngine.mdk,
          reason: '$p',
        );
        expect(
          PlayerEngineFactory.resolveEngineForContent(
              hdr: false, erikaHdrCapable: false, platformOverride: p),
          PlayerEngine.mdk,
          reason: '$p',
        );
      }
    });

    test('HDR + Android/iOS 且能力满足（Vulkan+HDR 显示）→ erika', () {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          PlayerEngineFactory.resolveEngineForContent(
              hdr: true, erikaHdrCapable: true, platformOverride: p),
          PlayerEngine.erika,
          reason: '$p',
        );
      }
    });

    test('HDR + Android 能力不足（如无 Vulkan 盒子）→ mdk 直写兜底', () {
      expect(
        PlayerEngineFactory.resolveEngineForContent(
            hdr: true,
            erikaHdrCapable: false,
            platformOverride: TargetPlatform.android),
        PlayerEngine.mdk,
      );
      expect(
        PlayerEngineFactory.resolveEngineForContent(
            hdr: true,
            erikaHdrCapable: false,
            platformOverride: TargetPlatform.iOS),
        PlayerEngine.mdk,
      );
    });

    test('HDR + Windows → media_kit（能力参数不参与）', () {
      expect(
        PlayerEngineFactory.resolveEngineForContent(
            hdr: true,
            erikaHdrCapable: false,
            platformOverride: TargetPlatform.windows),
        PlayerEngine.mediaKit,
      );
    });

    test('HDR + macOS/Linux → mdk 兜底', () {
      for (final p in const [
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          PlayerEngineFactory.resolveEngineForContent(
              hdr: true, erikaHdrCapable: true, platformOverride: p),
          PlayerEngine.mdk,
          reason: '$p',
        );
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

    test('起播最小缓冲 300ms（消除开局欠载卡顿）', () {
      expect(MdkPlayerAdapter.lowLatencyBufferMinMs, 300);
    });
  });
}

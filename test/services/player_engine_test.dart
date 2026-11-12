import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/services/player/mdk_player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('PlayerEngineFactory.supportedEngines（平台矩阵）', () {
    test('681：Android 手机仅 MPV，TV 三引擎', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // 手机：仅 MPV
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mpv],
      );
      // TV：MDK + Erika + MPV
      expect(
        PlayerEngineFactory.supportedEngines(tvMode: true),
        <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.erika,
          PlayerEngine.mpv,
        ],
      );
      // mediaKit（libmpv 纹理路径）不再暴露
      expect(
        PlayerEngineFactory.supportedEngines(tvMode: true)
            .contains(PlayerEngine.mediaKit),
        isFalse,
      );
    });

    test('681：Windows 仅 MPV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mpv],
      );
      expect(
        PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mediaKit),
        isFalse,
      );
    });

    test('iOS：仅 Erika', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.erika],
      );
    });

    test('Linux：仅 MDK', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[PlayerEngine.mdk],
      );
    });
  });

  group('PlayerEngineFactory.defaultEngine / resolveSelectedEngine', () {
    test('Android / Windows 默认 MPV；iOS 默认 Erika', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // 646.1：Windows 也默认 MPV（原生顶层窗口 HDR 直出）。
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.erika);
    });

    test('落盘内核受平台限制，不支持时回退默认', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.erika,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('erika'),
        PlayerEngine.erika,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // 681：安卓手机只 MPV → 所有非 MPV 存档都回退 MPV
      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mpv,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk'),
        PlayerEngine.mpv,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('bogus'),
        PlayerEngine.mpv,
      );
      // TV 下 mdk 保持
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mdk', tvMode: true),
        PlayerEngine.mdk,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // 646.1：Windows 上 media_kit 已移除 → 落盘值回退平台默认（MPV）。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mpv,
      );
      // 存档 mpv 在 Windows 上直接生效（且为默认）。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mpv'),
        PlayerEngine.mpv,
      );
    });
  });

  group('PlayerEngineFactory.isSupported', () {
    test('681：各平台 isSupported 按收敛后的矩阵', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // 手机：仅 MPV
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isTrue);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mediaKit), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse);
      // TV：三引擎
      expect(
          PlayerEngineFactory.isSupported(PlayerEngine.mdk, tvMode: true),
          isTrue);
      expect(
          PlayerEngineFactory.isSupported(PlayerEngine.erika, tvMode: true),
          isTrue);
      // iOS：仅 Erika
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isTrue);
      // Windows：仅 MPV
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isTrue);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mediaKit), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isFalse);
    });
  });

  group('MdkPlayerAdapter.seekFlags（TV seek 跳开头修复，v1.1.222）', () {
    test('keyFrame | inCache（对齐 fvp 默认缓存行为）', () {
      final flags = MdkPlayerAdapter.seekFlags;
      expect(flags.test(mdk.SeekFlag.keyFrame), isTrue);
      expect(flags.test(mdk.SeekFlag.inCache), isTrue);
      expect(flags.rawValue, mdk.SeekFlag.keyFrame | mdk.SeekFlag.inCache);
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

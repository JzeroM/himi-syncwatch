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
    test('Android：MDK + Erika + MPV（libmpv 引擎选项已移除）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.erika,
          PlayerEngine.mpv,
        ],
      );
      // mediaKit（libmpv 纹理路径）不再暴露：与原生 MPV 共用同一份 libmpv，
      // 引擎选项移除不影响原生 MPV。
      expect(
        PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mediaKit),
        isFalse,
      );
    });

    test('Windows：MDK + media_kit + Erika，MPV 已移除（641）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        PlayerEngineFactory.supportedEngines(),
        <PlayerEngine>[
          PlayerEngine.mdk,
          PlayerEngine.mediaKit,
          PlayerEngine.erika,
        ],
      );
      // 641：Windows 上 MPV texture 返回崩溃（flutter_windows.dll）、
      // surface 灰屏（HWND 被遮挡），故从可选列表移除。
      expect(
        PlayerEngineFactory.supportedEngines().contains(PlayerEngine.mpv),
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
    test('Android 默认 MPV；641 起 Windows 默认 media_kit；iOS 默认 Erika', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mpv);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // 641：MPV → media_kit。
      expect(PlayerEngineFactory.defaultEngine(), PlayerEngine.mediaKit);
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
      // mediaKit 引擎选项已移除：落盘值回退平台默认（MPV）。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mpv,
      );
      expect(
        PlayerEngineFactory.resolveSelectedEngine('bogus'),
        PlayerEngine.mdk,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      // 641：Windows 上 media_kit 重新可用（且为默认），落盘值直接生效。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('media_kit'),
        PlayerEngine.mediaKit,
      );
      // 旧存档选过 mpv → Windows 已移除，回退到新默认 media_kit。
      expect(
        PlayerEngineFactory.resolveSelectedEngine('mpv'),
        PlayerEngine.mediaKit,
      );
    });
  });

  group('PlayerEngineFactory.isSupported', () {
    test('Android 支持 MPV 不支持 MediaKit；Windows 支持 MediaKit 不支持 MPV', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mediaKit), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isTrue);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlayerEngineFactory.isSupported(PlayerEngine.erika), isTrue);
      // 641：Windows 反转——media_kit 可用、MPV 移除、MDK 保留。
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mpv), isFalse);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mediaKit), isTrue);
      expect(PlayerEngineFactory.isSupported(PlayerEngine.mdk), isTrue);
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

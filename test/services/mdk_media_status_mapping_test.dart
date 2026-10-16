import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/services/player/mdk_player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// mdk.MediaStatus 位布局与 AdapterMediaStatus 不同（mdk end=0x40、
/// seeking=0x80、prepared=0x100），MdkPlayerAdapter 必须逐位翻译而非透传
/// rawValue，否则 mdk 永不上报 end（不自动下一集）、卡顿位全部错位。
void main() {
  group('MdkPlayerAdapter.mapMediaStatus 位翻译（v1.2.7 修 mdk 不自动下一集）',
      () {
    test('mdk end(0x40) → AdapterMediaStatus.end（不是 buffered）', () {
      final mapped =
          MdkPlayerAdapter.mapMediaStatus(mdk.MediaStatus(mdk.MediaStatus.end));
      expect(mapped.test(AdapterMediaStatus.end), isTrue,
          reason: 'mdk end 必须映射为 himi end，否则 mdk 永不切集');
      expect(mapped.test(AdapterMediaStatus.buffered), isFalse,
          reason: '不得把 mdk end 误读成 buffered');
    });

    test('mdk seeking(0x80) → AdapterMediaStatus.seeking（不是 end）', () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.seeking));
      expect(mapped.test(AdapterMediaStatus.seeking), isTrue);
      expect(mapped.test(AdapterMediaStatus.end), isFalse,
          reason: '不得把 mdk seeking 误读成 end（拖进度条误切集）');
    });

    test('mdk prepared(0x100) → AdapterMediaStatus.prepared', () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.prepared));
      expect(mapped.test(AdapterMediaStatus.prepared), isTrue);
      expect(mapped.test(AdapterMediaStatus.seeking), isFalse);
    });

    test('mdk stalled(0x08) → AdapterMediaStatus.stalled（不是 prepared）', () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.stalled));
      expect(mapped.test(AdapterMediaStatus.stalled), isTrue);
      expect(mapped.test(AdapterMediaStatus.prepared), isFalse);
    });

    test('mdk buffering(0x10) → AdapterMediaStatus.buffering（不是 stalled）',
        () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.buffering));
      expect(mapped.test(AdapterMediaStatus.buffering), isTrue);
      expect(mapped.test(AdapterMediaStatus.stalled), isFalse);
    });

    test('mdk buffered(0x20) → AdapterMediaStatus.buffered（不是 buffering）',
        () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.buffered));
      expect(mapped.test(AdapterMediaStatus.buffered), isTrue);
      expect(mapped.test(AdapterMediaStatus.buffering), isFalse);
    });

    test('mdk invalid(-2^31) → AdapterMediaStatus.invalid', () {
      final mapped = MdkPlayerAdapter.mapMediaStatus(
          mdk.MediaStatus(mdk.MediaStatus.invalid));
      expect(mapped.test(AdapterMediaStatus.invalid), isTrue);
    });

    test('unloaded/loading/loaded 逐位翻译', () {
      expect(
        MdkPlayerAdapter.mapMediaStatus(
                mdk.MediaStatus(mdk.MediaStatus.unloaded))
            .test(AdapterMediaStatus.unloaded),
        isTrue,
      );
      expect(
        MdkPlayerAdapter.mapMediaStatus(mdk.MediaStatus(mdk.MediaStatus.loading))
            .test(AdapterMediaStatus.loading),
        isTrue,
      );
      expect(
        MdkPlayerAdapter.mapMediaStatus(mdk.MediaStatus(mdk.MediaStatus.loaded))
            .test(AdapterMediaStatus.loaded),
        isTrue,
      );
    });

    test('组合位（loaded|prepared|buffered）逐位保留，无串位', () {
      final raw = mdk.MediaStatus.loaded |
          mdk.MediaStatus.prepared |
          mdk.MediaStatus.buffered;
      final mapped = MdkPlayerAdapter.mapMediaStatus(mdk.MediaStatus(raw));
      expect(mapped.test(AdapterMediaStatus.loaded), isTrue);
      expect(mapped.test(AdapterMediaStatus.prepared), isTrue);
      expect(mapped.test(AdapterMediaStatus.buffered), isTrue);
      expect(mapped.test(AdapterMediaStatus.end), isFalse);
      expect(mapped.test(AdapterMediaStatus.stalled), isFalse);
      expect(mapped.test(AdapterMediaStatus.buffering), isFalse);
    });

    test('处理后 AdapterMediaStatus 位布局与 mdk 数值解耦', () {
      // mdk end 数值(0x40) 恰好等于 himi buffered 数值：翻译后 himi rawValue
      // 必须使用 himi 自己的 end 位(0x80)，而不是沿用 mdk 的 0x40。
      final mapped =
          MdkPlayerAdapter.mapMediaStatus(mdk.MediaStatus(mdk.MediaStatus.end));
      expect(mapped.rawValue, AdapterMediaStatus.end.rawValue);
    });
  });
}

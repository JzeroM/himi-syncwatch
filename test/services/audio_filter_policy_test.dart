import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/audio_filter_policy.dart';

void main() {
  group('AudioFilterPolicy.resolve', () {
    test('iOS + truehd → TrueHD 无声规避滤镜（含降混）', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: 'truehd', stereoDownmix: false, isIOS: true),
        AudioFilterPolicy.truehdIosFilter,
      );
      expect(
        AudioFilterPolicy.resolve(
            codec: 'truehd', stereoDownmix: true, isIOS: true),
        AudioFilterPolicy.truehdIosFilter,
      );
    });

    test('iOS + mlp → 同样命中规避滤镜', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: 'mlp', stereoDownmix: false, isIOS: true),
        AudioFilterPolicy.truehdIosFilter,
      );
    });

    test('编码大小写与首尾空格容错', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: ' TrueHD ', stereoDownmix: false, isIOS: true),
        AudioFilterPolicy.truehdIosFilter,
      );
      expect(
        AudioFilterPolicy.resolve(
            codec: 'MLP', stereoDownmix: false, isIOS: true),
        AudioFilterPolicy.truehdIosFilter,
      );
    });

    test('iOS + 非问题编码 + 降混开 → 仅降混滤镜', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: 'ac3', stereoDownmix: true, isIOS: true),
        AudioFilterPolicy.stereoDownmixFilter,
      );
    });

    test('iOS + 非问题编码 + 降混关 → 无滤镜', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: 'ac3', stereoDownmix: false, isIOS: true),
        '',
      );
    });

    test('Android + truehd 不干预（平台仅 iOS 生效）', () {
      expect(
        AudioFilterPolicy.resolve(
            codec: 'truehd', stereoDownmix: false, isIOS: false),
        '',
      );
      expect(
        AudioFilterPolicy.resolve(
            codec: 'truehd', stereoDownmix: true, isIOS: false),
        AudioFilterPolicy.stereoDownmixFilter,
      );
    });

    test('编码未知 → 只按降混开关', () {
      expect(
        AudioFilterPolicy.resolve(codec: '', stereoDownmix: true, isIOS: true),
        AudioFilterPolicy.stereoDownmixFilter,
      );
      expect(
        AudioFilterPolicy.resolve(codec: '', stereoDownmix: false, isIOS: true),
        '',
      );
      expect(
        AudioFilterPolicy.resolve(
            codec: '', stereoDownmix: false, isIOS: false),
        '',
      );
    });
  });

  group('滤镜串字面量', () {
    // 锁定 aformat 写法：aresample 的 ochl 是 FFmpeg 7.x 才有的选项名，
    // 旧版解析失败会让整条滤镜失效（iOS TrueHD 无声规避曾因此无效）。
    test('TrueHD 规避滤镜为 aformat 兼容写法', () {
      expect(
        AudioFilterPolicy.truehdIosFilter,
        'aformat=sample_fmts=s16|flt:channel_layouts=stereo',
      );
      expect(AudioFilterPolicy.truehdIosFilter, isNot(contains('ochl')));
      expect(AudioFilterPolicy.truehdIosFilter, isNot(contains('aresample')));
    });

    test('降混滤镜为 aformat 兼容写法', () {
      expect(
        AudioFilterPolicy.stereoDownmixFilter,
        'aformat=channel_layouts=stereo',
      );
      expect(AudioFilterPolicy.stereoDownmixFilter, isNot(contains('ochl')));
    });
  });
}

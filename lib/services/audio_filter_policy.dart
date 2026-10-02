/// 音频滤镜（mdk `audio.avfilter`）选择策略。
///
/// 纯 Dart 实现，不依赖 mdk / Flutter，便于单元测试。
///
/// 背景：iOS 上 TrueHD/MLP 音轨无声（上游 mdk-sdk issue #364 至今未修复）。
/// FFmpeg 解出 `s32 7.1` PCM 后送入 Apple AudioQueue 后端无法出声；
/// Android/Windows 同片源有声，故仅 iOS 规避。做法是在音频进入渲染器
/// 之前转成立体声 + `s16|flt`：`aresample=ochl=stereo` 降混、
/// `aformat=sample_fmts=s16|flt` 转采样格式——两段选项均为上游建议
/// 或本项目既有已验证的写法。
library;

class AudioFilterPolicy {
  const AudioFilterPolicy._();

  /// iOS TrueHD/MLP 无声规避滤镜：先降混立体声，再转采样格式。
  static const String truehdIosFilter =
      'aresample=ochl=stereo,aformat=sample_fmts=s16|flt';

  /// 用户「立体声降混」开关的滤镜。
  static const String stereoDownmixFilter = 'aresample=ochl=stereo';

  /// 会触发 iOS 无声的音轨编码（FFmpeg/Emby 惯例为小写，比较前统一处理）。
  static const Set<String> iosSilentCodecs = {'truehd', 'mlp'};

  /// 计算应写入 `audio.avfilter` 的滤镜串。
  ///
  /// [codec]：当前活跃音轨编码（如 `truehd`），未知传空。
  /// [stereoDownmix]：用户「立体声降混」开关。
  /// [isIOS]：是否 iOS（仅 iOS 受无声问题影响）。
  ///
  /// 优先级：iOS 问题编码 > 用户降混开关 > 无滤镜。
  /// iOS+TrueHD 场景下滤镜已含降混，无需叠加用户开关。
  static String resolve({
    String codec = '',
    required bool stereoDownmix,
    required bool isIOS,
  }) {
    final c = codec.trim().toLowerCase();
    if (isIOS && iosSilentCodecs.contains(c)) return truehdIosFilter;
    if (stereoDownmix) return stereoDownmixFilter;
    return '';
  }
}

/// 换源音量渐变（Windows 切集爆音修复）。
///
/// 同一 mdk.Player 硬切 `_player.media` 时，新旧音频缓冲在设备侧波形不
/// 连续，XAudio2 等后端会输出可闻的爆音（click/pop）。切源前把音量在
/// [steps] 步内线性渐出到 0，起播后再从当前音量线性渐入用户目标音量，
/// 两次渐变让波形连续过渡，消除爆音。
///
/// 纯 Dart、无插件依赖：音量施加通过 [fadeTo] 的 `apply` 回调注入，
/// 便于单测；延迟可通过构造参数替换。
class AudioFader {
  AudioFader({
    this.steps = 5,
    this.stepInterval = const Duration(milliseconds: 20),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future.delayed;

  /// 渐变步数（最后一步精确落在目标值）。
  final int steps;

  /// 每步间隔；一次渐变总耗时 ≈ (steps - 1) * stepInterval。
  final Duration stepInterval;

  final Future<void> Function(Duration) _delay;

  int _generation = 0;
  bool _active = false;

  /// 渐变进行中。上层在该期间不要把 player.volume 回写进 UI 音量，
  /// 否则音量条会跟随渐变跳到 0。
  bool get active => _active;

  /// 作废进行中的渐变（切集被新请求抢占、dispose 等）。
  ///
  /// 同时复位 [active]：没有新渐变接管时（如加载失败后 cancel）不能
  /// 让 active 残留 true，否则上层音量回写会被永久阻断；若紧接着
  /// 发起新渐变，新 fadeTo 会重新置 true。
  void cancel() {
    _generation++;
    _active = false;
  }

  /// 从 [from] 线性渐变到 [to]，共 [steps] 步。
  ///
  /// 新渐变会作废旧渐变（旧协程在下一步前退出且不再清理 active，
  /// 由新渐变接管）。最后一步无论是否被作废都保证恰好施加目标值——
  /// 若中途被作废则由新渐变负责收敛，不会留下中间音量。
  Future<void> fadeTo(
    void Function(double) apply,
    double from,
    double to,
  ) async {
    final gen = ++_generation;
    _active = true;
    try {
      for (var i = 1; i <= steps; i++) {
        if (gen != _generation) return;
        apply(from + (to - from) * i / steps);
        if (i < steps) await _delay(stepInterval);
      }
    } finally {
      if (gen == _generation) _active = false;
    }
  }
}

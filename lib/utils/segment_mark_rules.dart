/// 手动片头/片尾标记的范围约束（全局统一，全平台全播放器共用）。
///
/// 背景：长按标记是「以当前位置为片头结束点 / 片尾开始点」，位置可任取，
/// 很容易把片头标到 40%、把片尾标到 50% —— 一旦保存，跳过逻辑会在剧情
/// 中段跳走，属于不可逆的误操作。因此加两条硬约束：
///
/// - 片头结束点 ≤ 总时长 [introMaxFraction]（10%）；
/// - 片尾开始点 ≥ 总时长 [outroMinFraction]（70%）。
///
/// 时长未知（`durationMs <= 0`，如直播/转码流尚未报出时长）时不做范围校验，
/// 沿用播放器原有的「不能标记到结尾」判断。
///
/// 纯函数、无 Flutter 依赖：Dart 播放页是权威校验点；安卓
/// `markSegmentFromGesture` / 鸿蒙 `markSegmentFromGesture` 按同一组字面量
/// 做前置校验与提示（测试校验三端文案与阈值一致）。
abstract final class SegmentMarkRules {
  SegmentMarkRules._();

  /// 片头结束点允许的最大位置比例（含边界）。
  static const double introMaxFraction = 0.10;

  /// 片尾开始点允许的最小位置比例（含边界）。
  static const double outroMinFraction = 0.70;

  /// 片头结束点上限（毫秒）；`durationMs <= 0` 返回 null（不校验）。
  ///
  /// 整数运算（`×10 / 100`，向下取整）——与安卓/鸿蒙逐值一致，避免浮点
  /// 舍入导致边界 1ms 的三端差异。
  static int? introMaxMs(int durationMs) =>
      durationMs > 0 ? durationMs * 10 ~/ 100 : null;

  /// 片尾开始点下限（毫秒，向上取整）；`durationMs <= 0` 返回 null。
  static int? outroMinMs(int durationMs) =>
      durationMs > 0 ? (durationMs * 70 + 99) ~/ 100 : null;

  /// 校验位置是否可用于该类型标记：返回拒绝文案，null = 通过。
  ///
  /// 只做**范围**校验（10% / 70%）；「位置为 0」「3 秒门槛」「已到结尾」
  /// 等既有校验仍由播放页/原生各自先做。
  static String? rejectReason({
    required bool isIntro,
    required int positionMs,
    required int durationMs,
  }) {
    if (durationMs <= 0) return null;
    if (isIntro) {
      final max = introMaxMs(durationMs)!;
      if (positionMs > max) {
        return introRejectMessage;
      }
      return null;
    }
    final min = outroMinMs(durationMs)!;
    if (positionMs < min) {
      return outroRejectMessage;
    }
    return null;
  }

  /// 拒绝文案（与安卓/鸿蒙原生提示逐字一致）。
  static const String introRejectMessage = '片头结束点不能超过总时长的 10%';
  static const String outroRejectMessage = '片尾开始点不能低于总时长的 70%';
}

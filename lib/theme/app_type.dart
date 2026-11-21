/// 全局文字规格（698 N10-B）：字号档 + 字重档 + 行距规范，全 App 一处取值。
///
/// - 碎值已归一（9.5→10、10.5→11、11.5→12、12.5→13…四舍五入取整）——
///   Windows Qt 原生面板的 `font.pixelSize` 只收整数（QML 教训），取整后
///   Flutter 与 QML/ArkTS 面板字号天然对齐；
/// - 新代码一律从这里取值；旧代码大档值（11/12/13/14/15/18）保持不动
///   （观感零变化），逐步收敛；
/// - 数字密集处（评分/年份/分辨率徽章）开 tnum 等宽数字（见
///   [RatingsBadgeRow]/`_MetaRow`），列表滚动数字不跳。
abstract final class AppType {
  /// 微缩标注（角标/极小提示）。
  static const double micro = 10;

  /// 辅助说明（helper/时间戳）。
  static const double caption = 11;

  /// 次级正文（徽章行/次级标签）。
  static const double small = 12;

  /// 正文（简介/元数据/卡片副标题）。
  static const double body = 13;

  /// 强调正文（卡片标题/按钮）。
  static const double emphasis = 15;

  /// 标题（分区标题）。
  static const double title = 18;

  /// 大标题（hero 片名/大数字）。
  static const double display = 24;

  /// 多行正文行距（简介/描述类）：统一 1.5。
  static const double bodyLineHeight = 1.5;
}

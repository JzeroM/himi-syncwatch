import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 海报色调取色调度器（698 N8-A）：按 URL 单飞取三色组，换图自动重取，
/// 旧图结果晚到不覆写新图（seq 竞态令牌）；取色失败/未完成为 null（调用
/// 方走主题色兜底）。
///
/// 用法：调用方在 build 早段调 [ensure]（幂等，同 URL 不重发），随后读
/// [trio] 派生渐变；异步完成经 [onChanged] 通知 setState 重建。
class PosterToneResolver {
  PosterToneResolver({this.extract, this.onChanged});

  /// 取色器（可注入测试；默认 [PosterPalette.extractTrio]）。
  final Future<List<Color>?> Function(String url,
      {Map<String, String>? headers})? extract;

  /// 取色结果变化回调（调用方 setState；只在异步完成后触发）。
  final VoidCallback? onChanged;

  /// 当前三色组（null = 未取到/失败 → 调用方用主题色兜底）。
  List<Color>? trio;

  String? _url;
  int _seq = 0;

  /// 发起/更新取色（幂等：同 URL 不重复）。
  ///
  /// 换 URL 时立即清空 [trio]（当帧即回兜底色，取色完成后渐变换色）。
  void ensure(String? url, {Map<String, String>? headers}) {
    if (url == _url) return;
    _url = url;
    trio = null;
    if (url == null || url.isEmpty) return;
    final seq = ++_seq;
    (extract ?? PosterPalette.extractTrio)(url, headers: headers).then((value) {
      if (seq != _seq) return; // 换图后旧结果晚到：丢弃
      trio = value;
      onChanged?.call();
    });
  }
}

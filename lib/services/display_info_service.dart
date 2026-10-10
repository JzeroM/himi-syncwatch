import 'dart:io';

import 'package:flutter/services.dart';
import 'package:himi_syncwatch/services/log_service.dart';

/// 显示器「真实输出分辨率」探测（Android）。
///
/// 用途：渲染尺寸夹紧目标。Android TV/盒子的 Flutter 视图常只有 1080p
/// （UI 层），但输出模式可能是 4K；须用 Display 的真实尺寸做夹紧目标，
/// 才能保住 4K 全分辨率扫描输出，而非误降到 1080p。
///
/// 非 Android / 通道缺失 / 异常 → null（调用方回退到自身显示尺寸）。
/// 结果按会话缓存（显示 mode 播放中极少变化）。
class DisplayInfoService {
  const DisplayInfoService();

  /// 测试可注入的通道（默认 `himi/platform`，与 PlatformInfoPlugin 同）。
  final MethodChannel channel = const MethodChannel('himi/platform');

  /// 最近一次成功探测的物理分辨率（进程级缓存；null = 未取得）。
  static Size? _cached;

  /// 读取真实显示分辨率（物理像素）；不可用返回 null。
  Future<Size?> realDisplaySize() async {
    if (!Platform.isAndroid) return null;
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final map = await channel.invokeMapMethod<String, Object?>('displaySize');
      final w = (map?['width'] as num?)?.toDouble();
      final h = (map?['height'] as num?)?.toDouble();
      if (w != null && h != null && w > 0 && h > 0) {
        _cached = Size(w, h);
        final rate = map?['refreshRate'];
        LogService().log('Diag',
            '显示物理分辨率: ${w.toInt()}x${h.toInt()}'
            '${rate != null ? ' @${rate}Hz' : ''}');
        return _cached;
      }
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    return null;
  }

  /// 测试用：清空缓存。
  static void resetCache() => _cached = null;
}

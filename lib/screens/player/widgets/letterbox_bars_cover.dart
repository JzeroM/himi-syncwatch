import 'package:flutter/material.dart';

import '../../../services/log_service.dart';

/// 视频层之上的黑边遮罩。
///
/// 背景：Android 平台视图（SurfaceView / hybrid composition）接管视频层
/// 后，**视频矩形之外的区域引擎不再重绘**——那里停留在"进入播放器那一刻"
/// 的旧帧缓冲（含当时的控件、时间码）。控制条自动隐藏后，黑边区域仍会
/// "裸露"这些死帧残留（真机实测：3840x1598 片源在 1920x1080 屏上，上下
/// 各约 140px 黑边，快进 10s 黑边区纹丝不动）。
///
/// 修法：在视频层**之上**、控件之下铺一层整屏遮罩，[barsPath] 区域填
/// 不透明黑盖死死帧，视频矩形全透明照常透出。必须整屏铺满（layer bounds
/// 与 platform view 相交才会被合成），只用四条 `Positioned` 黑边会被画进
/// 死缓冲而无效。
///
/// 仅 SurfaceView 档需要（纹理 / Erika / media_kit 不产生此残留）。
class LetterboxBarsCover extends StatelessWidget {
  const LetterboxBarsCover({super.key, required this.aspect});

  /// 视频宽高比（与播放区 `AspectRatio` 所用值一致）。
  final double aspect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = Size(constraints.maxWidth, constraints.maxHeight);
          final path = barsPath(area, aspect);
          if (path.getBounds().isEmpty) return const SizedBox.shrink();
          _logGeometryOnce(area, path);
          return CustomPaint(
            size: area,
            painter: _LetterboxBarsPainter(
              bars: path,
              aspect: aspect,
              area: area,
            ),
          );
        },
      ),
    );
  }

  /// 计算黑边区域路径（宽度优先 contain，与 `RenderAspectRatio` 的
  /// `_applyAspectRatio` 一致）。
  ///
  /// 参数非法（面积任一维非正 / [aspect] 非有限正数）或视频恰好铺满 →
  /// 返回空 Path（调用方渲染 `SizedBox.shrink()`），不抛异常。
  @visibleForTesting
  static Path barsPath(Size area, double aspect) {
    final path = Path();
    if (area.width <= 0 || area.height <= 0) return path;
    if (!aspect.isFinite || aspect <= 0) return path;
    final available = area.width / area.height;
    if (!available.isFinite || available <= 0) return path;

    double videoW;
    double videoH;
    if (aspect >= available) {
      videoW = area.width;
      videoH = area.width / aspect;
    } else {
      videoH = area.height;
      videoW = area.height * aspect;
    }
    if (videoW.isNaN || videoH.isNaN || videoW <= 0 || videoH <= 0) {
      return path;
    }

    final left = (area.width - videoW) / 2;
    final top = (area.height - videoH) / 2;
    final right = left + videoW;
    final bottom = top + videoH;
    void addBar(double l, double t, double r, double b) {
      if (r - l > 0 && b - t > 0) {
        path.addRect(Rect.fromLTRB(l, t, r, b));
      }
    }

    addBar(0, 0, left, area.height);
    addBar(right, 0, area.width, area.height);
    addBar(left, 0, right, top);
    addBar(left, bottom, right, area.height);
    return path;
  }

  static String? _lastLogSignature;

  static void _logGeometryOnce(Size area, Path path) {
    final b = path.getBounds();
    final sig = '${area.width}x${area.height}'
        '|${b.left},${b.top},${b.right},${b.bottom}';
    if (sig == _lastLogSignature) return;
    _lastLogSignature = sig;
    LogService().log(
      'Diag',
      '黑边遮罩: 区域=${area.width.toInt()}x${area.height.toInt()} '
          '覆盖=${b.left.toInt()},${b.top.toInt()},'
          '${b.right.toInt()},${b.bottom.toInt()}',
    );
  }
}

class _LetterboxBarsPainter extends CustomPainter {
  const _LetterboxBarsPainter({
    required this.bars,
    required this.aspect,
    required this.area,
  });

  final Path bars;
  final double aspect;
  final Size area;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(bars, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_LetterboxBarsPainter oldDelegate) =>
      oldDelegate.aspect != aspect || oldDelegate.area != area;
}

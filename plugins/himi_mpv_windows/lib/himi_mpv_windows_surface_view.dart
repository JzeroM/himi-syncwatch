import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Windows 原生 MPV Surface 区域。
///
/// Flutter-Windows 的 platform view 仍不完整，这里用原生子 HWND + 透明
/// Flutter 覆盖层实现同一效果：本 Widget 只负责把视频矩形同步给原生插件。
class HimiMpvWindowsSurfaceView extends StatefulWidget {
  const HimiMpvWindowsSurfaceView({super.key});

  @override
  State<HimiMpvWindowsSurfaceView> createState() =>
      _HimiMpvWindowsSurfaceViewState();
}

class _HimiMpvWindowsSurfaceViewState extends State<HimiMpvWindowsSurfaceView> {
  static const MethodChannel _methods = MethodChannel('himi_mpv_windows');
  final GlobalKey _key = GlobalKey();
  bool _created = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    try {
      await _methods.invokeMethod<void>('createSurface');
      _created = true;
      _scheduleRectUpdate();
    } catch (_) {}
  }

  void _scheduleRectUpdate() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _updateRect());
  }

  void _updateRect() {
    if (!mounted || !_created) return;
    final box = _key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    unawaited(_methods.invokeMethod<void>('updateSurface', <String, dynamic>{
      'left': (origin.dx * dpr).round(),
      'top': (origin.dy * dpr).round(),
      'width': (box.size.width * dpr).round(),
      'height': (box.size.height * dpr).round(),
      'visible': true,
    }));
  }

  @override
  void dispose() {
    unawaited(_methods.invokeMethod<void>('destroySurface'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRectUpdate();
    return SizedBox.expand(key: _key);
  }
}

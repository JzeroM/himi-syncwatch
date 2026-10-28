import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HarmonyOS MPV 原生 Surface 平台视图。
///
/// 直接通过标准 `flutter/platform_views` 通道创建 hybrid 平台视图，
/// 不依赖 Flutter-OH 专属的 `OhosViewController` 类型。这样同一份 Dart
/// 代码也能在标准 Flutter（Windows）上编译。
class HimiMpvSurfaceView extends StatelessWidget {
  const HimiMpvSurfaceView({
    super.key,
    this.onPlatformViewCreated,
  });

  static const String viewType = 'himi_mpv_surface';

  final ValueChanged<int>? onPlatformViewCreated;

  @override
  Widget build(BuildContext context) {
    final layoutDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return _HimiMpvOhosSurface(
          controller: controller as _HimiMpvOhosController,
        );
      },
      onCreatePlatformView: (params) {
        return _HimiMpvOhosController(
          viewId: params.id,
          layoutDirection: layoutDirection,
          onCreated: (id) {
            params.onPlatformViewCreated(id);
            onPlatformViewCreated?.call(id);
          },
        );
      },
    );
  }
}

class _HimiMpvOhosSurface extends StatefulWidget {
  const _HimiMpvOhosSurface({required this.controller});

  final _HimiMpvOhosController controller;

  @override
  State<_HimiMpvOhosSurface> createState() => _HimiMpvOhosSurfaceState();
}

class _HimiMpvOhosSurfaceState extends State<_HimiMpvOhosSurface> {
  void _scheduleLayoutUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      widget.controller.updateLayout(
        size: box.size,
        offset: box.localToGlobal(Offset.zero),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleLayoutUpdate();
    // 必须返回 PlatformViewSurface，而不是普通占位 Widget。
    // PlatformViewSurface 会向 compositor 添加 PlatformViewLayer，鸿蒙
    // hybrid composition 下的 XComponent 原生层才会真正显示；此前
    // SizedBox.expand 只画了 Flutter 占位区域，Surface 模式因此白屏。
    return PlatformViewSurface(
      controller: widget.controller,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}

class _HimiMpvOhosController extends PlatformViewController {
  _HimiMpvOhosController({
    required this.viewId,
    required this.layoutDirection,
    required this.onCreated,
  });

  @override
  final int viewId;
  final TextDirection layoutDirection;
  final ValueChanged<int> onCreated;

  bool _created = false;
  bool _disposed = false;
  Size _lastSize = Size.zero;
  Offset _lastOffset = Offset.zero;

  @override
  bool get awaitingCreation => !_created && !_disposed;

  @override
  Future<void> create({Size? size, Offset? position}) async {
    if (_disposed || _created) return;
    _lastSize = size ?? Size.zero;
    _lastOffset = position ?? Offset.zero;
    await SystemChannels.platform_views
        .invokeMethod<void>('create', <String, dynamic>{
      'id': viewId,
      'viewType': HimiMpvSurfaceView.viewType,
      'direction': layoutDirection == TextDirection.rtl ? 1 : 0,
      'hybrid': true,
    });
    _created = true;
    onCreated(viewId);
  }

  Future<void> updateLayout({
    required Size size,
    required Offset offset,
  }) async {
    if (_disposed || !_created || size.isEmpty) return;
    if (size != _lastSize) {
      _lastSize = size;
      await SystemChannels.platform_views.invokeMapMethod<Object?, Object?>(
        'resize',
        <String, dynamic>{
          'id': viewId,
          'width': size.width,
          'height': size.height,
        },
      );
    }
    if (offset != _lastOffset) {
      _lastOffset = offset;
      await SystemChannels.platform_views.invokeMethod<void>(
        'offset',
        <String, dynamic>{
          'id': viewId,
          'top': offset.dy,
          'left': offset.dx,
        },
      );
    }
  }

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_created) {
      await SystemChannels.platform_views.invokeMethod<void>(
        'dispose',
        <String, dynamic>{
          'id': viewId,
          'hybrid': true,
        },
      );
    }
    _created = false;
  }
}

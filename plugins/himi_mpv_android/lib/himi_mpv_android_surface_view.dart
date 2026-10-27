import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Android MPV 原生 Surface 平台视图。
///
/// 原生 SurfaceView 的 Surface 被转换为 JNI global ref 交给 libmpv
/// (`wid`)。Flutter 层保持透明，控件/弹幕叠加在上方。
class HimiMpvAndroidSurfaceView extends StatelessWidget {
  const HimiMpvAndroidSurfaceView({
    super.key,
    this.onPlatformViewCreated,
  });

  static const String viewType = 'himi_mpv_android_surface';

  final ValueChanged<int>? onPlatformViewCreated;

  @override
  Widget build(BuildContext context) {
    final layoutDirection =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: layoutDirection,
        );
        controller.addOnPlatformViewCreatedListener((id) {
          params.onPlatformViewCreated(id);
          onPlatformViewCreated?.call(id);
        });
        controller.create();
        return controller;
      },
    );
  }
}

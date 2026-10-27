import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// HarmonyOS MPV 原生 Surface 平台视图。
///
/// 使用 hybrid composition（`initExpensiveOhosView`）把 ArkUI XComponent
/// 放进原生视图树，mpv 直接渲染到 XComponent 的 OHNativeWindow。Flutter
/// 层保持透明，控件/弹幕由 Flutter 叠加在上方。
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
        return OhosViewSurface(
          controller: controller as OhosViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveOhosView(
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

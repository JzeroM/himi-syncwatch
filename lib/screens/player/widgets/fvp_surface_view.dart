import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Android SurfaceView 视频输出通道（fvp/video-view platform view）。
///
/// 复刻 fvp `buildViewWithOptions` 的 hybrid composition 路径：
/// SurfaceView 在 Flutter 默认 TLHC 下位置/z 序错误（fvp 源码注释与
/// Flutter platform views 文档），须经 `initExpensiveAndroidView`。
/// creationParams 直接挂 mdk.Player 的 nativeHandle——nativeSetSurface
///（fvp_plugin.cpp）自包含包装播放器并 setOutputSurface，无需纹理
/// CreateRT。surface buffer 固定为视频分辨率（FvpVideoView 内
/// setFixedSize），合成器按视图矩形缩放，TV 上可全分辨率扫描输出。
class FvpSurfaceView extends StatelessWidget {
  const FvpSurfaceView({
    super.key,
    required this.nativeHandle,
    required this.videoWidth,
    required this.videoHeight,
    this.tunnel = false,
  });

  /// mdk.Player 的原生句柄（fvp `Player.nativeHandle`）。
  final int nativeHandle;

  /// 视频分辨率（creationParams 宽高 = surface buffer 尺寸）。
  final int videoWidth;
  final int videoHeight;

  /// 解码器直通——texture 档 tunnel 同语义：nativeSetSurface 走
  /// directSurface 分支，MediaCodec 直写 SurfaceView 的 buffer queue，
  /// 完全不经 mdk GL/EGL（EGL 故障设备的自愈通路）。false 时走
  /// GL presenter（支持 snapshot 等需要渲染器的能力）。
  final bool tunnel;

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, Object>{
      'player': nativeHandle,
      'width': videoWidth,
      'height': videoHeight,
      'tunnel': tunnel,
    };
    return Builder(
      builder: (context) {
        // RTL 应用里方向须取自 context，硬编码 ltr 会布局错位
        // （与 fvp buildViewWithOptions 同）。
        final layoutDirection =
            Directionality.maybeOf(context) ?? TextDirection.ltr;
        return PlatformViewLink(
          // 分辨率变化（换集）或 tunnel 变化（EGL 故障自愈）时重建
          // platform view：surfaceDestroyed → surfaceCreated 按新
          // tunnel 参数重新 nativeSetSurface
          key: ValueKey<String>(
              'fvp-video-view-${videoWidth}x$videoHeight-t$tunnel'),
          viewType: 'fvp/video-view',
          surfaceFactory: (context, controller) {
            return AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const <Factory<
                  OneSequenceGestureRecognizer>>{},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            );
          },
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: 'fvp/video-view',
              layoutDirection: layoutDirection,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            );
            controller.addOnPlatformViewCreatedListener(
              params.onPlatformViewCreated,
            );
            controller.create();
            return controller;
          },
        );
      },
    );
  }
}

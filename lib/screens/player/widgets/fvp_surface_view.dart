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
/// （fvp_plugin.cpp）自包含包装播放器并 setOutputSurface，无需纹理
/// CreateRT。surface buffer 固定为视频分辨率（FvpVideoView 内
/// setFixedSize），合成器按视图矩形缩放，TV 上可全分辨率扫描输出。
class FvpSurfaceView extends StatelessWidget {
  const FvpSurfaceView({
    super.key,
    required this.nativeHandle,
    required this.videoWidth,
    required this.videoHeight,
    this.tunnel = false,
    this.epoch = 0,
    this.onCreated,
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

  /// surface 世代：切集 +1 强制销毁重建 platform view（key 变化）。
  /// 旧 view 的 surfaceDestroyed（fvp native setDecoders 清码）必须先于
  /// 新 view 的 surfaceCreated（setDecoders(surface) 重开）落定，否则
  /// destroy 晚到会清掉新集解码器（声画全停）。
  final int epoch;

  /// platform view 创建完成（surfaceCreated 已绑定）回调。
  final VoidCallback? onCreated;

  /// platform view key（含世代）：同参同 key 复用，epoch 变化必重建。
  static String surfaceKey({
    required int width,
    required int height,
    required bool tunnel,
    required int epoch,
  }) =>
      'fvp-video-view-${width}x$height-t$tunnel-e$epoch';

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
          // 分辨率/世代/tunnel 变化时重建 platform view：
          // surfaceDestroyed → surfaceCreated 按 tunnel 参数重新
          // nativeSetSurface
          key: ValueKey<String>(surfaceKey(
            width: videoWidth,
            height: videoHeight,
            tunnel: tunnel,
            epoch: epoch,
          )),
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
            controller.addOnPlatformViewCreatedListener((id) {
              params.onPlatformViewCreated(id);
              onCreated?.call();
            });
            controller.create();
            return controller;
          },
        );
      },
    );
  }
}

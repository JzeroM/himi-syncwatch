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

  /// surface 世代：**必要重建**（分辨率/档位/tunnel 变化）时由两阶段
  /// 协调器在 attach 阶段 +1；同分辨率切集恒不递增——view/surface/
  /// EGL 上下文全程复用（v1.1.82 根修：迟到 surface + 上下文重建会让
  /// mdk renderer 永久丢帧，画面定格在首帧）。
  final int epoch;

  /// platform view 创建完成（surfaceCreated 已绑定）回调。
  final VoidCallback? onCreated;

  /// platform view viewType（与 fvp `buildViewWithOptions` 一致）。
  static const String platformViewType = 'fvp/video-view';

  /// nativeSetSurface creationParams 协议（键名须与上游 fvp
  /// `FvpVideoView` Java 侧读取一致，升版 fvp 时对照测试防失配）：
  /// - `player`: mdk.Player 原生句柄
  /// - `width`/`height`: surface buffer 尺寸（视频分辨率）
  /// - `tunnel`: 解码器直通开关
  static Map<String, Object> creationParams({
    required int nativeHandle,
    required int videoWidth,
    required int videoHeight,
    required bool tunnel,
  }) =>
      <String, Object>{
        'player': nativeHandle,
        'width': videoWidth,
        'height': videoHeight,
        'tunnel': tunnel,
      };

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
    final creationParams = FvpSurfaceView.creationParams(
      nativeHandle: nativeHandle,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      tunnel: tunnel,
    );
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
          viewType: platformViewType,
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
              viewType: platformViewType,
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

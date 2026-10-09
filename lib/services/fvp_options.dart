/// fvp（mdk Flutter 封装）启动期选项组装。
///
/// [FvpPlugin.registerWith] 的 options 全局生效一次且须在首个播放器
/// 创建前调用，故本函数供 `_bootstrap` 在设置加载完成后调用；修改
/// 相关设置需重启应用生效。
///
/// 选项来源均为 mdk wiki Global Options：
/// - `audio.xa2.persistent`（Windows）：停止不销毁 XAudio2 引擎，
///   切集换源更快且消除设备重启瞬态；
/// - `gl.yuv_sampler`：mdk 注明 "for android and rockchip arm driver
///   hardware decoder rendering"，YUV 采样渲染变体；
/// - `surfacetexture.glcontext`：SurfaceTexture 无有效 GL 上下文时
///   创建 context（纹理通道黑屏 workaround，视频全黑机型实验开关）。
///
/// 注意：fvp registerWith 的 `maxWidth`/`maxHeight`（纹理尺寸上限）
/// 对本应用**无效**——himi 绕过 video_player 插件层（mdk.Player FFI
/// 直用 + 自封装 FvpSurfaceView），那两个选项只在
/// `MdkVideoPlayerPlatform.create()` 里消费。渲染尺寸夹紧在
/// player_screen 内自实现（RenderTargetClamp + updateTexture 传参 /
/// FvpSurfaceView creationParams）。
///
/// 纯函数，便于单测。
Map<String, Object> buildFvpOptions({
  required bool xa2Persistent,
  required bool renderCompatMode,
}) {
  final global = <String, Object>{
    if (xa2Persistent) 'audio.xa2.persistent': 1,
    if (renderCompatMode) ...{
      'gl.yuv_sampler': 1,
      'surfacetexture.glcontext': 1,
    },
  };
  return {'global': global};
}

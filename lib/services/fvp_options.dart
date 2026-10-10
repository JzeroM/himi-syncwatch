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
///   创建 context（纹理通道黑屏 workaround，视频全黑机型实验开关）；
/// - `avsync.audio.adaptive`（全平台常开，1.1.186）：视频落后于音频
///   时放慢音频速度保同步（mdk 0.37+），配合音频硬解减少成簇丢帧；
/// - `avsync.video.decoder_drop`（全平台常开，1.1.186）：音画严重
///   不同步时解码端平滑丢帧（fvp#336 wang-bin 方案），替代渲染端
///   簇状丢帧；
/// - `videoout.hdr`（实验开关，1.1.187）：0=恒 tone map 到 sRGB
///   （mdk 默认）；1=按屏幕能力启用 HDR 输出（metal/d3d11；Android
///   EGL 可能忽略）。恒显式注入使 Diag 取证行能区分 A/B 档位。
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
  required bool videoOutHdrAuto,
}) {
  final global = <String, Object>{
    if (xa2Persistent) 'audio.xa2.persistent': 1,
    if (renderCompatMode) ...{
      'gl.yuv_sampler': 1,
      'surfacetexture.glcontext': 1,
    },
    // avsync 两参数全平台常开（见 doc 头），音频钟抖动/解码突发
    // 导致的簇状丢帧缓解（1.1.186：4K60 手机丢帧诊断）。
    'avsync.audio.adaptive': 1,
    'avsync.video.decoder_drop': 1,
    // videoout.hdr 恒注入（见 doc 头）：HDR10 4K60 丢帧 A/B 实验，
    // Diag 行 `fvp options` 显式可见当前档位。
    // 注意：player_screen 已通过 setColorSpace(bt709) 强制 SDR 输出
    // （1.1.191，修复 mdk-sdk#361 HDR10 丢帧+发白），此全局选项
    // 仅影响未显式调 setColorSpace 的场景。
    'videoout.hdr': videoOutHdrAuto ? 1 : 0,
  };
  return {'global': global};
}

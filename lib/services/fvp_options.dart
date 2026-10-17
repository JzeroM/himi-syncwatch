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
/// - `avsync.audio.adaptive`（1.1.186 恒开 → 现改开关、默认关）：
///   视频落后于音频时放慢音频速度保同步（mdk 0.37+），配合音频硬解
///   减少成簇丢帧；但 mdk 0.36 时代它是空操作，升 mdk 0.39.0 后首次
///   真正生效，盒子 SDR 卡顿疑似回归 → 默认关，手机 4K60 场景可开；
/// - `avsync.video.decoder_drop`（**已移除**，1.1.195）：changelog 0.37.0
///   提到 "Support decoder frame drop if out of sync" 但选项名未在
///   Global Options 文档中列出（名称来自 fvp#336 对话）。怀疑与渲染端
///   丢帧逻辑冲突导致 HDR10 实验失效，移除后 A/B 验证；
/// - `videoout.hdr`（**恒 0**）：0=恒 tone map 到 sRGB；1=按屏幕能力启用
///   HDR 输出（metal/d3d11；Android EGL 可能忽略），且**会覆盖
///   `Player.set(ColorSpace)`**。himi 的 HDR/DV 输出改由
///   `Player.set(ColorSpace)` 逐内容控制（见 PlayerScreen.dvOutputColorSpace
///   / _applyOutputColorSpace），故此处必须恒为 0，避免启动期全局覆盖。
///
/// 注意：fvp registerWith 的 `maxWidth`/`maxHeight`（纹理尺寸上限）
/// 与 `lowLatency`（起播加速）对本应用**无效**——himi 绕过 video_player
/// 插件层（mdk.Player FFI 直用 + 自封装 FvpSurfaceView），那两个选项
/// 只在 `MdkVideoPlayerPlatform.create()` 里消费。纹理尺寸夹紧在
/// player_screen 内自实现（RenderTargetClamp + updateTexture 传参 /
/// FvpSurfaceView creationParams）；lowLatency=1 等效属性在
/// `_initPlayerProperties` 内直接写入（见 MdkPlayerAdapter
/// .lowLatencyProperties）。
///
/// 纯函数，便于单测。
Map<String, Object> buildFvpOptions({
  required bool xa2Persistent,
  required bool renderCompatMode,
  required bool avsyncAudioAdaptive,
}) {
  final global = <String, Object>{
    if (xa2Persistent) 'audio.xa2.persistent': 1,
    if (renderCompatMode) ...{
      'gl.yuv_sampler': 1,
      'surfacetexture.glcontext': 1,
    },
    // avsync.audio.adaptive（见 doc 头）：现改开关、默认关，
    // mdk 0.39.0 首次真正生效后盒子 SDR 卡顿疑似回归。
    'avsync.audio.adaptive': avsyncAudioAdaptive ? 1 : 0,
    // videoout.hdr 恒 0（见 doc 头）：逐内容 HDR 输出改由
    // Player.set(ColorSpace) 控制，此全局项须为 0 以免覆盖之。
    'videoout.hdr': 0,
  };
  return {'global': global};
}

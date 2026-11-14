/// 697：渲染后端判定（四端共用同一套规则）。
///
/// ## 为什么需要这个文件
///
/// 调试面板的「杜比视界 → 后端」要回答两个问题：
///
/// 1. **实际**跑在哪个后端？（Vulkan / D3D11 / OpenGL）
/// 2. 这个后端能不能做 DV 元数据处理（libplacebo 的 compute shader）？
///
/// ## 两个坑（真机踩过）
///
/// **坑 1：`gpu-context` 读回来是「配置列表」，不是实际值。**
///
/// 我们为了让 Vulkan 失败能自动回落，给 mpv 下发的是优先级列表：
///
///     gpu-api      = vulkan,opengl
///     gpu-context  = androidvk,android
///
/// 而 mpv 的 `gpu-api` / `gpu-context` 是 `OPT_SETTINGSLIST` 类型，
/// 读回来就是完整候选串 `vulkan,opengl`。**据此无法判断实际选了哪个。**
/// 要看实际值必须读 `current-gpu-context`（mpv `command.c` 里
/// `mp_property_gpu_context` → `vo->context_name`）。
///
/// **坑 2：安卓 Vulkan 的上下文名不含 "vulkan" 这个子串。**
///
///     OpenGL → android
///     Vulkan → androidvk   ← 没有 "vulkan"
///
/// 早期判定写成 `ctx.contains('vulkan')`，导致真机明明跑在 Vulkan 上，
/// 面板却报「不支持 DV / 画面会偏色」（697 真机截图）。
library;

/// 上下文名 → 后端族。
enum RenderBackend {
  /// Vulkan（libplacebo 有 compute shader → 能做 DV 动态元数据）
  vulkan,

  /// Direct3D 11（Windows，同样有 compute → 支持 DV）
  d3d11,

  /// OpenGL / OpenGL ES（没有可靠的 compute + SSBO 组合，DV 会降级）
  opengl,

  /// 未知 / 空串
  unknown,
}

/// 把 mpv 的上下文名（可能是逗号分隔的候选列表）归类到后端族。
///
/// 只看**第一个**非空项：优先级列表的语义就是「第一个能起来的就是它」，
/// 后面的是回落项。若传的是实际值（`current-gpu-context`），本来就只有一项。
RenderBackend renderBackendOf(String? context) {
  final raw = (context ?? '').toLowerCase();
  if (raw.trim().isEmpty) return RenderBackend.unknown;

  final first = raw
      .split(',')
      .map((e) => e.trim())
      .firstWhere((e) => e.isNotEmpty, orElse: () => '');
  if (first.isEmpty) return RenderBackend.unknown;

  // `androidvk` / `ohosvk` / `vulkan` / `x11vk`……都带 `vk`
  if (first.contains('vk') || first.contains('vulkan')) {
    return RenderBackend.vulkan;
  }
  if (first.contains('d3d11')) return RenderBackend.d3d11;
  if (first.contains('android') ||
      first.contains('egl') ||
      first.contains('glx') ||
      first.contains('wayland') ||
      first.contains('opengl') ||
      first.contains('gl')) {
    return RenderBackend.opengl;
  }
  return RenderBackend.unknown;
}

/// 后端能否做 DV 元数据处理（libplacebo compute）。
///
/// 安卓 / 鸿蒙走 Vulkan、Windows 走 D3D11 都可以；OpenGL 路径下
/// `hdr-compute-peak` 会被 mpv 自动关掉（`video/out/gpu/video.c` 里
/// 三处写回 `-1`），逐场景峰值拿不到，DV 观感会打折。
bool backendSupportsDv(String? context) {
  final backend = renderBackendOf(context);
  return backend == RenderBackend.vulkan || backend == RenderBackend.d3d11;
}

/// 后端族的展示名。
String renderBackendLabel(RenderBackend backend) => switch (backend) {
      RenderBackend.vulkan => 'Vulkan',
      RenderBackend.d3d11 => 'D3D11',
      RenderBackend.opengl => 'OpenGL',
      RenderBackend.unknown => '未知',
    };

/// 面板「后端」行的判定输入：优先实际值，缺失才退回配置列表。
///
/// 真机排障时**实际值才是真相**；配置列表只说明我们「允许」什么。
String effectiveRenderContext({
  required String actual,
  required String configured,
}) {
  final a = actual.trim();
  if (a.isNotEmpty) return a;
  return configured.trim();
}

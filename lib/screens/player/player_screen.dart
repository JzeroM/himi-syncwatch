import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:himi_syncwatch/player_core/player_core_bridge.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';
import 'package:himi_syncwatch/services/player/mdk_player_adapter.dart';
import 'package:himi_syncwatch/services/player/mpv_player_adapter.dart';
import 'package:himi_mpv_android/himi_mpv_android.dart'
    show HimiMpvAndroidSurfaceView;
import 'package:himi_mpv_ohos/himi_mpv_ohos.dart' show HimiMpvSurfaceView;
import 'package:himi_mpv_windows/himi_mpv_windows.dart'
    show HimiMpvWindowsSurfaceView;
import 'package:himi_syncwatch/services/player/stream_reload_scheduler.dart';
import 'package:himi_syncwatch/services/player/clock_offset_estimator.dart';
import 'package:himi_syncwatch/services/player/stream_stall_guard.dart';
import 'package:erika_flutter/erika_flutter.dart'
    show ErikaVideoView, ErikaOutputMode;
import 'package:himi_syncwatch/services/player/erika_player_adapter.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show Video, VideoController;
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:himi_syncwatch/core/constants.dart';
import 'package:himi_syncwatch/models/episode_info.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/media_segment.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/device_profile_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/media_state_override_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/room_provider.dart';
import 'package:himi_syncwatch/providers/rtm_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/track_migration.dart';
import 'package:himi_syncwatch/services/server_route_service.dart';
import 'package:uuid/uuid.dart';
import 'package:agora_rtm/agora_rtm.dart';
import 'package:himi_syncwatch/services/decode_mode_service.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/display_info_service.dart';
import 'package:himi_syncwatch/services/hdr_output_policy.dart';
import 'package:himi_syncwatch/services/render_target_clamp.dart';

import 'package:himi_syncwatch/services/audio_filter_policy.dart';
import 'package:himi_syncwatch/services/audio_fade.dart';
import 'package:himi_syncwatch/services/snapshot_probe.dart';
import 'package:himi_syncwatch/services/orientation_sensor_gate.dart';
import 'package:himi_syncwatch/services/decoder_report.dart';
import 'package:himi_syncwatch/services/diagnostic_export.dart';
import 'package:himi_syncwatch/services/egl_fault_detector.dart';
import 'package:himi_syncwatch/services/codec_mime_map.dart';
import 'package:himi_syncwatch/services/dolby_vision_service.dart';
import 'package:himi_syncwatch/services/rtm_service.dart';
import 'package:himi_syncwatch/services/network_speed_meter.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_caches.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_candidate.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_matcher.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_timeline.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';
import 'package:himi_syncwatch/utils/playback_gesture.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/room/room_share_dialog.dart';
import 'package:himi_syncwatch/widgets/tv/tv_back_confirm.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/screens/player/room_resource_search.dart';
import 'package:himi_syncwatch/screens/player/player_hotkey.dart';
import 'package:himi_syncwatch/screens/player/player_orientation.dart';
import 'package:himi_syncwatch/screens/player/player_platform.dart';
import 'package:himi_syncwatch/screens/player/track_initial_selection.dart';
import 'package:himi_syncwatch/screens/player/widgets/decode_mode_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/display_adjust_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/danmaku_overlay.dart';
import 'package:himi_syncwatch/screens/player/widgets/episode_select_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/glass_slider_theme.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/audio_track_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/version_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/sync_debug_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/fvp_surface_view.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_kernel_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_top_bar.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_bottom_row.dart';
import 'package:himi_syncwatch/screens/player/player_lifecycle_policy.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_clock.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_lock_button.dart';
import 'package:himi_syncwatch/screens/player/widgets/speed_menu_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/segment_mark_panel.dart';
import 'package:himi_syncwatch/screens/player/controls_auto_hide.dart';
import 'package:himi_syncwatch/screens/player/widgets/selector_side_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/seek_time_labels.dart';
import 'package:himi_syncwatch/screens/player/widgets/subtitle_style_panel.dart';
import 'package:himi_syncwatch/screens/player/widgets/video_gesture_layer.dart';
import 'package:himi_syncwatch/screens/player/widgets/letterbox_bars_cover.dart';
import 'package:himi_syncwatch/screens/player/player_lock_controller.dart';
import 'package:himi_syncwatch/services/subtitle_delay_file.dart';
import 'package:himi_syncwatch/services/subtitle_style_store.dart';
import 'package:himi_syncwatch/services/manual_segment_store.dart';
import 'package:himi_syncwatch/services/media_segment_resolver.dart';
import 'package:himi_syncwatch/services/segment_skip_controller.dart';
import 'package:himi_syncwatch/services/platform/windows_clipboard_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:himi_syncwatch/services/count_retry.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/mdk_log_parser.dart';
import 'package:himi_syncwatch/services/playback_diagnostics.dart';
import 'package:himi_syncwatch/services/render_storm_detector.dart';
import 'package:himi_syncwatch/services/rtm/room_info_codec.dart';
import 'package:himi_syncwatch/services/switch_volume_guard.dart';
import 'package:himi_syncwatch/services/video_avfilter_policy.dart';
import 'package:himi_syncwatch/services/window_fullscreen_service.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';

/// 兼容 re-export：既有测试/调用方从 player_screen 导入 [EpisodeInfo]。
export 'package:himi_syncwatch/models/episode_info.dart' show EpisodeInfo;

/// 播放器默认音量（0-1）：进入播放器即为 80%。
const kPlayerDefaultVolume = 0.8;

/// 播放器默认亮度（0-1）：进入播放器即为 80%。
const kPlayerDefaultBrightness = 0.8;

class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? roomCode;
  final String? mediaSourceId;
  final bool isHost;
  final String audienceName;

  /// 来源服务器本地配置 id（跨服务器播放）；null = 当前激活服务器。
  final String? serverId;

  /// 标题艺术字图 URL（详情页传入的 Logo 图）；null/房间模式不显示。
  final String? logoUrl;

  /// 起播位置（毫秒；详情页「继续观看」传入，首次加载 seek 到此）。
  final int startMs;

  /// 弹幕错源排除线索：作品年份（Emby ProductionYear）；null = 未知，年份降权。
  final int? year;

  /// 弹幕错源排除线索：内容类型（'movie' / 'series'）；null = 未知，不按类型排除。
  final String? kind;

  /// 弹幕错源排除线索：是否为动画（Emby 类型含「动画」）；用于排除真人剧类候选。
  final bool isAnimation;

  /// 手动片头/片尾仓库（测试注入）。null = 使用本地文件存储。
  final ManualSegmentRepository? manualSegmentRepository;

  const PlayerScreen({
    super.key,
    required this.itemId,
    this.roomCode,
    this.mediaSourceId,
    this.isHost = false,
    this.audienceName = '',
    this.serverId,
    this.logoUrl,
    this.startMs = 0,
    this.year,
    this.kind,
    this.isAnimation = false,
    this.manualSegmentRepository,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();

  /// 焦点 [candidate] 是否位于 [root] 子树内（含 root 自身）。
  /// 控制条卸载前据此判断是否回落热键层，防止焦点悬空（方向键"选不到"）。
  @visibleForTesting
  static bool focusWithin(FocusNode root, FocusNode? candidate) =>
      candidate != null &&
      (candidate == root || candidate.ancestors.contains(root));

  /// 控制条自动隐藏时长（5 秒无操作后隐藏全部控件，含选择器面板）。
  static const Duration controlsAutoHideAfter = Duration(seconds: 5);

  /// 播完自动下一集位置兜底的 seek 冷却：seek 完成后此窗口内忽略
  /// 结尾位置判定（防拖进度条/seek 后 position 短暂停在结尾被误判）。
  static const Duration autoNextSeekCooldown = Duration(seconds: 3);

  /// 右侧选择器面板宽度：随屏宽自适应（0.42×屏宽，钳在 260~320），
  /// 保证滑杆有足够横向行程（字幕样式/弹幕调节等共用）。
  @visibleForTesting
  static double selectorPanelWidth(double screenWidth) =>
      (screenWidth * 0.42).clamp(260.0, 320.0);

  /// 选择器面板几何（top/bottom/right）：常规面板避开顶栏与底部控制条；
  /// 选集面板（[fullBleed]）上下右三边贴边铺满（v1.1.175）。
  @visibleForTesting
  static ({double top, double bottom, double right}) selectorPanelBox({
    required bool fullBleed,
    required double safeTop,
    required double safeBottom,
  }) =>
      fullBleed
          ? (top: 0.0, bottom: 0.0, right: 0.0)
          : (
              top: safeTop + 48,
              // 116 = 桌面/TV 控制条高度（110）+ 6px 余量；叠加安全区
              //（手机手势条会抬高控制条，控制条高 110+inset）
              bottom: 116 + safeBottom,
              right: 12,
            );

  /// 设置 → 弹幕时间轴配置（纯映射，供测试）。
  @visibleForTesting
  static DanmakuTimelineConfig danmakuTimelineConfig(AppSettings s) =>
      DanmakuTimelineConfig(
        scrollRows: s.danmakuScrollRows,
        topRows: s.danmakuTopRows,
        bottomRows: s.danmakuBottomRows,
        blockTop: s.danmakuBlockTop,
        blockBottom: s.danmakuBlockBottom,
        blockWords: s.danmakuBlockWords
            .split(',')
            .map((w) => w.trim())
            .where((w) => w.isNotEmpty)
            .toList(),
        maxCount: s.danmakuLimitCount ? s.danmakuMaxCount : null,
      );

  /// Emby 播放进度上报间隔（3 秒）。
  static const Duration playbackReportInterval = Duration(seconds: 3);

  /// 字幕样式属性写入门控（纯逻辑，可单测）：
  /// - 未挂载（页面已销毁）
  /// - 引擎热切换/内容路由重建中（`_player` 可能仍指向已释放的旧引擎）
  /// 以上任一成立即禁止写入原生播放器（Windows 拖字幕滑杆闪退根因）。
  @visibleForTesting
  static bool canWriteSubtitleStyle({
    required bool mounted,
    required bool switchingEngine,
  }) =>
      mounted && !switchingEngine;

  /// 字幕样式属性写入序列（纯逻辑，可单测）。
  ///
  /// MDK 的 `subtitle.margin.y` 在字幕垂直居中时无效；PGS 等位图字幕
  /// 部分资源会被按居中处理，导致只能缩放不能移动。位图且走 MDK 时先
  /// 强制底部对齐，再写位置/缩放，使位置滑杆生效。
  @visibleForTesting
  static List<({String name, String value})> subtitleStyleWrites({
    required bool forceBitmapBottom,
    required double scale,
    required int marginY,
  }) =>
      [
        if (forceBitmapBottom) (name: 'subtitle.alignment.y', value: '1'),
        (name: 'subtitle.scale', value: scale.toStringAsFixed(2)),
        (name: 'subtitle.margin.y', value: '$marginY'),
      ];

  /// 轮询等待 [ready] 为 true（超时返回 false）。
  @visibleForTesting
  static Future<bool> waitUntil(
    bool Function() ready, {
    Duration timeout = const Duration(seconds: 2),
    Duration pollMs = const Duration(milliseconds: 50),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (ready()) return true;
      await Future<void>.delayed(pollMs);
    }
    return ready();
  }

  /// 视频尺寸解析（与 fvp _setVideoSize 同规则）：
  /// 宽高无效（<=0，如 probesize 未解析出）→ null；
  /// par 归一化高度；rotation 90/270 时交换宽高。
  @visibleForTesting
  static Size? resolveVideoSize({
    required int width,
    required int height,
    double par = 1.0,
    int rotation = 0,
  }) {
    if (width <= 0 || height <= 0) return null;
    final h = (height / (par > 0 ? par : 1.0)).round();
    if (rotation % 180 == 90) {
      return Size(h.toDouble(), width.toDouble());
    }
    return Size(width.toDouble(), h.toDouble());
  }

  /// SurfaceView 是否需要两阶段重建（见 [_remountSurfaceView]）：
  /// 仅分辨率变化时 true。
  ///
  /// 同尺寸切集恒 false（v1.1.82 根修）：切集拆建 view 会让 mdk
  /// renderer 在重建的 EGL 上下文上渲 1 帧后永久丢帧，画面定格、
  /// 音频进度正常。texture/tunnel 档与首播（oldSize 为 null）不涉及
  /// platform view 拆建，同样 false。
  @visibleForTesting
  static bool surfaceViewNeedsRemount({
    required String output,
    required Size? oldSize,
    required Size? newSize,
  }) =>
      AppSettings.isSurfaceViewMode(output) &&
      oldSize != null &&
      newSize != null &&
      oldSize != newSize;

  /// SurfaceView 视图是否以直写（解码器直写 ANativeWindow）参数构建：
  /// - 手动选择直写档（surfaceViewDirect）恒 true；
  /// - EGL 故障设备（[eglFault]，eglChooseConfig 3004）恒直写绕开坏 GL。
  ///
  /// v1.2.14：视图构建（`tunnel` 参数）与渲染兜底（定时 renderVideo()
  /// 补充推进）共用本判定，单一来源防漂移——v1.2.11 新增 surfaceViewDirect
  /// 档时曾漏改兜底条件（写死 `output == 'surfaceView'`），10-bit 内容
  /// 走该档后失去兜底，起播竞态下 mdk renderer 永久丢帧、画面定格。
  @visibleForTesting
  static bool surfaceViewDirectWrite({
    required bool usesSurfaceView,
    required bool surfaceViewDirect,
    required bool eglFault,
  }) =>
      usesSurfaceView && (surfaceViewDirect || eglFault);

  /// 会话级 EGL 自愈触发判定（v1.2.14）：仅「进入本次播放会话后新出现」
  /// 的故障才触发自愈。
  ///
  /// 会话开始前已置位（[faultAtSessionStart]，持久标记设备）说明视图已按
  /// 直写参数构建，无需自愈；旧行为会在首条 mdk 日志（任意级别）到达时
  /// 误触发一次两阶段重建，制造「迟到 surface + 上下文重建 → mdk renderer
  /// 永久丢帧」竞态（偶发起播画面定格根因）。
  @visibleForTesting
  static bool shouldTriggerEglHeal({
    required bool fault,
    required bool handled,
    required bool faultAtSessionStart,
  }) =>
      fault && !handled && !faultAtSessionStart;

  /// 进入播放器的初始控制条设置：
  /// - 全模式启动自动隐藏计时（此前初进无人调 `_resetHideTimer`，控件
  ///   永不自动隐藏——非 TV 模式同样需要"播放中 5 秒隐藏"）；
  /// - TV 且控件可见：postFrame 落焦 seek 滑杆。热键层 autofocus 会先把
  ///   焦点抢到无描边的裸 Focus 节点（屏幕无焦点环），而 `_showControlsForTv`
  ///   的落焦只挂在"隐藏→显示"翻转分支、初进不经过——故此处补落焦，
  ///   落点与"调出控件"完全一致。
  /// - 守卫重试：控制条仅在 `_isPlayerReady` 后构建（首帧滑杆未挂树、
  ///   seekNode.context 为 null），未附着时逐帧重试直到控件出现；
  ///   [shouldRetry] 返回 false（页面已销毁/控件已隐藏）或达到
  ///   [maxAttempts] 上限即放弃。
  @visibleForTesting
  static void scheduleInitialControlsSetup({
    required bool tvMode,
    required bool controlsVisible,
    required FocusNode seekNode,
    required VoidCallback onStartHideTimer,
    bool Function()? shouldRetry,
    int maxAttempts = 600,
  }) {
    onStartHideTimer();
    if (!tvMode || !controlsVisible) return;
    var attempts = 0;
    void attempt() {
      if (seekNode.context != null) {
        seekNode.requestFocus();
        return;
      }
      attempts++;
      if (attempts >= maxAttempts) return;
      if (shouldRetry != null && !shouldRetry()) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
  }

  /// 控制条横竖屏切换按钮是否显示：移动端需要，TV 全程横屏无需旋转控制。
  @visibleForTesting
  static bool showRotateButton({
    required bool tvMode,
    required bool mobilePlatform,
  }) =>
      mobilePlatform && !tvMode;

  /// 旋转按钮图标：语义直白的「旋转屏幕」（原 screen_lock_* 是「锁定」
  /// 语义，用户看不懂），保持无底纯图标与字幕/音轨按钮一致。
  @visibleForTesting
  static IconData get rotateButtonIcon => Icons.screen_rotation_alt;

  /// 控制条顶部标题艺术字（Logo 图）是否显示：仅单人播放且有 logo，
  /// 房间联播不显示（房间模式不加 logo）。
  @visibleForTesting
  static bool showLogoInControls({
    required String? logoUrl,
    required bool isRoom,
  }) =>
      !isRoom && logoUrl != null && logoUrl.isNotEmpty;

  /// 合并解码器列表中的 image=N 属性（1.1.190 官方 setDecoders 方式）。
  ///
  /// mdk 官方方式：`setDecoders(["AMediaCodec:image=0"])` 属性内嵌在
  /// 解码器名中，创建时读取，不受 mdk 内部 `video.decoder=scale=WxH`
  /// 覆写影响（1.1.189 setProperty 方式被覆写导致实验无效）。
  @visibleForTesting
  static List<String> mergeDecoderListImage(
    List<String> decoders,
    String imageVal,
  ) =>
      DecodeModeService.withDecoderImage(decoders, imageVal);

  /// 合并解码器列表中的 low_latency=1 属性（1.1.192 实验）。
  ///
  /// AMediaCodec low_latency 改变硬解器内部 buffer 管理路径，
  /// A/B 验证 10-bit P010 4K60 簇状丢帧是否为 Qualcomm 硬解 bug。
  @visibleForTesting
  static List<String> mergeDecoderLowLatency(List<String> decoders) =>
      DecodeModeService.withDecoderLowLatency(decoders);

  /// 输出色彩空间（1.1.191，1.1.194 限 Android，1.1.198 归入 hdrGlWorkaround）：
  /// 恒 BT709（SDR）。
  ///
  /// Android + hdrGlWorkaround 开关（默认开启）时调用：Flutter 纹理恒
  /// SDR（fvp 文档），mdk 默认 auto 会为 HDR10 内容建 bt2020_pq 表面，
  /// 导致 SDR 面板发白 + HDR10 管线簇状丢帧 + 纹理黑屏（mdk-sdk#361，
  /// fvp#379 workaround）。关闭仅用于 A/B 实验。
  ///
  /// iOS：不调用 setColorSpace。Metal 上与 videoout.hdr=0 冲突导致
  /// HDR10 黑屏（1.1.194 修复），iOS 依赖 videoout.hdr=0 全局选项。
  @visibleForTesting
  static AdapterColorSpace outputColorSpace() => AdapterColorSpace.bt709;

  /// 非 DV HDR 的内容/设备状态 → 输出色彩空间（纯函数，便于单测映射）。
  ///
  /// 把播放器运行期状态（HDR/HLG/DV 判定、载体）映射到 [HdrOutputPolicy]；
  /// [dv] 为真时返回 null（DV 由 [dvOutputColorSpace] 单独处理）。
  /// 该策略默认生效，不受 `hdrGlWorkaround` 实验开关门控。
  @visibleForTesting
  static AdapterColorSpace? resolveHdrOutputColorSpace({
    required TargetPlatform platform,
    required bool dv,
    required bool hdr,
    required bool hlg,
    required bool surfaceView,
    required DisplayCapabilities display,
  }) {
    if (dv) return null;
    return HdrOutputPolicy.resolve(
      platform: platform,
      isHdr10: hdr && !hlg,
      isHlg: hlg,
      display: display,
      channelCanCarryHdr: surfaceView,
    );
  }

  /// Dolby Vision 内容输出色彩空间策略（纯函数，便于单测）。
  ///
  /// DV 内容恒走 mdk（LLDV：mdk 解析并处理 DV 元数据，输出 SDR/HDR10）。
  /// 输出目标由 `Player.set(ColorSpace)` 决定；全局 `videoout.hdr` 恒 0
  /// （=0 时不覆盖 set），故本策略生效。
  ///
  /// - Android：显示支持 HDR10 → HDR10 直通（BT2100_PQ）；否则 SDR
  ///   tone map（BT709，避免 SDR 面板发白）。
  /// - Windows：写死 d3d11 HDR10（BT2100_PQ）。
  /// - iOS：返回 null（不调用 setColorSpace）——Metal 上与 videoout.hdr=0
  ///   冲突会 HDR10 黑屏（1.1.194），依赖全局选项恒 SDR tone map。
  /// - web / 其余：SDR（BT709）。
  static AdapterColorSpace? dvOutputColorSpace({
    required TargetPlatform platform,
    required DisplayCapabilities display,
  }) {
    switch (platform) {
      case TargetPlatform.android:
        return display.supportsHdr10
            ? AdapterColorSpace.bt2100PQ
            : AdapterColorSpace.bt709;
      case TargetPlatform.windows:
        return AdapterColorSpace.bt2100PQ;
      case TargetPlatform.iOS:
        return null;
      default:
        return AdapterColorSpace.bt709;
    }
  }

  /// 顶栏解码模式按钮是否显示：TV 模式隐藏（解码模式仅走设置页）。
  @visibleForTesting
  static bool showDecodeButton({required bool tvMode}) => !tvMode;

  /// 位图字幕编码判定（Emby codec 名，大小写不敏感）：PGS/VobSub/DVB。
  /// 位图字幕无法像文本字幕那样被重设样式/缩放/位置。
  @visibleForTesting
  static bool isBitmapSubtitleCodec(String codec) {
    final c = codec.toLowerCase();
    return c.contains('pgs') ||
        c.contains('hdmv') ||
        c.contains('dvdsub') ||
        c.contains('dvbsub') ||
        c.contains('vobsub') ||
        c.contains('dvd_sub') ||
        c.contains('dvb_sub');
  }

  /// 弹幕列表 → Erika 原生弹幕 JSON：`[{time, content, type, color}]`。
  @visibleForTesting
  static String danmakuJsonFor(List<DanmakuComment> comments) {
    return jsonEncode(<Map<String, Object>>[
      for (final c in comments)
        {
          'time': c.time,
          'content': c.text,
          'type': switch (c.mode) {
            DanmakuMode.scroll => 'scroll',
            DanmakuMode.top => 'top',
            DanmakuMode.bottom => 'bottom',
          },
          'color': '#${(c.color & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        }
    ]);
  }

  /// 「显示调节」入口位置：TV 在底部控制条（弹幕与字幕之间），非 TV 在顶栏。
  @visibleForTesting
  static bool showTopSubtitleStyleButton({required bool tvMode}) => !tvMode;

  @visibleForTesting
  static bool showBottomDisplayAdjustButton({required bool tvMode}) => tvMode;

  /// 播完自动下一集的位置兜底判定（纯函数，供测试）。
  ///
  /// 仅服务「引擎不上报 end 位」的档位（media_kit/Erika）：mdk 有
  /// `MediaStatus.end`，走兜底会把「拖进度条到结尾窗口」误判为播完
  /// 直接切集（v1.1.238 回归）。
  /// - [engineEmitsEnd]：引擎自身会上报 end（mdk）→ 兜底恒不触发；
  /// - [seekCooldownActive]：seek 完成后冷却期内不触发；
  /// - 正在播放且位置进入结尾窗口（距时长 ≤500ms）才触发。
  @visibleForTesting
  static bool shouldAutoNextEpisode({
    required int positionMs,
    required int durationMs,
    required bool playing,
    bool engineEmitsEnd = false,
    bool seekCooldownActive = false,
  }) {
    if (engineEmitsEnd || seekCooldownActive) return false;
    return playing && durationMs > 0 && positionMs >= durationMs - 500;
  }

  /// 跳过片尾后是否直接进入下一集（纯函数，供测试）。
  @visibleForTesting
  static bool shouldAdvanceAfterOutroSkip({
    required bool hasEpisodeList,
    required int currentEpisodeIndex,
    required int episodeCount,
  }) =>
      hasEpisodeList &&
      currentEpisodeIndex >= 0 &&
      currentEpisodeIndex + 1 < episodeCount;

  /// 跳过片尾并退出时是否提示“所有剧集播放完毕”（剧集最后一集才提示）。
  @visibleForTesting
  static bool shouldShowSeriesFinishedAfterOutroSkip({
    required bool isSeries,
    required bool hasNextEpisode,
  }) =>
      isSeries && !hasNextEpisode;

  /// 前 3 秒不可设置片头（按视频播放位置判定）。
  @visibleForTesting
  static bool canSetIntroAt(int positionMs) =>
      positionMs >= SegmentSkipController.introGateMs;

  /// 片头提示是否仍需等待本次起播满 3 秒。
  @visibleForTesting
  static bool shouldDelayIntroPrompt({
    required int playbackElapsedMs,
    required bool insideIntro,
  }) =>
      insideIntro && playbackElapsedMs < SegmentSkipController.introGateMs;

  /// 切集/换源窗口内禁止片段提示：旧位置 + 新片段会误判片尾。
  @visibleForTesting
  static bool canEvaluateSkipPrompt({
    required bool suppressed,
    required bool switchingMedia,
  }) =>
      !suppressed && !switchingMedia;

  /// 是否自动执行片头/片尾跳过（总开关与自动开关同时开启且可控制播放）。
  @visibleForTesting
  static bool shouldAutoSkipSegment({
    required bool canControlPlayback,
    required bool skipEnabled,
    required bool autoSkipEnabled,
  }) =>
      canControlPlayback && skipEnabled && autoSkipEnabled;

  /// 已有手动标记时，手机长按也需要进入更新/清除确认。
  @visibleForTesting
  static bool hasExistingSegmentMark(int? existingMs) => existingMs != null;

  /// 引擎 end 事件是否可信（纯函数，供测试）：mdk keyframe seek 窗口
  /// 会误报 `MediaStatus.end` 位（v1.1.239 修复不彻底，拖进度条仍切
  /// 集）——真实播完时 position≈duration，误报时位置仍远离结尾。
  /// - [seekInProgress]：seek/拖动进行中 position 未回读，忽略；
  /// - 时长未就绪无法校验 → 视作误报；
  /// - 距结尾 >1s 的 end → 引擎误报。
  @visibleForTesting
  static bool shouldHandleEngineEnd({
    required bool seekInProgress,
    required int positionMs,
    required int durationMs,
  }) {
    if (seekInProgress) return false;
    if (durationMs <= 0) return false;
    return positionMs >= durationMs - 1000;
  }

  /// 观众收到携带 playUrl 的同步消息时是否应触发起播（纯函数，供测试）。
  ///
  /// 房主 `join` 处理会先发带 playUrl 的 roomInfo、再发同 URL 的 syncPlay，
  /// 流为空时 `requestRoomInfo` 响应还会再带一次；这些消息都会命中观众侧
  /// 起播入口。同一 URL 若被并发/连续触发，会各自执行
  /// `media=`/`prepare()`/`_ensureTexture()`（HDR 时还双重重建引擎）→ 竞态
  /// 黑屏。因此：
  /// - 空 URL → 否；
  /// - 与当前播放 URL 相同 → 否（去重）；
  /// - 与在飞 URL 相同 → 否（并发单飞）；
  /// - 否则 → 是。
  @visibleForTesting
  static bool shouldStartAudiencePlay({
    required String playUrl,
    required String currentPlayUrl,
    required String? inFlightPlayUrl,
  }) {
    if (playUrl.isEmpty) return false;
    if (playUrl == currentPlayUrl) return false;
    if (inFlightPlayUrl != null && playUrl == inFlightPlayUrl) return false;
    return true;
  }

  /// 加载转圈遮罩可见性（纯函数，供测试）：切源中恒显；播放器已就绪
  /// 但 `duration==0` 仅在**首次起播前**强制显（首帧未出）。加载期间强制
  /// 显示顶栏与底栏控件——黑屏转圈时用户仍可点返回退出。
  /// v1.2.24：首播后重载偶发「loaded 但 duration 暂报 0」，旧条件会把
  /// 控件再强留屏上且叠着刚重建的视频层，用户感知为「控件自己冒出来且
  /// 显示不完整」；重载期间本来就有 switchingMedia 兜底。
  @visibleForTesting
  static bool isLoadingMaskVisible({
    required bool switchingMedia,
    required int durationMs,
    required bool playerReady,
    required bool startedOnce,
  }) =>
      switchingMedia || (durationMs == 0 && playerReady && !startedOnce);

  /// 首帧加载转圈是否显示（纯函数，供测试）。
  ///
  /// 仅限「播放器就绪、时长未知、尚未起播、位置为 0、且未处于播放态」。
  /// 转码/直播流可能永远报不出 duration；一旦位置推进或进入 playing，
  /// 必须隐藏转圈，否则视频在播但遮罩永久停留。
  @visibleForTesting
  static bool shouldShowInitialLoadingSpinner({
    required int durationMs,
    required int positionMs,
    required bool playerReady,
    required bool startedOnce,
    required bool playing,
  }) =>
      playerReady &&
      durationMs == 0 &&
      !startedOnce &&
      positionMs == 0 &&
      !playing;

  /// 有效时长：播放器优先，拿不到时回退 Emby 元数据。
  @visibleForTesting
  static int effectiveDurationMs({
    required int playerMs,
    required int fallbackMs,
  }) {
    if (playerMs > 0) return playerMs;
    return fallbackMs > 0 ? fallbackMs : 0;
  }

  /// 手机版判定：移动端平台且非 TV（控制条布局分支）。
  @visibleForTesting
  static bool isMobilePhoneControls({
    required bool tvMode,
    required bool mobilePlatform,
  }) =>
      mobilePlatform && !tvMode;

  /// 顶栏倍速键是否显示：仅手机本地单人（房间模式由房主节奏接管，
  /// 转屏键见 [showRotateButton] 复用同一手机判定）。
  @visibleForTesting
  static bool showTopSpeedButton({
    required bool tvMode,
    required bool mobilePlatform,
    required bool isRoom,
  }) =>
      !isRoom &&
      isMobilePhoneControls(tvMode: tvMode, mobilePlatform: mobilePlatform);

  /// 底栏倍速键是否显示：TV / 桌面本地单人（手机已移至顶栏）。
  @visibleForTesting
  static bool showBottomSpeedButton({
    required bool tvMode,
    required bool mobilePlatform,
    required bool isRoom,
  }) =>
      !isRoom &&
      !isMobilePhoneControls(tvMode: tvMode, mobilePlatform: mobilePlatform);

  /// 长按视频区临时倍速倍率（手机版）。
  static const double speedBoostMultiplier = 2.0;

  /// 左缘锁按钮是否显示：TV 模式无锁（遥控器语义下不提供锁定）。
  @visibleForTesting
  static bool showLockButton({required bool tvMode}) => !tvMode;

  /// 顶栏左上角影视信息：电影 = 片名；剧集 = `剧名 – S01E02`
  ///（剧名为空回退片名，直链播放等无元数据场景由调用方判空不渲染）。
  @visibleForTesting
  static String formatMediaTitle(EpisodeInfo info) {
    if (info.isMovie || info.seriesName.isEmpty) return info.name;
    return '${info.seriesName} – ${episodeCode(info.season, info.number)}';
  }

  /// 按下标取影视信息标题：[index] 为负（初进未选定集）或越界时返回
  /// 空串。详情页开房 host 初进时 `_episodes` 已有数据而
  /// `_currentEpisodeIndex` 仍为 -1，直取 `_episodes[index]` 会
  /// RangeError 令整页白屏（v1.1.97 顶栏影视信息引入的回归）。
  @visibleForTesting
  static String mediaTitleAt(List<EpisodeInfo> episodes, int index) {
    if (index < 0 || index >= episodes.length) return '';
    return formatMediaTitle(episodes[index]);
  }

  /// S01E02 风格集编号（电影 season/number 为 0，不走此格式）。
  @visibleForTesting
  static String episodeCode(int season, int number) =>
      'S${season.toString().padLeft(2, '0')}'
      'E${number.toString().padLeft(2, '0')}';
}

enum _OrientationMode { portraitUp, landscapeLeft, landscapeRight }

class _ResourceItem {
  final String id;
  final String name;
  final int season;
  final int number;
  final String poster;
  final String seriesName;

  const _ResourceItem({
    required this.id,
    required this.name,
    this.season = 0,
    this.number = 0,
    this.poster = '',
    this.seriesName = '',
  });

  bool get isMovie => season == 0 && number == 0 && seriesName.isEmpty;
}

class _SeasonGroup {
  final int seasonNumber;
  final List<_ResourceItem> episodes;
  bool collapsed = true;

  _SeasonGroup({
    required this.seasonNumber,
    required this.episodes,
  });
}

class _ResourceGroup {
  final String name;
  final bool isMovie;
  final List<_SeasonGroup> seasons;
  bool collapsed = true;

  _ResourceGroup({
    required this.name,
    required this.isMovie,
    required this.seasons,
  });

  int get totalCount => seasons.fold(0, (sum, s) => sum + s.episodes.length);
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  static const _videoFitModes = [
    BoxFit.contain,
    BoxFit.cover,
    BoxFit.fill,
    BoxFit.none,
  ];
  static const _videoFitIcons = [
    Icons.fit_screen,
    Icons.fullscreen,
    Icons.zoom_out_map,
    Icons.aspect_ratio,
  ];
  static const _videoFitLabels = ['自适应', '裁剪', '铺满', '原始'];

  /// 播放器适配器（Phase 4 引擎热切换后重新赋值，非 final）。
  late PlayerAdapter _player;

  /// 当前播放引擎（内容路由重建后更新；起播恒 mdk）。
  PlayerEngine _currentEngine = PlayerEngine.mdk;

  Timer? _heartbeatTimer;
  Timer? _rateRestoreTimer;
  StreamSubscription? _rtmSubscription;
  bool _isHost = false;
  bool _showControls = true;

  /// 屏幕锁定状态机（会话态）：锁后屏蔽手势/热键，左缘锁钮两形态切换
  final PlayerLockController _lockController = PlayerLockController();

  /// 真实下载速度计（整机下行流量，播放时 ≈ 视频流速度）；
  /// 平台不支持/读取失败时保持 null，顶栏不渲染网速。
  NetworkSpeedMeter? _speedMeter;
  double? _networkSpeedBps;

  /// 热键层焦点（PlayerHotkey 外部节点）：控制条隐藏后焦点回落于此，
  /// 遥控器方向键恢复 seek/唤出控制条语义
  final FocusNode _hotkeyFocusNode = FocusNode(debugLabel: 'PlayerHotkey');

  /// 控制条进度滑杆焦点：TV 唤出控制条后焦点落位点
  final FocusNode _controlsFocusNode =
      FocusNode(debugLabel: 'PlayerSeekSlider');

  /// 播放/暂停按钮焦点：滑杆按落键的定向落点（按钮行左侧组无法被
  /// 几何方向导航直达，由 PlayerHotkey 拦截滑杆 Down 转投此节点）
  final FocusNode _playPauseFocusNode =
      FocusNode(debugLabel: 'PlayerPlayPause');

  /// 下一集按钮焦点：左组尾——Right 跨满宽 Spacer 时由 PlayerHotkey
  /// 定向到字幕（几何导航会跳回上方滑杆）
  final FocusNode _nextEpisodeFocusNode =
      FocusNode(debugLabel: 'PlayerNextEpisode');

  /// 字幕按钮焦点：右组头——Left 跨回左组的定向落点
  final FocusNode _subtitleButtonFocusNode =
      FocusNode(debugLabel: 'PlayerSubtitleButton');

  /// 音轨/倍速按钮焦点（TV 打开选择器面板后原路返回的落点）
  final FocusNode _audioButtonFocusNode =
      FocusNode(debugLabel: 'PlayerAudioButton');
  final FocusNode _speedButtonFocusNode =
      FocusNode(debugLabel: 'PlayerSpeedButton');

  /// 选集按钮焦点（TV 打开选集面板后原路返回的落点）
  final FocusNode _episodeButtonFocusNode =
      FocusNode(debugLabel: 'PlayerEpisodeButton');

  /// 多版本切换按钮焦点（TV 打开版本面板后原路返回的落点）
  final FocusNode _versionButtonFocusNode =
      FocusNode(debugLabel: 'PlayerVersionButton');

  /// 选择器面板落焦节点：打开面板后显式 requestFocus 精确落到选中行
  /// （autofocus 在同级按钮已持焦时不抢占——这是"焦点进不了面板"的根因）
  final FocusNode _selectorFirstFocusNode =
      FocusNode(debugLabel: 'SelectorPanelFirstRow');

  /// 选择器面板根锚点（skipTraversal 不参与遍历）：控制条自动隐藏判定
  /// "焦点在菜单面板内"的依据（面板在 Stack 平级、不在控制条子树内）
  final FocusNode _selectorPanelRootFocusNode =
      FocusNode(debugLabel: 'SelectorPanelRoot');

  /// 打开选择器面板的按钮节点：面板关闭后焦点原路返回该按钮
  FocusNode? _selectorOpenerNode;

  /// 控制条根焦点（skipTraversal 不参与遍历）：自动隐藏判定"焦点是否
  /// 停留在控制条内"的依据
  final FocusNode _controlsRootFocusNode =
      FocusNode(debugLabel: 'PlayerControlsRoot');

  /// 顶栏根焦点（skipTraversal）：自动隐藏焦点判定根之一
  final FocusNode _topBarRootFocusNode =
      FocusNode(debugLabel: 'PlayerTopBarRoot');
  Duration _position = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);

  /// Emby 元数据时长（播放器不报 duration 时的兜底）。
  int _fallbackDurationMs = 0;
  String? _myUserId;
  String? _rtmChannel;
  String? _rtmAppId;
  String? _hostUserId;

  double _volume = kPlayerDefaultVolume * 100;
  double _brightness = kPlayerDefaultBrightness;
  final ValueNotifier<double> _brightnessNotifier =
      ValueNotifier(kPlayerDefaultBrightness);
  final ValueNotifier<double> _volumeNotifier =
      ValueNotifier(kPlayerDefaultVolume * 100);
  bool _syncPaused = false;
  bool _isSyncing = false;
  int _playRequestId = 0;

  /// 观众播放单飞标记：当前正在执行的 [_playFromUrl] 的 URL。
  ///
  /// 观众可能对**同一 URL**并发收到多条触发消息（房主 join 路径先 roomInfo
  /// 后 syncPlay、流为空时 requestRoomInfo 响应等）。两条 `_playFromUrl`
  /// 并发会各自执行 `media=`/`prepare()`/`_ensureTexture()`，并在 HDR 场景
  /// 双重重建引擎 → EGL/纹理竞态黑屏。同 URL 在飞时丢弃后续调用。
  String? _inFlightPlayUrl;

  /// 跨设备时钟偏移估计（观众用）：消除房主/观众系统时钟差导致的
  /// 恒定进度偏差。房主不用（其 ts 即本机时钟）。
  final ClockOffsetEstimator _clockOffset = ClockOffsetEstimator();
  Timer? _clockPingTimer;

  /// 换源音量渐变（切集爆音修复）。
  final AudioFader _fader = AudioFader();

  /// 换源音量守卫（切集静音回归修复）：渐出前记录目标音量、
  /// 换源窗口内拒绝 player.volume 回写污染 UI 音量。
  final SwitchVolumeGuard _volGuard = SwitchVolumeGuard();

  /// 纹理通道实际创建时的档位（'texture'/'tunnel'）；
  /// 设置切换后据此决定是否重建纹理。
  String? _textureOutputApplied;

  /// 显示器真实输出分辨率（物理像素，Android 原生探测，播中不变）。
  /// 渲染尺寸夹紧目标：TV/盒子 UI 层常只报 1080p，须用 Display 真实
  /// 尺寸才能保住 4K 输出模式下的全分辨率扫描输出。
  /// null = 未取得/非 Android（回退 MediaQuery×dpr）。
  Size? _displayPhysical;

  /// 实际生效的渲染目标尺寸取证（调试面板：原生尺寸 → 夹紧后尺寸；
  /// 未夹紧时两段相同）。夹紧仅在 SurfaceView 档 + HDR + 开关开时生效。
  String get _renderTargetDesc {
    final native = _videoNativeSize;
    if (native == null) return '-';
    final n = '${native.width.toInt()}x${native.height.toInt()}';
    // 夹紧仅 SurfaceView 档生效（纹理档恒原生）
    if (!_usesSurfaceView) return n;
    final clamped = _clampedRenderSize(native);
    if (clamped == null) return n;
    return '$n → ${clamped.width.toInt()}x${clamped.height.toInt()}';
  }

  /// 截帧取证结果（面板展示，null = 未截过）。
  String? _snapshotInfo;
  DateTime? _lastSnapshotAt;

  /// EGL 故障已处理（自动切 tunnel 自愈只做一次，防重入/防环）。
  bool _eglFaultHandled = false;

  /// 进入本次播放会话前 EGL 故障检测器是否已置位（v1.2.14 会话级守卫）：
  /// 持久标记设备上首条 mdk 日志（任意级别）即命中已置位检测器，旧逻辑
  /// 误触发一次自愈重建（迟到 surface + 上下文重建竞态 → renderer 永久
  /// 丢帧、起播偶发定格）。[_loadStream]/[_playFromUrl] 开播时快照。
  bool _eglFaultAtSessionStart = false;
  DateTime? _lastSeekTime;
  bool _showPanel = true;
  String _currentPlayUrl = '';
  String _currentToken = '';

  /// 控件自动隐藏：长时间无真实输入（焦点变更/按键/指针）后收起全部控件
  late final ControlsAutoHideController _autoHide;
  Timer? _positionTimer;
  Timer? _diagnosticTimer;
  Timer? _reportTimer;
  bool _isDraggingSlider = false;

  /// seek 进行中守卫（v1.1.222）：MDK 关键帧 seek 窗口内原生 position
  /// 可能报 0/负值，_positionTimer 若此时写入会把进度条拉回开头，
  /// 后续遥控器 ±N 秒又以被污染的 _position 为基准 → 真实 seek(0)。
  /// seek 前置真，await adapter seek Future 完成（2s 超时兜底）后清零
  /// 并回读 position 同步一次 UI。
  bool _isSeekingPlayback = false;

  // ---- 跳过片头/片尾（手动标记 + Emby 章节）----
  late final ManualSegmentRepository _manualSegments;
  final SegmentSkipController _skipController = SegmentSkipController();
  final FocusNode _skipPromptFocusNode =
      FocusNode(debugLabel: 'SegmentSkipPrompt');
  final FocusNode _segmentMarkFirstFocusNode =
      FocusNode(debugLabel: 'SegmentMarkFirst');
  final FocusScopeNode _segmentMarkScopeNode = FocusScopeNode(
    debugLabel: 'SegmentMarkScope',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop,
  );
  final Stopwatch _skipPromptPlaybackWatch = Stopwatch();

  List<MediaSegment> _skipSegments = const [];
  MediaSegment? _skipPromptSegment;
  Timer? _skipPromptTimer;
  MediaItem? _segmentMediaItem;
  ManualSegmentRecord? _manualSegmentRecord;
  String _segmentServerId = '';
  int _segmentDurationMs = 0;
  int _skipLoadSeq = 0;
  bool _skipPromptSuppressed = false;
  bool _showSegmentMarkPanel = false;

  // ---- Emby 播放会话上报（续播/自动已观看）----
  /// 本次播放会话 id（切集重生成）。
  String _playSessionId = const Uuid().v4();
  EmbyService? _reportService;
  String? _reportItemId;
  String? _reportServerConfigId;
  String? _reportMediaSourceId;
  bool _reportStarted = false;

  /// 进度上报触发续播栏刷新的节流时刻（≤1 次/2s）。
  DateTime? _lastProgressBump;

  // ---- 播放中线路故障转移（v1.1.242）----
  /// 当前播放会话连续上报失败计数（成功清零）。
  int _reportFailCount = 0;

  /// 本次播放是否已自动切过线路（单次播放只切 1 次，换集重置）。
  bool _failoverAttempted = false;

  /// failover 进行中守卫（防并发重入）。
  bool _failoverInFlight = false;

  // ---- 视频流同线路自动重载（v1.1.245）----
  /// 流中断（invalid/取流失败/缓冲超时）时的退避重载调度。
  final StreamReloadScheduler _streamReload = StreamReloadScheduler();

  /// 缓冲 watchdog：持续 buffering/stalled 超过阈值触发同线路重载。
  /// 仅当期间播放位置停滞（无推进）才判为真卡死；position 持续推进说明
  /// 只是高码率/弱网下的降速播放，不得重载（否则反复清缓冲加剧卡顿）。
  Timer? _stallWatchdogTimer;

  /// watchdog 武装时的播放位置（ms）；用于采样时判断是否仍有推进。
  int? _stallWatchdogStartPosMs;

  bool _showSubtitleMenu = false;
  bool _showAudioMenu = false;
  bool _showKernelMenu = false;
  bool _switchingKernel = false;
  bool _showDecodeModeMenu = false;
  bool _showSpeedMenu = false;
  bool _showSubtitleStyleMenu = false;

  /// 选集面板（右侧剧集卡片浮层；仅单人模式多集时可开）。
  bool _showEpisodeMenu = false;

  /// 多版本切换面板（右侧浮层；仅非房间模式多版本时可开）。
  bool _showVersionMenu = false;

  /// 当前条目的全部可用版本（Emby MediaSources；加载流时刷新）。
  List<MediaSource> _currentMediaSources = const [];

  /// 当前生效版本 id（加载流时刷新；切换版本后更新）。
  String? _activeMediaSourceId;

  // ── 弹幕（v1.1.134，自定义 danmu_api 源）──

  /// 弹幕开关：initState 取设置默认；API 地址未配置时强制关
  ///（配置后下次起播自动生效，点击时给出配置提示）。
  bool _danmakuOn = false;

  /// match/comment 进行中（防重入；进行中再点开关只翻转显示态）。
  bool _danmakuLoading = false;

  /// 加载代次：换集时自增，丢弃仍在飞行的上一集结果。
  int _danmakuLoadSeq = 0;

  /// 已加载弹幕（关弹幕后保留，重开免请求；换集清空重载）。
  List<DanmakuComment> _danmakuComments = const [];

  /// 当前已加载弹幕对应的集索引（-1 = 无）；避免起播/恢复时重复加载。
  int _danmakuLoadedIndex = -1;

  /// 静默重试计时器与已重试次数（瞬时失败时保留上次弹幕、后台再试）。
  Timer? _danmakuRetryTimer;
  int _danmakuRetryAttempt = 0;

  /// 静默重试退避序列（秒）：首延迟缩短到 2s，其后 5s/10s（共 3 次）。
  static const List<int> _danmakuRetryDelaysSec = [2, 5, 10];

  /// 底栏「弹幕」开关焦点（TV 跨组导航锚点：右组头）。
  final FocusNode _danmakuButtonFocusNode = FocusNode();

  /// 当前弹幕客户端（API 地址变化时重建）。
  DandanplayClient? _danmakuClient;
  String? _danmakuClientKey;

  /// 字幕样式（大小/位置/延迟）：本播放会话内存态；按内容 id 落盘
  ///（[SubtitleStyleStore]），退出后重进同内容恢复。
  double _subtitleScale = SubtitleStylePanel.defaultScale;
  int _subtitleMarginY = SubtitleStylePanel.defaultMarginY;
  int _subtitleDelayMs = SubtitleStylePanel.defaultDelayMs;

  /// 当前激活的本地字幕文件路径（`_activeSubtitleIndex == -1` 时有效，
  /// 延迟偏移重载的原素材）。
  String? _activeLocalSubtitlePath;

  /// 延迟变更 → 重载偏移字幕的去抖（拖动连续触发只重载最后一次）。
  Timer? _subtitleDelayReloadTimer;

  /// 样式变更 → 落盘的去抖。
  Timer? _subtitleStyleSaveTimer;

  /// 样式属性写入原生播放器的去抖（~100ms）：滑杆连续拖动只写最后一次，
  /// 降低高频同步 FFI 与引擎重建窗口叠加导致的原生崩溃风险。
  Timer? _subtitleStyleApplyTimer;

  final SubtitleStyleStore _subtitleStyleStore = SubtitleStyleStore();

  /// 顶栏「字幕样式」按钮焦点（面板打开来源，关闭时归还）。
  final FocusNode _subtitleStyleButtonFocusNode =
      FocusNode(debugLabel: 'subtitleStyleButton');

  /// 顶栏「播放内核」胶囊焦点。
  final FocusNode _kernelButtonFocusNode =
      FocusNode(debugLabel: 'playerKernelButton');

  /// 当前播放倍速（单人模式；初始取设置持久值，换集/重载后恢复）。
  double _speed = 1.0;

  /// 手机版长按临时 2× 倍速：按住生效、松手恢复 [_speed]（不落盘）。
  bool _speedBoostActive = false;

  // 手势控制
  bool _showGestureOverlay = false;
  String _gestureHintText = '';
  Timer? _gestureHintTimer;
  IconData? _gestureOverlayIcon;
  bool _isLeftSide = false;
  final ValueNotifier<bool> _showBrightnessBarNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showVolumeBarNotifier = ValueNotifier(false);
  Timer? _gestureBarTimer;

  // fvp: 轨道信息通过 Emby API 获取，不需要 media_kit 的 SubtitleTrack/AudioTrack
  StreamSubscription? _tracksSubscription;

  /// mdk 播放状态/媒体状态/运行时事件监听（dispose 与引擎重建时取消）。
  StreamSubscription? _stateSub;
  StreamSubscription? _statusSub;
  // onEvent 曾为匿名订阅（从不取消）：每次引擎重建都会在旧播放器的
  // _eventCb 上多挂一个永久监听 → 订阅/闭包泄漏，且使上游 hasListener
  // 恒真。改为存字段并随重建/dispose 取消（v1.2.6）。
  StreamSubscription? _eventSub;
  bool _subtitleAutoSelected = false;

  List<MediaStream> _embySubtitleStreams = [];
  List<MediaStream> _embyAudioStreams = [];
  MediaStream? _embyVideoStream; // 视频流信息（用于 DV 检测）
  int? _embyDefaultAudioIndex;
  int? _activeSubtitleIndex;
  bool _useServerSubtitleBurnIn = false;
  _OrientationMode _orientationMode = _OrientationMode.portraitUp;
  BoxFit _videoFit = BoxFit.contain;
  Size? _videoNativeSize;
  String? _lastMediaKitFitKey;

  /// 黑帧取证用纹理尺寸文本：textureSize 未 resolve 时显示 '-'。
  String get _textureSizeText => _videoNativeSize == null
      ? '-'
      : '${_videoNativeSize!.width.toInt()}x${_videoNativeSize!.height.toInt()}';

  // 窗口全屏（桌面）
  bool _isWindowFullscreen = false;
  final WindowFullscreenService _windowFullscreenService =
      WindowFullscreenService();

  // 传感器
  StreamSubscription? _accelSub;

  Map<String, dynamic>? _roomData;

  // 房间解散检测
  bool _hasReceivedRoomInfo = false;
  Timer? _roomInfoTimeout;

  // 观众侧流为空时的退避重试（修「菜单全空」）：流晚到时主动再要 roomInfo
  Timer? _streamRequestTimer;
  int _streamRequestAttempts = 0;

  // 播报板 + 在线用户
  final List<String> _broadcastMessages = [];
  final ValueNotifier<int> _broadcastVersion = ValueNotifier(0);
  int _onlineUserCount = 0;
  StreamSubscription? _presenceSubscription;
  final ScrollController _broadcastScrollController = ScrollController();
  String? _audienceName;

  // 剧集资源列表
  List<EpisodeInfo> _episodes = [];
  String _seriesName = '';
  int _currentEpisodeIndex = -1;
  bool _isSwitchingMedia = false;

  /// 本集「播完」是否已处理（自动下一集/完播提示只触发一次）。
  /// mdk end 事件与位置兜底可能同时命中，靠此门去重；换集重置。
  bool _endHandled = false;

  /// 最近一次 seek 完成时刻：冷却期内忽略位置兜底的自动下一集
  /// （防 seek 后 position 短暂停在结尾窗口被误判播完）。
  DateTime? _lastSeekCompletedAt;

  /// 黑屏加载转圈遮罩是否在显示（切集遮罩 / 首帧进度为 0 的转圈）。
  /// 加载期间强制显示顶栏与底栏控件（否则黑屏无返回入口）。
  bool get _isLoadingMaskVisible => PlayerScreen.isLoadingMaskVisible(
        switchingMedia: _isSwitchingMedia,
        durationMs: _duration.inMilliseconds,
        playerReady: _isPlayerReady,
        startedOnce: _hasStartedPlayback,
      );

  /// 视频尺寸同步重试（见 _syncVideoNativeSize）：计数防风暴、
  /// pending 防多入口并发调度重复链
  int _videoSizeRetry = 0;
  bool _videoSizeRetryPending = false;

  /// SurfaceView platform view 世代：**必要重建**（分辨率/档位/tunnel
  /// 变化）时由 [_remountSurfaceView] 在 attach 阶段 +1。同分辨率切集
  /// 恒不递增——view/surface/EGL 上下文全程复用（v1.1.82 根修：
  /// 切集拆建 view 让 mdk renderer 在新上下文上永久丢帧，画面定格
  /// 首帧、音频进度正常，himi_logs_5 实证）。
  int _videoSurfaceEpoch = 0;

  /// SurfaceView 两阶段重建的 detach 门：true 时 build 卸下 platform
  /// view（触发 surfaceDestroyed/nativeSetSurface 解绑），settle 后由
  /// [_remountSurfaceView] attach 复位。
  bool _surfaceDetached = false;

  /// 渲染风暴计数（log handler 喂入；见 [RenderStormDetector]）。
  final RenderStormDetector _renderStorm = RenderStormDetector();

  /// 新 surface 是否已完成 surfaceCreated 绑定（nativeSetSurface 绑定）。
  /// 起播前等待此标志，避免 state=playing 抢在绑定之前。
  bool _surfaceViewCreated = false;
  bool _hasEpisodeList = false;
  bool _isPlayerReady = false;

  /// 页面已进入销毁流程：异步加载续体据此停止一切原生调用。
  bool _disposed = false;

  /// 延迟释放只允许启动一次（防止引擎切换/异常路径重复释放）。
  bool _playerDisposeStarted = false;

  /// 是否已成功起播过（首次获知非零时长置位）：`duration==0` 强制显
  /// 控件的加载兜底只在首次起播前生效，避免播放中重载的 duration 抖动
  /// 把控件反复强留屏上（见 [isLoadingMaskVisible]）。
  bool _hasStartedPlayback = false;

  /// 观众侧最近一次应用的远端流签名（字幕/音轨条数+默认音轨）。
  /// 用于流晚到时触发重新选轨（修「观众菜单全空」）。
  String _remoteStreamSignature = '';

  /// 引擎热切换/内容路由重建进行中：暂时卸载旧视频视图（渲染黑底），
  /// 避免旧 widget 在旧引擎释放后仍访问其原生对象（崩溃/错误）。
  bool _switchingEngine = false;

  /// 应用已进入后台/熄屏（收到 paused/inactive/hidden）：回前台（resumed）
  /// 时据此触发一次视频输出恢复（纹理重建 / SurfaceView 补帧）。
  bool _appBackgrounded = false;

  /// 熄屏/切后台前是否处于播放态；恢复后据此还原播放状态。
  bool _wasPlayingBeforeBackground = false;

  /// 视频输出恢复进行中（防 resumed 重入叠加）。
  bool _recoveringVideo = false;

  /// 回前台重载后恢复到暂停态：管线刚重建，直接 `state=playing` 可能不接回；
  /// 置位后下一次「暂停→播放」先对当前进度 seek 一次再起播（见 [_togglePlayPause]）。
  bool _pendingResumeSeek = false;

  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier(false);

  // 分组缓存（由 _rebuildGroups 从扁平数组计算）
  List<_ResourceGroup> _resourceGroups = [];

  void _rebuildGroups() {
    final groups = <String, _ResourceGroup>{};

    for (int i = 0; i < _episodes.length; i++) {
      final ep = _episodes[i];

      final groupName = ep.isMovie ? '电影' : ep.seriesName;

      final item = _ResourceItem(
        id: ep.id,
        name: ep.name,
        season: ep.season,
        number: ep.number,
        poster: ep.poster,
        seriesName: ep.seriesName,
      );

      groups.putIfAbsent(
          groupName,
          () => _ResourceGroup(
                name: groupName,
                isMovie: ep.isMovie,
                seasons: [],
              ));

      final group = groups[groupName]!;
      _SeasonGroup seasonGroup = group.seasons.cast<_SeasonGroup?>().firstWhere(
            (s) => s!.seasonNumber == ep.season,
            orElse: () => _SeasonGroup(seasonNumber: ep.season, episodes: []),
          )!;

      if (!group.seasons.any((s) => s.seasonNumber == ep.season)) {
        group.seasons.add(seasonGroup);
        group.seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      }

      seasonGroup.episodes.add(item);
    }

    _resourceGroups = groups.values.toList();
    // 电影组排在前面
    _resourceGroups.sort((a, b) {
      if (a.isMovie && !b.isMovie) return -1;
      if (!a.isMovie && b.isMovie) return 1;
      return a.name.compareTo(b.name);
    });

    // 恢复折叠状态：当前播放的集所在组自动展开
    if (_currentEpisodeIndex >= 0 && _currentEpisodeIndex < _episodes.length) {
      final curEp = _episodes[_currentEpisodeIndex];
      final curGroupName = curEp.isMovie ? '电影' : curEp.seriesName;
      for (final g in _resourceGroups) {
        if (g.name == curGroupName) {
          g.collapsed = false;
          for (final s in g.seasons) {
            if (s.seasonNumber == curEp.season) {
              s.collapsed = false;
            }
          }
        }
      }
    }
  }

  bool _roomSyncInitializing = false;

  // 同步调试面板
  String _syncRtmChannel = '-';
  String _syncRtmStatus = '未连接';
  String _syncMetadataTestResult = '-'; // 自检结果
  String _voStatus = '-'; // 视频输出驱动
  String _videoResolution = '-'; // 视频分辨率
  String _hdrType = 'SDR'; // HDR 类型标签
  /// 内容是否为 HDR（闩锁，一旦判定不回退）：用于自动路由
  /// （mdk#361：直写 surface 在 HDR 上会 wedge/卡顿 → 降级为同载体 GL）。
  /// 由 Emby 元数据 + 运行期 mediaInfo **色彩信息**共同判定（bt2100
  /// PQ/HLG 或 doviProfile>0）；像素格式不再参与（10-bit SDR ≠ HDR）。
  bool _hdrContent = false;

  /// 内容是否为 HLG（闩锁）：Emby 元数据或运行期 mediaInfo `bt2100HLG`。
  /// 用于非 DV HDR 输出策略（见 [HdrOutputPolicy]）：HLG 屏上输出
  /// `bt2100hlg` 而不是被 tone map 成 SDR。
  bool _hlgContent = false;

  /// 内容是否为 Dolby Vision（**仅** Emby 标）：用于引擎路由（恒 mdk）
  /// 与输出色彩策略（见 [dvOutputColorSpace]）。
  bool get _isDvContent => _embyVideoStream?.isDolbyVision == true;

  /// 内容是否 HLG（Emby 元数据 或 运行期闩锁）。
  bool get _isHlgContent => _hlgContent || _embyVideoStream?.isHLG == true;

  /// 内容是否 10-bit 以上（闩锁）：**不是 HDR 判定**——bt709 的
  /// p010/yuv420p10le 同样命中。用于输出决策：设备 GL 10-bit 纹理
  /// 实测不可用时强制直写（绕开 GL 渲染 10-bit 帧）。
  bool _is10BitContent = false;
  DvProbeResult _dvProbe = DvProbeResult.unknown; // 设备 DV 解码能力（仅展示）
  bool _isSwitchingDecode = false; // 并发保护：防止快速切换模式导致状态错乱
  List<String> _syncEvents = [];

  // 播放诊断数据
  int _bufferedMs = 0;
  int _mediaBitrate = 0;
  double _videoFps = 0;
  int _audioSampleRate = 0;
  int _audioChannels = 0;
  String _mediaFormat = '';
  // 新增诊断字段
  String _playbackState = 'stopped';
  String _mediaStatusStr = '-';
  int _positionMs = 0;
  int _durationMs = 0;
  String _videoCodecName = '-';
  int _videoBitrate = 0;
  String _pixelFormat = '-';
  int _doviProfile = 0;
  String _audioCodecName = '-';
  int _audioBitrate = 0;
  String _stereoDownmix = '关';
  String _actualVideoDecoders = '-';

  /// mdk `video.decoder` 属性原值，字段名与内容不符，如实单列展示
  String _mdkRawDecoder = '-';
  String _audioBackend = '-';

  /// 上次写入 mdk 的 `audio.avfilter` 值，用于去重（诊断每秒回调）。
  String? _lastAudioFilter;

  /// 判定 [_lastAudioFilter] 时用的音轨编码，进诊断面板取证。
  String _lastAudioFilterCodec = '';

  /// 滤镜取证文案：面板/导出用，区分「滤镜没写入」vs「写入了仍无声」。
  String get _audioFilterText {
    final f = _lastAudioFilter;
    if (f == null) return '(未写入)';
    final codec = _lastAudioFilterCodec.isEmpty ? '未知' : _lastAudioFilterCodec;
    return '${f.isEmpty ? '(无)' : f} | codec=$codec';
  }

  /// 实际生效的解码器（框架名由 mdk 事件给出，底层 codec 名由平台预选推断）
  DecoderReport _decoderReport = DecoderReport.empty;
  String _codecProbeKey = '';
  // 卡顿诊断
  final PlaybackDiagnostics _diag = PlaybackDiagnostics();
  String _diagSummary = '';
  String _diagTimeline = '';
  String _diagStalls = '';
  String _diagNotes = '';
  int _bufProgress = -1; // 缓冲进度 0-100，-1 表示未知

  /// mdk 状态行解析出的视频缓存秒数。深度诊断未开或未收到状态行时为 null。
  double? _latestCacheSeconds;

  /// 产物身份自证（版本 + DV 通道是否进包），读取一次后缓存。
  String _buildSummary = '产物身份: 读取中...';
  bool _buildIdentityLoaded = false;

  Timer? _sampleTimer;
  bool _deepLogActive = false;

  /// 普通态（深度诊断关）的「EGL 检测」handler 是否已挂。播放器的
  /// mdk 日志入口必须常驻：只靠 main 全局 handler 时 3004 会被它
  /// 消费（`feed` 一次性语义），本页面的自愈与落盘永不触发。
  bool _resumeLogHandlerInstalled = false;
  DateTime _deepWindowStart = DateTime.now();
  int _deepPerSecond = 0;

  /// 深度诊断安全阀：仅对"保留行"计数。过滤掉 `buffering progress`
  /// 刷屏后，状态行约 4 行/秒，不会再被误触发。
  static const int _deepLinesPerSecondLimit = 50;
  static const int _deepStatusLineCap = 240; // 状态行保留 240 条 ≈ 60s
  static const int _deepNoteLineCap = 120;

  /// mdk 状态行（fps / cache），按时间顺序保留最近若干条
  final List<String> _deepLogLines = <String>[];

  /// 解码器选择 / 丢帧 / 错误等关键行
  final List<String> _deepNoteLines = <String>[];
  final GlobalKey _qrKey = GlobalKey();
  bool _shareDialogOpen = false;

  // 调试面板拖拽位置
  double _debugPanelX = 20;
  double _debugPanelY = 100;
  final ValueNotifier<int> _syncEventsVersion = ValueNotifier(0);

  void _logSyncEvent(String event) {
    LogService().log('Sync', event);
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _syncEvents.add('[$time] $event');
    if (_syncEvents.length > 15) _syncEvents.removeAt(0);
    _syncEventsVersion.value++;
  }

  Future<void> _queryHwdecStatus() async {
    try {
      if (mounted) {
        setState(() {
          _voStatus = 'fvp/libmdk';
        });
      }
    } catch (_) {}
  }

  /// 定时采集播放诊断数据（缓冲区、码率、帧率等）
  void _queryDiagnostics() {
    if (!mounted) return;
    try {
      // 深度诊断开关可在播放中实时切换
      _syncDeepDiagnostics();
      final mi = _player.mediaInfo;
      final buffered = _player.buffered();
      final pos = _player.position;
      final st = _player.state;
      final ms = _player.mediaStatus;

      // 播放状态
      String playState = st == AdapterPlaybackState.playing
          ? 'playing'
          : st == AdapterPlaybackState.paused
              ? 'paused'
              : 'stopped';
      String mediaSt = _describeMediaStatus(ms);

      // 视频信息
      int vBitrate = 0;
      double fps = 0;
      String vCodec = '-';
      String pixFmt = '-';
      int dovi = 0;
      int vWidth = 0;
      int vHeight = 0;
      if (mi.video.isNotEmpty) {
        final vc = mi.video[0];
        vCodec = vc.codec;
        vBitrate = vc.bitRate;
        fps = 0;
        pixFmt = vc.formatName;
        dovi = vc.doviProfile;
        vWidth = vc.width;
        vHeight = vc.height;
      }

      // 音频信息
      int aBitrate = 0;
      int sampleRate = 0;
      int channels = 0;
      String aCodec = '-';
      if (mi.audio.isNotEmpty) {
        final ac = mi.audio[0];
        aCodec = ac.codec;
        aBitrate = ac.bitRate;
        sampleRate = ac.sampleRate;
        channels = ac.channels;
      }

      // mdk 上报的 video.decoder 不可靠（实测返回 `scale=3840x1608`
      // 这类与解码器无关的值）。配置项以 videoDecoders 为准；mdk 原值
      // 单独一行如实展示，它与实际解码器的偏差本身就是有用的证据。
      final mdkRawDecoder = _player.getProperty('video.decoder') ?? '-';
      final actualDecoders = _player.videoDecoders.join(',');

      // 降混设置
      final dm = ref.read(settingsProvider).stereoDownmix ? '开' : '关';
      final ab = AppSettings.effectiveAudioRenderer(
          ref.read(settingsProvider).audioRenderer);

      // 平台预选解码器：签名未变则跳过，避免每个采样周期跨 MethodChannel
      _maybeProbeCodecs(vCodec, vWidth, vHeight, dovi, aCodec);

      // 音轨编码随 mediaInfo 就绪后才可判定，每采样周期兜底刷新一次
      // （内部按值去重，值不变不写 mdk 属性）
      _applyAudioFilterPolicy();

      setState(() {
        _bufferedMs = buffered;
        _mediaBitrate = vBitrate > 0 ? (vBitrate / 1000).round() : 0;
        _videoFps = fps;
        _audioSampleRate = sampleRate;
        _audioChannels = channels;
        _mediaFormat = mi.format ?? '';
        _playbackState = playState;
        _mediaStatusStr = mediaSt;
        _positionMs = pos;
        _durationMs = mi.duration;
        _videoCodecName = vCodec;
        _videoResolution =
            vWidth > 0 && vHeight > 0 ? '${vWidth}x$vHeight' : '-';
        _videoBitrate = vBitrate > 0 ? (vBitrate / 1000).round() : 0;
        _pixelFormat = pixFmt;
        _doviProfile = dovi;
        _audioCodecName = aCodec;
        _audioBitrate = aBitrate > 0 ? (aBitrate / 1000).round() : 0;
        _stereoDownmix = dm;
        _actualVideoDecoders = actualDecoders;
        _mdkRawDecoder = mdkRawDecoder;
        _audioBackend = ab;
        _diagSummary = _diag.summary();
      });
    } catch (e) {
      LogService().log('Diag', '诊断采集失败: $e');
    }
  }

  /// 按格式签名去重地探测平台预选解码器。
  ///
  /// mdk 事件只给出解码框架名（`AMediaCodec` / `FFmpeg`），无法区分
  /// 框架内落到硬件还是软件实现；这里补上底层 codec 名。
  ///
  /// 结果是「Android 会为该格式选谁」的**推断**，展示时须标注置信度。
  /// 签名不变直接返回，防止每个采样周期都跨一次 MethodChannel。
  Future<void> _maybeProbeCodecs(
    String videoCodec,
    int width,
    int height,
    int doviProfile,
    String audioCodec,
  ) async {
    final key = '$videoCodec|${width}x$height|$doviProfile|$audioCodec';
    if (key == _codecProbeKey) return;
    _codecProbeKey = key;

    final vMime = CodecMimeMap.video(videoCodec);
    final aMime = CodecMimeMap.audio(audioCodec);
    final isDv = doviProfile > 0;

    // mime 映射未命中时保持空值，由 verdict 判为未知，绝不猜。
    final video = vMime == null
        ? null
        : await DolbyVisionService.selectDecoder(
            mime: vMime,
            width: width > 0 ? width : null,
            height: height > 0 ? height : null,
            dolbyVision: isDv,
          );
    final audio = aMime == null
        ? null
        : await DolbyVisionService.selectDecoder(mime: aMime);

    if (!mounted) return;
    setState(() {
      var report = _decoderReport;
      if (video != null) {
        report = report.withVideo(
          report.video.copyWith(
            codec: video.picked ?? '',
            codecIsSoftware: video.isSoftware,
          ),
        );
      }
      if (audio != null) {
        report = report.withAudio(
          report.audio.copyWith(
            codec: audio.picked ?? '',
            codecIsSoftware: audio.isSoftware,
          ),
        );
      }
      _decoderReport = report;
    });
  }

  /// 记录 mdk 上报的实际解码框架。
  ///
  /// mdk 每尝试一个解码器就发一次事件（含失败回退），因此取**最新值**，
  /// 回退过程在面板上直接可见。error 字段一并保留，成功为 0。
  /// 成功事件同样落盘：Windows 硬解是否生效、iOS 视频走没走硬解，
  /// 全靠这行取证（此前仅 error 落盘，正常路径无日志可查）。
  void _noteDecoderEvent(AdapterMediaEvent event) {
    final isVideo = event.category == 'decoder.video';
    LogService()
        .log('Diag', '${event.category}: ${event.detail} code ${event.error}');
    final current = isVideo ? _decoderReport.video : _decoderReport.audio;
    final next = current.copyWith(framework: event.detail, error: event.error);
    setState(() {
      _decoderReport = isVideo
          ? _decoderReport.withVideo(next)
          : _decoderReport.withAudio(next);
    });
  }

  /// 记录 mdk 日志里**实际创建**的底层解码器名。
  ///
  /// 这是唯一可信的真值来源：DV 能力探测返回的 `picked` 只是预测，
  /// 真机上视频预测 `c2.dolby.decoder.hevc` 而实际创建 `c2.qti.hevc.decoder`，
  /// 混进「实际解码」会直接把诊断带偏。该行属 FINE 级日志，
  /// 仅在深度诊断开启时输出，故 [DecoderTrack.actualCodec] 可能长期为 null。
  void _noteActualCodec(String line) {
    final v = MdkLogParser.parseSelectedCodec(line, video: true);
    final a = MdkLogParser.parseSelectedCodec(line, video: false);
    if (v == null && a == null) return;
    setState(() {
      var r = _decoderReport;
      if (v != null) r = r.withVideo(r.video.copyWith(actualCodec: v));
      if (a != null) r = r.withAudio(r.audio.copyWith(actualCodec: a));
      _decoderReport = r;
    });
  }

  /// 把 mdk MediaStatus 位标志映射为可读文本。
  /// buffered / stalled / buffering 均反映卡顿，必须显式呈现而非落到 '-'。
  static String _describeMediaStatus(AdapterMediaStatus ms) {
    if (ms.test(AdapterMediaStatus.invalid)) return 'invalid';
    if (ms.test(AdapterMediaStatus.end)) return 'end';
    if (ms.test(AdapterMediaStatus.buffering)) return 'buffering';
    if (ms.test(AdapterMediaStatus.stalled)) return 'stalled';
    if (ms.test(AdapterMediaStatus.seeking)) return 'seeking';
    if (ms.test(AdapterMediaStatus.buffered)) return 'buffered';
    if (ms.test(AdapterMediaStatus.loaded)) return 'loaded';
    if (ms.test(AdapterMediaStatus.loading)) return 'loading';
    if (ms.test(AdapterMediaStatus.unloaded)) return 'unloaded';
    if (ms.test(AdapterMediaStatus.prepared)) return 'prepared';
    return '-';
  }

  /// 250ms 轻量采样：只取 3 个廉价取值写入时间线，不触发 setState。
  /// 目的是捕捉亚秒级缓冲波动，1 秒的重查询捕捉不到。
  void _samplePlayback() {
    if (!mounted) return;
    try {
      final ms = _player.mediaStatus;
      final st = _player.state;
      // 兜底：状态位未翻转导致卡顿计时悬挂时强制结算
      _diag.reapStaleStall();
      // 播放稳定兜底复位（v1.1.245）：无 pending/inFlight 且状态健康时
      // 复位重试预算（网络自愈 / 瞬断恢复场景，避免旧预算误耗尽）。
      if (!_streamReload.hasPending &&
          !_streamReload.inFlight &&
          st == AdapterPlaybackState.playing &&
          !ms.test(AdapterMediaStatus.invalid) &&
          !ms.test(AdapterMediaStatus.buffering) &&
          !ms.test(AdapterMediaStatus.stalled)) {
        _streamReload.reset();
      }
      // 缓冲 watchdog 进度感知：武装期间 position 持续推进说明是「慢但在播」
      // （高码率 4K + 弱网下降速播放），并非真卡死 → 取消 watchdog 不重载。
      final stallStartPos = _stallWatchdogStartPosMs;
      if (_stallWatchdogTimer != null && stallStartPos != null) {
        if (StreamStallGuard.progressed(stallStartPos, _player.position)) {
          LogService().log('Diag', '缓冲期间进度仍推进 → 取消缓冲超时watchdog');
          _diag.onStallEnd();
          _cancelStallWatchdog();
        }
      }
      _diag.addSample(
        pos: _player.position,
        buffered: _player.buffered(),
        state: st == AdapterPlaybackState.playing
            ? 'playing'
            : st == AdapterPlaybackState.paused
                ? 'paused'
                : 'stopped',
        status: _describeMediaStatus(ms),
        reloading: ms.test(AdapterMediaStatus.unloaded) ||
            ms.test(AdapterMediaStatus.loading),
        cacheSeconds: _latestCacheSeconds,
        bufProgress: _bufProgress,
      );
    } catch (e) {
      LogService().log('Diag', '采样失败: $e');
    }
  }

  /// 读取产物身份并缓存。
  ///
  /// 通道能应答即证明原生插件随包发布；应答不了就说明这份日志来自缺插件的
  /// 构建（CI 曾整体覆盖 android/ 造成过这种情况），报告首行直接写明，
  /// 免得把打包事故误当成代码 bug 反复排查。
  Future<void> _loadBuildIdentity() async {
    if (_buildIdentityLoaded) return;
    _buildIdentityLoaded = true;
    final identity = await DolbyVisionService.buildIdentity();
    if (!mounted) return;
    setState(() => _buildSummary = '产物身份: ${identity.summary}');
    if (identity.channelMissing) {
      LogService().log('Diag', 'DV 通道未注册，产物缺原生插件: ${identity.error}');
    }
  }

  /// 探测设备 DV 解码能力，仅用于日志与调试面板展示。
  ///
  /// 不再据此覆盖解码器列表：解码模式（auto/hw/sw）由 [DecodeModeService]
  /// 统一决定。旧实现在能力探测假阴性时强制 `['FFmpeg']`，会把具备硬解
  /// 的设备（骁龙平台 DV 常声明在 video/hevc 而非 video/dolby-vision）
  /// 错误降级为软件解码，4K 10bit 下解码不及导致卡顿。
  /// mdk 的 AMediaCodec 本身在失败时会自动回退到 FFmpeg。
  Future<void> _probeDvCapability() async {
    if (!Platform.isAndroid) return;
    if (_embyVideoStream == null || !_embyVideoStream!.isDolbyVision) {
      _dvProbe = DvProbeResult.unknown;
      return;
    }
    final probe = await DolbyVisionService.probe();
    if (!mounted) return;
    setState(() => _dvProbe = probe);
    LogService().log('Player', 'DV 能力: ${probe.summary}');
    LogService().log(
      'Player',
      'DV 解码器配置: ${_player.videoDecoders.join(',')}',
    );
  }

  /// 检测杜比视界内容并更新 HDR 标签
  Future<void> _detectDolbyVision() async {
    try {
      bool isDV = false;
      String hdrType = 'SDR';

      if (_embyVideoStream != null) {
        isDV = _embyVideoStream!.isDolbyVision;
        hdrType = _embyVideoStream!.hdrLabel;
        LogService()
            .log('Player', 'DV 检测(Emby API): isDV=$isDV, hdrType=$hdrType');
      }

      if (!mounted) return;

      setState(() {
        _hdrType = hdrType;
      });
      // Emby 元数据就绪 → 复核 HDR（自动路由依据）
      _refreshHdrContent();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _manualSegments =
        widget.manualSegmentRepository ?? LocalManualSegmentStore();
    WidgetsBinding.instance.addObserver(this);
    // Android：预取显示器真实输出分辨率（渲染尺寸夹紧目标）。TV/盒子
    // 的 UI 层常只报 1080p，须用 Display 真实尺寸才能保住 4K 输出模式
    // 下的全分辨率扫描输出；失败/null 由 _clampDisplayPhysical 回退
    // MediaQuery×dpr。异步不阻塞起播，通常在首帧前就绪。
    if (Platform.isAndroid) {
      unawaited(const DisplayInfoService().realDisplaySize().then((s) {
        if (mounted && s != null) setState(() => _displayPhysical = s);
      }));
    }
    // 锁状态机变化 → 重建顶栏锁图标 / 解锁浮钮
    _lockController.addListener(_onLockStateChanged);
    // 自动隐藏：焦点变更（落在控件根内）顺延 5 秒；焦点静置不顺延
    _autoHide = ControlsAutoHideController(
      after: PlayerScreen.controlsAutoHideAfter,
      onHide: _onControlsIdleHide,
      focusRoots: () => [
        _controlsRootFocusNode,
        _selectorPanelRootFocusNode,
        _topBarRootFocusNode,
        _segmentMarkScopeNode,
      ],
      enabled: () => _showControls && mounted,
    );
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
    // 播放内核：每次进入播放器都从平台默认引擎开始；顶栏切换仅当前
    // 播放会话生效，不写回默认设置。剧集切集沿用当前内核。
    _currentEngine = PlayerEngineFactory.defaultEngine();
    _player = PlayerEngineFactory.create(
      _currentEngine,
      erikaOutputMode: ErikaOutputMode.auto,
    );
    // 强制输出 SDR（BT709）：仅 Android + hdrGlWorkaround 开关（默认开启）。
    // Flutter 纹理恒 SDR（fvp 文档），mdk 默认 auto 会为 HDR10 内容建
    // bt2020_pq 表面，导致 Android SDR 面板发白 + HDR10 管线簇状丢帧
    // + 纹理黑屏（mdk-sdk#361，fvp#379 workaround：HDR 内容回退 GL +
    // tone map 到 SDR）。iOS Metal 上 setColorSpace(bt709) 与
    // videoout.hdr=0 冲突导致 HDR10 黑屏（1.1.194 修复）。
    // 1.1.198 归入 hdrGlWorkaround 单开关，关闭仅用于 A/B 实验。
    // 本次修正：Dolby Vision 内容按平台策略输出（Android HDR10/SDR、
    // Windows 恒 HDR、iOS 不设置）；其余维持 hdrGlWorkaround 的 SDR 强制。
    _applyOutputColorSpace();
    // 字幕属性配置（大小/位置随会话状态，initState 后异步恢复落盘值）
    if (_currentEngine != PlayerEngine.mpv) {
      _player.setProperty('subtitle', '1');
      _player.setProperty('subtitle.font.size', '40');
      _player.setProperty('subtitle.border', '2');
      _player.setProperty('subtitle.shadow', '1');
    }
    _applySubtitleStyle();
    // 音频滤镜（立体声降混 / iOS TrueHD 无声规避）统一走策略，
    // 初始化时音轨编码未知，先按开关落一次；选轨/诊断再按编码刷新
    final settings = ref.read(settingsProvider);
    _speed = settings.playbackSpeed;
    ref.listenManual<bool>(
      settingsProvider.select((s) => s.skipIntroOutroEnabled),
      (previous, enabled) {
        if (!mounted || previous == enabled) return;
        if (!enabled) {
          _skipLoadSeq++;
          _skipPromptTimer?.cancel();
          _skipPromptTimer = null;
          _skipPromptPlaybackWatch.reset();
          _skipController.reset();
          setState(() {
            _skipPromptSegment = null;
            _skipSegments = const [];
            _manualSegmentRecord = null;
            _showSegmentMarkPanel = false;
          });
        } else {
          final item = _segmentMediaItem;
          if (item != null) unawaited(_loadSkipSegments(item));
        }
      },
    );
    // 弹幕：默认开关跟随设置；未配置 API 地址时强制关（静默，
    // 不在起播时打扰；用户点击弹幕钮才提示去配置）。
    // 实际拉取推迟到当前集就绪后（见 _loadEpisodeStream 完成 / 起播），
    // 避免集索引未就绪时误报「无法获取当前影片名称」。
    _danmakuOn = settings.danmakuDefaultOn &&
        DandanplayClient.normalizeBaseUrl(settings.danmakuApiUrl) != null;
    _applyAudioFilterPolicy();
    // 音频后端：OpenSL 时钟精度更高，可改善高复杂度音频的播放流畅度。
    // AAudio/OpenSL/AudioTrack 为 Android 专属（其余平台自动归一为 auto），
    // 生效值落盘取证：iOS 曾因默认 AudioTrack 无效导致无声
    final renderer = AppSettings.effectiveAudioRenderer(settings.audioRenderer);
    LogService()
        .log('Player', '音频后端: 设置=${settings.audioRenderer} 生效=$renderer');
    if (renderer != 'auto') {
      _player.audioBackends = [renderer];
    }
    // 音量默认 80%
    _player.volume = kPlayerDefaultVolume;
    _startSpeedMeter();
    _myUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';

    _isHost = widget.isHost;
    _audienceName = widget.audienceName.isNotEmpty
        ? widget.audienceName
        : (_isHost ? '房主' : '观众');

    // 主持人：优先从 Riverpod provider 读取 episodes/movie；观众通过 RTM 接收
    if (_isHost) {
      final pendingEpisodes = ref.read(pendingRoomEpisodesProvider);
      final pendingMovie = ref.read(pendingRoomMovieProvider);
      if (pendingEpisodes != null && pendingEpisodes.isNotEmpty) {
        // 电视剧：从完整数据提取所有字段
        _episodes = pendingEpisodes
            .map((e) => EpisodeInfo(
                  id: e['id'] as String? ?? '',
                  name: e['name'] as String? ?? '',
                  season: e['season'] as int? ?? 0,
                  number: e['number'] as int? ?? 0,
                  poster: e['poster'] as String? ?? '',
                  seriesName: e['seriesName'] as String? ?? '',
                  // 建房选集面板逐集单选的版本（缺省 = 服务端默认）
                  mediaSourceId: e['mediaSourceId'] as String?,
                  serverId: (e['serverId'] as String?) ?? widget.serverId,
                ))
            .toList();
        _seriesName = pendingEpisodes.first['seriesName'] as String? ?? '';
        _hasEpisodeList = true;
        _clearPendingAfterFrame(() {
          ref.read(pendingRoomEpisodesProvider.notifier).state = null;
        });
      } else if (pendingMovie != null) {
        _episodes = [
          EpisodeInfo(
            id: pendingMovie['id'] as String? ?? '',
            name: pendingMovie['name'] as String? ?? '电影',
            poster: pendingMovie['poster'] as String? ?? '',
            mediaSourceId: widget.mediaSourceId,
            serverId: (pendingMovie['serverId'] as String?) ?? widget.serverId,
          )
        ];
        _seriesName = '';
        _hasEpisodeList = true;
        _clearPendingAfterFrame(() {
          ref.read(pendingRoomMovieProvider.notifier).state = null;
        });
      }
      _rebuildGroups();
    }

    _setupPlayerListeners();
    // 初进控制条设置：全模式启动 5 秒自动隐藏；TV 模式补落焦 seek 滑杆
    //（热键层 autofocus 抢走焦点且无焦点环，翻转分支初进不经过）
    PlayerScreen.scheduleInitialControlsSetup(
      tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
      controlsVisible: _showControls,
      seekNode: _controlsFocusNode,
      onStartHideTimer: _resetHideTimer,
      // 控件未就绪时逐帧重试；页面销毁/控件被隐藏即放弃
      shouldRetry: () => mounted && _showControls,
    );
    // 防御：EGL 故障若在播放器创建前已被全局检测（bootstrap handler），
    // 进入页面即触发自愈，不必等下一次日志喂入。
    if (eglFaultDetector.fault) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onEglFault());
    }
    _startOrientationSensor();

    if (widget.roomCode != null) {
      _setupRoomSync();
    }

    _switchToLandscape(_OrientationMode.landscapeLeft);

    // 先完成硬件解码设置，再启动播放，避免竞态
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 并行执行：亮度初始化 + 播放器属性初始化
      await Future.wait([
        Future(() async {
          if (!mounted) return;
          // Windows 亮度默认跟随系统（仅读取展示，不覆盖系统亮度）；
          // 其他平台维持原行为：强制设为默认 0.8
          if (PlayerPlatform.brightnessFollowsSystem) {
            double current = kPlayerDefaultBrightness;
            try {
              current = await ScreenBrightness().application;
            } catch (_) {}
            _brightness = PlayerPlatform.initialBrightness(
              current: current,
              followSystem: true,
              fallback: kPlayerDefaultBrightness,
            );
            _brightnessNotifier.value = _brightness;
          } else {
            _brightness = kPlayerDefaultBrightness;
            _brightnessNotifier.value = kPlayerDefaultBrightness;
            try {
              await ScreenBrightness()
                  .setApplicationScreenBrightness(kPlayerDefaultBrightness);
            } catch (_) {}
          }
        }),
        _initPlayerProperties(),
      ]);
      if (!mounted) return;
      if (_isHost &&
          _hasEpisodeList &&
          _episodes.isNotEmpty &&
          widget.roomCode == null) {
        final targetIndex = _episodes.indexWhere((e) => e.id == widget.itemId);
        try {
          await _loadEpisodeStream(targetIndex >= 0 ? targetIndex : 0,
              startMs: widget.startMs);
        } catch (_) {
          LogService()
              .log('Player', '_loadEpisodeStream 异常，强制设置 _isPlayerReady');
          if (mounted) {
            setState(() {
              _isPlayerReady = true;
            });
          }
        }
      }
    });
  }

  /// 帧末清理 pending provider（房主进入播放器时消费的暂存数据）。
  ///
  /// initState 处于构建期，debug 下 Riverpod 会断言「构建期不得修改
  /// provider」并中断 initState（播放器空白）；release 无守卫，但统一
  /// 延到帧末时序一致、风险更低。页面已卸载则跳过。
  void _clearPendingAfterFrame(void Function() clear) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      clear();
    });
  }

  /// 迁移期取底层内核 adapter（factory 默认返回 PlayerCoreBridge）。
  T? _wrappedAdapter<T extends PlayerAdapter>() {
    final p = _player;
    if (p is PlayerCoreBridge) return p.wrappedAs<T>();
    return p is T ? p : null;
  }

  Future<void> _initPlayerProperties() async {
    if (!mounted) return;
    final settings = ref.read(settingsProvider);

    // 配置解码器
    // 锁屏保持
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // media_kit 引擎：应用 hwdec/tone-mapping/cache-size 设置
    // mdk 专属属性（avformat.* / demux.* / avcodec.* / videoDecoders 等）
    // 对 mpv 无效，media_kit 档跳过
    if (_player is MediaKitSettingsApplier) {
      await (_player as MediaKitSettingsApplier).applyMediaKitSettings(
        hwdec: settings.mkHwdec,
        toneMapping: settings.mkToneMapping,
        cacheSizeMb: settings.mkCacheSize,
      );
      return;
    }

    // Erika 引擎：无 mdk 属性可写，直接返回（Erika 设置经其 adapter/构造生效）
    if (_player is ErikaPlayerProvider) {
      return;
    }

    if (_player is MpvPlayerAdapter) {
      final decoders = DecodeModeService.resolveDecoders(settings.decodeMode);
      _player.videoDecoders = decoders;
      LogService()
          .log('Player', 'MPV 解码配置: ${settings.decodeMode} → $decoders');
      return;
    }

    // 音频硬解接线（1.1.186）：Android 不接线时 mdk 音频默认直接
    // FFmpeg 软解（真机日志确证），EAC3 软解音频钟抖动会让视频按
    // avsync 成簇判迟到丢帧；auto/hw 档优先 AMediaCodec，FFmpeg 兜底。
    final decoders = DecodeModeService.resolveDecoders(settings.decodeMode);
    _player.videoDecoders = decoders;
    final audioDecoders =
        DecodeModeService.resolveAudioDecoders(settings.decodeMode);
    _player.audioDecoders = audioDecoders;
    // 落盘配置值取证：Windows「硬解没生效」类问题先核对配置与
    // decoder.video 事件（实际生效框架）是否一致
    LogService().log('Player',
        '解码配置: ${settings.decodeMode} → video=$decoders audio=$audioDecoders');

    // avformat 起播配置（v1.1.222 lowLatency 等效；v1.2.4 去 nobuffer）：
    // +fastseek 加速 seek，不再叠加 +nobuffer（其丢首个关键帧包会让起播
    // 瞬间卡顿，全平台 MDK 复现）；analyzeduration 100ms（原 500ms）保留
    // 起播加速。probesize 保持 1MB（fvp lowLatency 不动 probesize）。
    _player.setProperty('avformat.probesize', '1048576'); // 1MB
    MdkPlayerAdapter.lowLatencyProperties.forEach(_player.setProperty);

    // mdk 缓冲/包缓存（网络流抗抖动，v1.2.29 起改由设置控制，下次起播生效）：
    // - buffer（setBufferRange）：min = 队列排空后需再攒够的时长（越大越
    //   不易"一顿一顿"、起播越慢）；max = 缓冲上限（越大越扛网络抖动，
    //   官方称不影响延迟，代价是内存；0 = 无限）。默认 3000/10000（v1.2.64
    //   起；旧版曾硬编码 min=300）。归一 max>=min 见 AppSettings.
    //   normalizeBufferMax。
    // - demux.buffer.ranges：demuxer 段缓存区间数（默认 8，0 = 关闭），
    //   网络流"只下一次"、加速后退 seek（纯内存 LRU）。依据 fvp #98 /
    //   mdk wiki Player-APIs；`demux.buffer.protocols` 默认已含 http,https。
    final mdkBuffer = AppSettings.normalizeBufferMax(
      minMs: settings.mdkBufferMinMs,
      maxMs: settings.mdkBufferMaxMs,
    );
    _player.setBufferRange(min: settings.mdkBufferMinMs, max: mdkBuffer);
    _player.setProperty(
      MdkPlayerAdapter.demuxBufferRangesKey,
      MdkPlayerAdapter.demuxBufferRangesValue(settings.mdkDemuxCacheRanges),
    );

    // FFmpeg 解码线程数：0 = 逻辑核心数 + 1（仅软解回退时生效，硬解忽略）
    _player.setProperty('avcodec.threads', '0');
  }

  /// HDR 内容强制切 MPV 原生 Surface 直出（三端统一）。
  ///
  /// SDR 保持用户当前内核/纹理；只有纹理链路被判定不可用时才由
  /// [MpvOutputPolicy] 在适配器层切直出。
  Future<void> _routeHdrToMpvIfNeeded() async {
    if (_currentEngine == PlayerEngine.mpv || Platform.isIOS) return;
    final hdr = _hdrContent ||
        _embyVideoStream?.isHDR == true ||
        _embyVideoStream?.isDolbyVision == true ||
        _isHlgContent;
    var textureUnavailable = false;
    if (Platform.isAndroid) {
      final profile = ref.read(deviceProfileProvider);
      textureUnavailable = profile.eglBroken(
            eglFaultSeen: eglFaultDetector.fault,
          ) ||
          (_is10BitContent && profile.tenBitGlBroken);
    }
    if ((!hdr && !textureUnavailable) ||
        !PlayerEngineFactory.isSupported(PlayerEngine.mpv)) {
      return;
    }
    if (hdr) _hdrContent = true;
    await _recreateEngineForLoad(PlayerEngine.mpv, ErikaOutputMode.auto);
    if (textureUnavailable && _player is MpvPlayerAdapter) {
      (_player as MpvPlayerAdapter).forceNativeSurface = true;
    }
  }

  void _applyMpvContentHints() {
    if (_currentEngine != PlayerEngine.mpv) return;
    final player = _player;
    if (player is! MpvPlayerAdapter) return;
    final stream = _embyVideoStream;
    player.hdrContent =
        _hdrContent || stream?.isHDR == true || stream?.isDolbyVision == true;
    player.hlgContent = _isHlgContent;
  }

  /// 当前活跃音轨的编码名（小写），取不到返回 ''。
  ///
  /// 优先取 mdk 实测（mediaInfo 活跃轨），回退 Emby 元数据。
  String _currentAudioCodec() {
    try {
      final audio = _player.mediaInfo.audio;
      if (audio.isNotEmpty) {
        final act = _player.activeAudioTracks;
        final idx =
            (act.isNotEmpty && act.first >= 0 && act.first < audio.length)
                ? act.first
                : 0;
        final c = audio[idx].codec;
        if (c.isNotEmpty) return c;
      }
    } catch (_) {}
    final act = _player.activeAudioTracks;
    if (act.isNotEmpty &&
        act.first >= 0 &&
        act.first < _embyAudioStreams.length) {
      return _embyAudioStreams[act.first].codec;
    }
    return '';
  }

  /// 按 [AudioFilterPolicy] 刷新 `audio.avfilter`（音轨切换 / 诊断采样 /
  /// 设置变化时调用；值未变化则跳过，避免每秒重复写属性）。
  ///
  /// iOS 上 TrueHD/MLP 经 FFmpeg 解出的 s32/多声道 PCM 在 AudioQueue
  /// 后端无声（上游 mdk-sdk#364 未修），仅 iOS 需要规避滤镜。
  void _applyAudioFilterPolicy({String? codec}) {
    final settings = ref.read(settingsProvider);
    final effectiveCodec = codec ?? _currentAudioCodec();
    final filter = AudioFilterPolicy.resolve(
      codec: effectiveCodec,
      stereoDownmix: settings.stereoDownmix,
      isIOS: Platform.isIOS,
    );
    if (filter == _lastAudioFilter) return;
    _lastAudioFilter = filter;
    _lastAudioFilterCodec = effectiveCodec;
    if (_currentEngine == PlayerEngine.mpv) {
      _player.setProperty('af', filter);
    } else {
      _player.setProperty('audio.avfilter', filter);
    }
    LogService().log(
      'Player',
      '音频滤镜: ${filter.isEmpty ? "(无)" : filter} '
          '| codec=${effectiveCodec.isEmpty ? "未知" : effectiveCodec} '
          '| 降混=${settings.stereoDownmix ? "开" : "关"} 平台=${Platform.isIOS ? "iOS" : "其他"}',
    );
  }

  Future<void> _loadEpisodeStream(
    int episodeIndex, {
    int startMs = 0,
    bool resetBudget = true,
  }) async {
    if (episodeIndex < 0 || episodeIndex >= _episodes.length) return;

    final ep = _episodes[episodeIndex];
    final itemId = ep.id;
    final epMediaSourceId = ep.mediaSourceId;
    _beginSkipPromptSuppression();

    // 立即标记就绪，显示视频区域（带黑色遮罩），避免卡在 placeholder
    if (mounted) {
      setState(() {
        _isPlayerReady = true;
      });
    }

    // 先设置 _currentEpisodeIndex，这样 publishPlayInfo 能拿到正确的值
    if (!mounted) return;
    setState(() {
      _currentEpisodeIndex = episodeIndex;
      // 新集开播：解除上一集的播完门，允许本集再触发自动下一集
      _endHandled = false;
      // 新集允许一次新的自动故障转移
      _failoverAttempted = false;
      _reportFailCount = 0;
      // 新集复位同线路重载预算（v1.1.245）；同线路重载复用本路径时
      // 不得复位（否则每轮重载清零退避预算 → 无限循环）。
      if (resetBudget) _streamReload.reset();
      _cancelStallWatchdog();
      // 换集：清空上一集的片头片尾状态，详情到达后重新解析
      _skipLoadSeq++;
      _skipPromptTimer?.cancel();
      _skipPromptTimer = null;
      _skipPromptSegment = null;
      _skipSegments = const [];
      _segmentMediaItem = null;
      _manualSegmentRecord = null;
      _segmentDurationMs = 0;
      _duration = Duration.zero;
      _durationNotifier.value = _duration;
      _position = Duration(milliseconds: startMs > 0 ? startMs : 0);
      _positionNotifier.value = _position;
      _lastSeekCompletedAt = null;
      _showSegmentMarkPanel = false;
      _skipPromptPlaybackWatch.reset();
      _skipController.reset();
    });
    // 弹幕与媒体并行：集索引就绪即拉取（不等整流加载完成，缩短出弹幕时间）
    if (mounted && _danmakuOn) unawaited(_loadDanmaku());

    int? fallbackDurationMs;
    try {
      // 来源服务器（集可能来自其他服务器）
      final epServerId = ep.serverId ?? widget.serverId;
      final embyService = ref.read(embyServiceForProvider(epServerId));
      final config = ref.read(embyConfigForProvider(epServerId));

      // 第一步：先获取 Emby 详情（获取 DV 信息，用于解码器选择）
      try {
        final details = (config != null && config.isAuthenticated)
            ? await embyService.getItemDetails(itemId).catchError((e) {
                LogService().log('Player', '获取 Emby 详情失败: $e');
                return null;
              })
            : null;
        if (details != null && mounted) {
          final source = details.mediaSources.firstWhere(
            (s) => s.id == epMediaSourceId,
            orElse: () =>
                details.mediaSources.firstOrNull ??
                MediaSource(id: '', name: ''),
          );
          final detailRunTimeMs =
              details.runTimeTicks != null && details.runTimeTicks! > 0
                  ? details.runTimeTicks! ~/ 10000
                  : 0;
          final sourceRunTimeMs =
              source.runTimeTicks != null && source.runTimeTicks! > 0
                  ? source.runTimeTicks! ~/ 10000
                  : 0;
          if (detailRunTimeMs > 0) {
            fallbackDurationMs = detailRunTimeMs;
          } else if (sourceRunTimeMs > 0) {
            fallbackDurationMs = sourceRunTimeMs;
          }
          final configuredServerId = config?.serverId ?? '';
          _segmentServerId = configuredServerId.isNotEmpty
              ? configuredServerId
              : (epServerId ?? '');
          setState(() {
            _embyAudioStreams = source.audioStreams;
            _embySubtitleStreams = source.subtitleStreams;
            _embyVideoStream = source.videoStream;
            _embyDefaultAudioIndex = source.defaultAudioStreamIndex;
            // 多版本切换数据源：全部版本 + 当前生效版本
            _currentMediaSources = details.mediaSources;
            _activeMediaSourceId = source.id.isEmpty ? null : source.id;
          });
          await _loadSkipSegments(details);
          if (!mounted) return;
          // iOS TrueHD 无声规避：Emby 元数据已知默认音轨编码，load 前
          // 预写滤镜，不必等 mediaInfo 就绪后的诊断回调（首个缓冲段无声）
          _applyAudioFilterPolicy(codec: source.defaultAudioStream?.codec);
          // 房主换集/加载后流信息更新 → 重广播，观众据此刷新字幕/音轨菜单
          unawaited(_broadcastRoomInfo());
        }
      } catch (_) {}

      // 第二步：探测 DV 解码能力（不覆盖解码器配置）
      await _probeDvCapability();
      await _loadBuildIdentity();

      // 换集：清空上一集的卡顿诊断，避免时间线跨集污染
      _diag.reset();
      _decoderReport = DecoderReport.empty;
      _codecProbeKey = '';

      // 第三步：加载流（prepare 会使用已配置好的解码器）
      if (!mounted) return;
      await _loadStream(
          itemId: itemId,
          mediaSourceId: epMediaSourceId,
          serverId: epServerId,
          startMs: startMs,
          fallbackDurationMs: fallbackDurationMs);

      // 详情缺 RunTimeTicks 时，等播放器时长就绪后再补解析片尾区间
      if (mounted &&
          _segmentMediaItem != null &&
          _segmentDurationMs <= 0 &&
          _duration.inMilliseconds > 0) {
        await _loadSkipSegments(_segmentMediaItem!, resetController: false);
      }

      // _loadStream 已在 updateTexture() 后设置播放状态，此处仅同步 UI
      if (mounted) {
        _syncPlayState();
      }
    } catch (e) {
      LogService().log('Player', '_loadEpisodeStream 异常: $e');
    }

    // 无论成功或失败，都标记播放器已就绪，避免卡在 placeholder
    if (mounted) {
      setState(() {
        _isPlayerReady = true;
      });
    }

    if (!mounted) return;
    _rebuildGroups();

    // 不做 setNext 预加载（gapless）：MediaStatus.end → _switchToEpisode
    // 是自动连播的既定路径（v1.0.92 曾因 gapless 导致切集自动播放丢失
    // 而回退），setNext 与之并存会造成双重换源——mdk 先 gapless 过渡、
    // end 处理器又硬切 media，既爆音又重复加载。
  }

  /// 同步视频原生尺寸：**mediaInfo 直读优先**，textureSize 兜底。
  ///
  /// 换序动机（v1.1.82，himi_logs_5 实测）：textureSize 依赖 fvp 的
  /// loaded/decoder.video 事件填 completer，SurfaceView 档切集时可能
  /// 整 3 秒超时才回退 mediaInfo——期间帧已就绪、view 未挂，surface
  /// 迟到是 renderer 定格根因之一。mediaInfo 在 prepare 返回后即可用，
  /// 与 textureSize 同源（均读 mediaInfo.video + par/rotation），即时
  /// resolve 消除固定 3 秒卡顿。mediaInfo 未就绪时才等 textureSize
  /// （3 秒兜底），二者皆空走 1 秒重试链。
  ///
  /// 尺寸变化时：texture/tunnel 档普通 setState；SurfaceView 档且旧
  /// view 在场则走 [_remountSurfaceView] 两阶段重建（同尺寸不拆）。
  Future<void> _syncVideoNativeSize() async {
    final sw = Stopwatch()..start();
    Size? size = _readMediaInfoVideoSize();
    var source = 'mediaInfo';
    if (size == null) {
      try {
        size = await _player.textureSize.timeout(const Duration(seconds: 3));
        source = size != null ? 'textureSize' : 'timeout';
      } catch (_) {
        source = 'timeout';
      }
      if (!mounted || _disposed) return;
      size ??= _readMediaInfoVideoSize();
      if (size != null) source = 'mediaInfo(兜底)';
    }
    if (!mounted || _disposed) return;
    if (size == null) {
      _scheduleVideoSizeRetry();
      LogService().log('Diag',
          '尺寸同步: 未就绪 (${sw.elapsedMilliseconds}ms) → 1s 后重试 #$_videoSizeRetry');
      return;
    }
    _videoSizeRetry = 0;
    final old = _videoNativeSize;
    if (old == size) {
      LogService()
          .log('Diag', '尺寸同步: $source $size 无变化 (${sw.elapsedMilliseconds}ms)');
      return;
    }
    final remount = PlayerScreen.surfaceViewNeedsRemount(
      output: _effectiveVideoOutput(),
      oldSize: old,
      newSize: size,
    );
    LogService().log(
        'Diag',
        '尺寸同步: $source ${old ?? '(首播)'} → $size '
            '(${sw.elapsedMilliseconds}ms) remount=$remount');
    if (remount) {
      await _remountSurfaceView(applySize: size);
      return;
    }
    setState(() {
      _videoNativeSize = size;
    });
    _applyVideoAvfilter(size);
    // 尺寸/媒体信息就绪 → 运行期复核 HDR（自动路由依据）
    _refreshHdrContent();
    _nudgeOverlayRepaint('尺寸变更 ${size.width.toInt()}x${size.height.toInt()}');
  }

  /// SurfaceView 附着/尺寸变更后补一帧空 setState（postFrame）。
  ///
  /// hybrid composition 下平台视图重挂或改尺寸时，Flutter 浮层可能停在
  /// 上一次合成（控制条被视频层盖住半截的"旧帧残留"，Android TV 盒子
  /// 起播卡顿恢复窗口实测）；补一帧让引擎重新合成浮层。日志留证便于
  /// 真机核对时间线。
  void _nudgeOverlayRepaint(String reason) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      LogService().log('Diag', '补帧刷新浮层: $reason');
      setState(() {});
    });
  }

  /// 尺寸未就绪时 1 秒后重试（最多 10 次）：覆盖 decoder.video /
  /// mediaInfo 晚于起播到达的场景；单链防抖避免多入口叠加定时器。
  void _scheduleVideoSizeRetry() {
    if (_videoSizeRetryPending || _videoSizeRetry >= 10) return;
    _videoSizeRetryPending = true;
    _videoSizeRetry++;
    Future.delayed(const Duration(seconds: 1), () {
      _videoSizeRetryPending = false;
      if (mounted) _syncVideoNativeSize();
    });
  }

  /// 等待 SurfaceView 完成 surfaceCreated 绑定（tunnel 档
  /// setDecoders(surface) 在此重开解码器）后再起播。
  /// 非 SurfaceView 档立即返回 true。
  Future<bool> _waitSurfaceCreated() async {
    if (!_usesSurfaceView) return true;
    return PlayerScreen.waitUntil(() => _surfaceViewCreated || !mounted);
  }

  /// SurfaceView 必要重建（分辨率变化 / EGL tunnel 翻转）的两阶段收口：
  ///
  /// 1. **detach**：卸下 platform view → surfaceDestroyed 异步到达 →
  ///    native `updateNativeSurface(nullptr)` 解绑落定；
  /// 2. **settle 300ms**：确保 destroy 不会晚到打掉即将创建的新 view；
  /// 3. **attach**：epoch+1（key 变化）挂新 view，[applySize] 生效后
  ///    等 surfaceCreated 绑定。
  ///
  /// 同分辨率切集**不走这里**——view 全程复用（v1.1.82 根修：迟到
  /// surface + EGL 上下文重建会让 mdk renderer 永久丢帧、画面定格）。
  Future<bool> _remountSurfaceView({Size? applySize}) async {
    if (!mounted || !_usesSurfaceView) return true;
    LogService()
        .log('Diag', 'surface 两阶段重建: detach (epoch=$_videoSurfaceEpoch)');
    setState(() {
      _surfaceDetached = true;
      _surfaceViewCreated = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return false;
    setState(() {
      _videoSurfaceEpoch++;
      _surfaceDetached = false;
      if (applySize != null) {
        _videoNativeSize = applySize;
        _applyVideoAvfilter(applySize);
      }
    });
    LogService().log('Diag',
        'surface 两阶段重建: attach (epoch=$_videoSurfaceEpoch, size=$applySize)');
    _nudgeOverlayRepaint('surface attach (epoch=$_videoSurfaceEpoch)');
    final ok = await _waitSurfaceCreated();
    if (ok)
      _nudgeOverlayRepaint('surfaceCreated 后 (epoch=$_videoSurfaceEpoch)');
    return ok;
  }

  /// mediaInfo 直读视频尺寸（textureSize 超时后的回退源）。
  /// 取最宽流，[resolveVideoSize] 统一 par/rotation 规则；无效 → null。
  Size? _readMediaInfoVideoSize() {
    try {
      final videos = _player.mediaInfo.video;
      if (videos.isEmpty) return null;
      var v = videos.first;
      for (final i in videos) {
        if (i.width > v.width) v = i;
      }
      return PlayerScreen.resolveVideoSize(
        width: v.width,
        height: v.height,
        par: v.par,
        rotation: v.rotation,
      );
    } catch (_) {
      return null;
    }
  }

  /// 上次写入 mdk 的 `video.avfilter` 值，用于去重（尺寸同步可多次触发）。
  String? _lastVideoFilter;

  /// 非标尺寸规范化滤镜（v1.1.70 实验）：任一维非 8 对齐时在解码后
  /// scale 补到 16 对齐（3840x1598 黑屏 vs 3840x2160/1080p 正常的
  /// 根因验证 + 规避一体；8 对齐触发条件放过全部正常片源）。
  /// 触发值变化时显式写入，对齐时显式清空（换片尺寸变小路径）。
  void _applyVideoAvfilter(Size size) {
    if (_currentEngine == PlayerEngine.mpv) return;
    final filter = VideoAvfilterPolicy.resolve(
      size.width.toInt(),
      size.height.toInt(),
    );
    if (filter == _lastVideoFilter) return;
    _lastVideoFilter = filter;
    _player.setProperty('video.avfilter', filter ?? '');
    LogService().log(
      'Player',
      '视频滤镜: ${filter ?? "(无)"} '
          '| 尺寸=${size.width.toInt()}x${size.height.toInt()}',
    );
  }

  /// 滤镜取证文案：面板/导出用，区分「没触发过」vs「对齐已清」vs 实际串。
  String get _videoFilterText {
    final f = _lastVideoFilter;
    if (f == null) return '(未写入)';
    return f.isEmpty ? '(无)' : f;
  }

  /// 当前生效的视频输出通道（见 [AppSettings.eglAwareVideoOutput]）。
  /// EGL 故障进程级持久：故障后默认进片直写 SurfaceView（不再先建
  /// texture GL，避免每次进片重复触发 3004 + 自愈 race 闪退）；
  /// 用户手动改过输出则尊重手动选择（texture 档对照实验逃生口）。
  ///
  /// 再经 [AppSettings.routeVideoOutput] 按内容自动路由：HDR/10-bit 内容
  /// 直写会 wedge/卡顿（mdk#361），故降级为同载体 GL 路径。
  /// 1.1.198 起受 hdrGlWorkaround 开关控制（关 = 不降级，A/B 基线）。
  String _effectiveVideoOutput() {
    // media_kit / Erika 档：固定 texture（引擎自管理渲染，无 tunnel/surfaceView）
    if (_currentEngine == PlayerEngine.mediaKit ||
        _currentEngine == PlayerEngine.erika ||
        _currentEngine == PlayerEngine.mpv) {
      return 'texture';
    }
    final settings = ref.read(settingsProvider);
    final base = AppSettings.eglAwareVideoOutput(
      settings.videoOutput,
      eglFault: eglFaultDetector.fault,
      userSet: settings.videoOutputUserSet,
    );
    final routed = AppSettings.routeVideoOutput(base,
        isHdr: _hdrContent, enabled: settings.hdrGlWorkaround);
    // 10-bit 内容兜底（启动能力评估）：设备实测 GL 10-bit 纹理不可用
    // （EGL 正常但 R16/16F/RGB10A2 上传全失败）时强制直写，绕开 GL
    // 渲染器；未探测/未实测不介入（respect 历史行为与用户手动档）。
    final profile = ref.read(deviceProfileProvider);
    return AppSettings.tenBitAwareVideoOutput(
      routed,
      tenBit: _is10BitContent,
      gl10BitOk: !profile.tenBitGlBroken,
      userSet: settings.videoOutputUserSet,
    );
  }

  /// DV 内容的目标输出色彩空间（非 DV 返回 null，交由
  /// [_shouldForceSdrToneMap] 常规路径处理）。
  ///
  /// Android 按显示 HDR10 能力、Windows 恒 d3d11 HDR、iOS 不设置
  /// （见 [dvOutputColorSpace]）。
  AdapterColorSpace? _dvOutputColorSpace() {
    if (!_isDvContent) return null;
    return PlayerScreen.dvOutputColorSpace(
      platform: defaultTargetPlatform,
      display: ref.read(deviceProfileProvider).display,
    );
  }

  /// 是否强制 SDR tone map（`setColorSpace(bt709)`）。
  ///
  /// 仅 Android + hdrGlWorkaround 开关开启时强制（mdk-sdk#361 /
  /// fvp#379 workaround）：Flutter 纹理恒 SDR，mdk 默认 auto 会为 HDR10
  /// 内容建 bt2020_pq 表面，导致 SDR 面板发白 + 丢帧 + 纹理黑屏。此法
  /// 仅在显示不具备 HDR 能力时强制，避免误伤 HDR 屏（videoout.hdr 恒 0）。
  bool _shouldForceSdrToneMap() {
    if (!Platform.isAndroid) return false;
    final settings = ref.read(settingsProvider);
    if (!settings.hdrGlWorkaround) return false;
    return !ref.read(deviceProfileProvider).mdkHdrPassthroughCapable;
  }

  /// 按内容应用输出色彩空间（`Player.set(ColorSpace)`）。
  ///
  /// - DV 内容：走 [dvOutputColorSpace]（Android 按显示 HDR10 能力 /
  ///   Windows 恒 HDR / iOS 返回 null 不设置）。
  /// - 非 DV HDR（HDR10/HLG）：走 [HdrOutputPolicy]——显示 + 载体均支持
  ///   时真 HDR 输出（`bt2100PQ`/`bt2100hlg`），否则 `bt709` tone map。
  ///   该分支**默认生效**，不受 `hdrGlWorkaround` 实验开关门控。
  /// - 非 HDR：仅 [._shouldForceSdrToneMap] 时强制 SDR（保持既有行为）。
  void _applyOutputColorSpace() {
    final dv = _dvOutputColorSpace();
    if (dv != null) {
      _player.setColorSpace(dv);
      LogService().log('Player', 'DV 输出色彩空间: ${dv.name}');
      return;
    }
    final profile = ref.read(deviceProfileProvider);
    final hdr = PlayerScreen.resolveHdrOutputColorSpace(
      platform: defaultTargetPlatform,
      dv: _isDvContent,
      hdr: _hdrContent,
      hlg: _isHlgContent,
      surfaceView: _usesSurfaceView,
      display: profile.display,
    );
    if (hdr != null) {
      _player.setColorSpace(hdr);
      LogService().log(
        'Player',
        'HDR 输出色彩空间: ${hdr.name}'
            '（内容=${_isHlgContent ? "HLG" : "HDR10"}'
            ' 显示=${profile.display.display} 载体=${_usesSurfaceView ? "SurfaceView" : "纹理"}）',
      );
      return;
    }
    if (_shouldForceSdrToneMap()) {
      _player.setColorSpace(PlayerScreen.outputColorSpace());
      LogService().log('Player', '输出色彩空间: bt709（SDR tone map）');
    }
  }

  /// 显示器物理尺寸（渲染夹紧目标）：Android 优先原生探测（TV UI 层
  /// 常只报 1080p，须取真实输出模式）；未取得/iOS 回退 MediaQuery×dpr。
  Size? _clampDisplayPhysical() {
    final physical = _displayPhysical;
    if (physical != null && physical.width > 0 && physical.height > 0) {
      return physical;
    }
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return null;
    final s = mq.size * mq.devicePixelRatio;
    return s.width > 0 && s.height > 0 ? s : null;
  }

  /// 渲染尺寸夹紧：把 [videoSize] contain-fit 到显示器物理尺寸。
  ///
  /// 仅 HDR 内容 + hdrGlWorkaround 开关开启时生效（fvp#379 size clamp）。
  /// 高分辨率内容（4K60 等）在弱 GPU 设备上以原生尺寸过 GL 会丢帧；
  /// 夹到显示器物理尺寸后像素量最多降 4 倍，画质无感（显示器物理
  /// 像素就那么多）。视频未超过显示尺寸返回 null（保持原生）。
  /// 仅 SurfaceView 档使用（纹理档恒原生尺寸）。
  Size? _clampedRenderSize(Size videoSize) {
    if (!_hdrContent) return null;
    if (!ref.read(settingsProvider).hdrGlWorkaround) return null;
    final display = _clampDisplayPhysical();
    if (display == null) return null;
    return RenderTargetClamp.compute(
      displayPhysical: display,
      videoSize: videoSize,
    );
  }

  /// 判定并闩锁 [HDR 内容][_hdrContent]（Emby 元数据 + 运行期 mediaInfo）。
  ///
  /// 运行期优先于元数据（Emby 常把 HDR 片标成 SDR）。一旦判定为 HDR 保持
  /// 不回退；判定翻转时刷新视频输出（可能切换载体：直写→同载体 GL）。
  /// 判定为 HDR 时回写面板 `_hdrType`（1.1.187）：Emby 误标 SDR 的
  /// strm/重封装项以运行期 colorSpace 为准，保证面板取证与路由一致。
  void _refreshHdrContent() {
    if (_hdrContent) return;
    var hdr = _embyVideoStream?.isHDR == true ||
        _embyVideoStream?.isDolbyVision == true;
    var runtimeLabel = '';
    if (!hdr) {
      try {
        final videos = _player.mediaInfo.video;
        if (videos.isNotEmpty) {
          final c = videos.first;
          final cs = c.colorSpace;
          // HDR 只认色彩信息（误判修复）：10-bit 像素格式（p010/
          // yuv420p10le）在 bt709 下是 10-bit SDR，不是 HDR——旧实现
          // 把它当 HDR 导致盒子 64 位 APK 误路由/误降级黑屏。
          hdr = cs == AdapterColorSpace.bt2100PQ ||
              cs == AdapterColorSpace.bt2100hlg ||
              c.doviProfile > 0;
          if (hdr) {
            if (c.doviProfile > 0) {
              runtimeLabel = 'Dolby Vision';
            } else if (cs == AdapterColorSpace.bt2100PQ) {
              runtimeLabel = 'HDR10';
            } else if (cs == AdapterColorSpace.bt2100hlg) {
              runtimeLabel = 'HLG';
              // HLG 闩锁（HLG 不计入 isHDR，但需驱动非 DV HDR 输出策略）
              _hlgContent = true;
            } else {
              runtimeLabel = 'HDR10';
            }
          } else if (!_is10BitContent &&
              AppSettings.is10BitPixelFormat(c.formatName)) {
            // 10-bit SDR（bt709+p010 等）闩锁：非 HDR，但输出决策需
            // 参考设备 GL 10-bit 纹理能力（`_effectiveVideoOutput`）。
            _is10BitContent = true;
            LogService().log('Player',
                '10-bit SDR 内容判定: ${c.formatName}（非 HDR，按 GL 10-bit 纹理能力兜底输出）');
            if (mounted) {
              setState(() {});
              unawaited(_applyVideoOutputMode());
            }
          }
        }
      } catch (_) {}
    }
    if (!hdr || !mounted) return;
    // Emby 标签非 SDR 时保留（含 DV Profile 等更精确信息）；
    // Emby 误标 SDR 时以运行期判定回写面板。
    final embyLabel = _embyVideoStream?.hdrLabel ?? 'SDR';
    final panelLabel = embyLabel != 'SDR'
        ? embyLabel
        : (runtimeLabel.isNotEmpty ? runtimeLabel : embyLabel);
    LogService().log('Player',
        'HDR 内容判定: true（元数据=$embyLabel 运行期=${runtimeLabel.isEmpty ? "-" : runtimeLabel}）→ 自动路由直写档为同载体 GL');
    setState(() {
      _hdrContent = true;
      _hdrType = panelLabel;
    });
    _applyMpvContentHints();
    // HDR image=0 实验（1.1.190 官方 setDecoders 方式）：运行期判定
    // HDR（Emby 误标 SDR 的 strm/重封装项）兜底注入。属性内嵌在解码
    // 器名中，不受 mdk 内部 video.decoder=scale=WxH 覆写影响。
    // low_latency=1 实验（1.1.192）：同样兜底注入。
    if (Platform.isAndroid) {
      final s = ref.read(settingsProvider);
      final expNoImage = s.videoDecoderNoImage;
      final expLowLatency = s.videoDecoderLowLatency;
      if (expNoImage || expLowLatency) {
        var decoders = DecodeModeService.resolveDecoders(s.decodeMode);
        if (expNoImage) {
          decoders = PlayerScreen.mergeDecoderListImage(decoders, '0');
          LogService().log('Player',
              'HDR image=0 实验: 运行期判定 HDR → videoDecoders $decoders（下次起播生效）');
        }
        if (expLowLatency) {
          decoders = PlayerScreen.mergeDecoderLowLatency(decoders);
          LogService().log('Player',
              'low_latency=1 实验: 运行期判定 HDR → videoDecoders $decoders（下次起播生效）');
        }
        _player.videoDecoders = decoders;
      }
    }
    // 路由可能改变实际输出档位（如 surfaceViewDirect→surfaceView）→ 重应用
    unawaited(_applyVideoOutputMode());
    // 运行期才判定 HDR/HLG（Emby 误标 SDR）→ 补设输出色彩空间
    // （非 DV HDR：HDR10→PQ / HLG→HLG / 否则 tone map）。
    _applyOutputColorSpace();
  }

  /// 当前 MPV 输出是否走原生 Surface（平台视图）。
  bool get _usesMpvNativeSurface =>
      _currentEngine == PlayerEngine.mpv &&
      _player is MpvPlayerAdapter &&
      (_player as MpvPlayerAdapter).usesNativeSurface;

  /// 当前档位是否走 SurfaceView 平台视图通道（普通档或直写档）。
  bool get _usesSurfaceView =>
      AppSettings.isSurfaceViewMode(_effectiveVideoOutput());

  /// SurfaceView 直写档：解码器直写 SurfaceView 的 ANativeWindow，绕开
  /// mdk GL 渲染器与 Flutter 纹理合成（4K HDR 高负载下最省的路径）。
  bool get _surfaceViewDirect => _effectiveVideoOutput() == 'surfaceViewDirect';

  /// 当前 SurfaceView 视图是否以直写参数构建（与视图 `tunnel` 参数、
  /// 渲染兜底共用 [PlayerScreen.surfaceViewDirectWrite] 单一来源防漂移）。
  bool get _surfaceViewDirectWrite => PlayerScreen.surfaceViewDirectWrite(
        usesSurfaceView: _usesSurfaceView,
        surfaceViewDirect: _surfaceViewDirect,
        eglFault: eglFaultDetector.fault,
      );

  /// 视频输出是否就绪：纹理通道看 textureId；SurfaceView 通道无纹理，
  /// 媒体信息拿到视频尺寸即就绪。media_kit 档：VideoController 注册后即就绪。
  bool _videoOutputReady() {
    if (_currentEngine == PlayerEngine.erika) {
      // Erika 使用原生 view，不注册 Flutter texture；页面/媒体就绪即可起播。
      return _isPlayerReady;
    }
    if (_currentEngine == PlayerEngine.mediaKit ||
        _currentEngine == PlayerEngine.mpv) {
      return _player.textureId.value != null;
    }
    if (_usesSurfaceView) {
      // textureSize 可能仍在超时等待中：mediaInfo 已有有效尺寸即视为
      // 可起播（观众路径据此决定 state=playing，不能卡到尺寸 future）
      return _videoNativeSize != null || _readMediaInfoVideoSize() != null;
    }
    return _player.textureId.value != null;
  }

  /// EGL 故障自愈（真机黑屏根因）：设备 EGL 无法满足 mdk 的 config
  /// attrib（`EGL ERROR (3004)`/`No EGL config found`）→ GL presenter
  /// 无效 → 解码 buffer 全部 not rendered → 黑屏。
  ///
  /// 自愈目标是 **SurfaceView 直写**（himi_logs_2 实测纹理档直写
  /// SurfaceTexture 也黑——帧未消费 29 秒后 decode error）：SurfaceView
  /// 的 buffer queue 由窗口系统合成，既不经 mdk EGL 也不经 Flutter
  /// 纹理/合成，是该故障下唯一完全隔离的通路。切档后 build 里
  /// `tunnel: eglFaultDetector.fault` 使 key 变化强制 platform view
  /// 按直写参数重建。
  ///
  /// 幂等：`_eglFaultHandled` 防重入；已在 SurfaceView 档则仅强制
  /// rebuild（surface 可能已按 tunnel=false 建立）。
  /// v1.1.75：播放中自愈静音——不再弹 SnackBar（3 条提示全删），
  /// 提示只留诊断面板 `_diag.note` 与日志，切档/落盘行为不变。
  void _onEglFault() {
    if (_eglFaultHandled || !mounted) return;
    _eglFaultHandled = true;
    LogService().log('Player', '检测到 EGL 初始化失败（设备 GL 驱动不兼容）');
    // 跨重启持久化：本次为冷启动首次故障（texture GL 已创建 → 可能已
    // 触发 stop race），落盘后下次启动直接直写，此后不再有自愈流程。
    unawaited(ref.read(settingsProvider.notifier).update(eglFaultSeen: true));
    final settings = ref.read(settingsProvider);
    // 尊重手动选择（v1.1.72）：用户改过输出档位则不写回 surfaceView，
    // 保留 texture 档对照实验逃生口；未手动才执行老自愈自动切档。
    final writeBack = AppSettings.eglFaultWriteBack(settings.videoOutput,
        userSet: settings.videoOutputUserSet);
    if (writeBack != null) {
      ref.read(settingsProvider.notifier).update(videoOutput: writeBack);
      _diag.note('EGL 初始化失败 → 切换 SurfaceView 直写（重启后完全生效）');
    } else {
      final manual = settings.videoOutputUserSet;
      _diag.note(manual
          ? 'EGL 初始化失败 → 保持手动档位（若画面异常请切 SurfaceView）'
          : 'EGL 初始化失败 → 保持当前档位');
    }
    if (mounted) setState(() {});
    // 冷启动首次故障不做 stop/重建自愈（v1.1.69 定案）：himi_logs_4 中
    // stop 与 native EGL 创建流程并发是偶发 native crash 主嫌（卡
    // 00:00 后闪退回桌面）。故障已落盘 eglFaultSeen → 本次仅记日志+
    // 按需切档，下次启动按 eglFaultSeen/userSet 决定档位。
    //
    // tunnel 参数变化（tunnel: eglFaultDetector.fault 进 surfaceKey）
    // 会让 view key 失配：两阶段重建让 destroy 先落定再挂直写参数，
    // 防同帧拆建竞态（EGL 翻转是播放中唯一会改 key 的路径）。
    if (_usesSurfaceView && _videoNativeSize != null && !_surfaceDetached) {
      unawaited(_remountSurfaceView());
    }
    if (mounted) setState(() {});
  }

  /// 喂渲染风暴检测器；命中（1s 内丢帧达阈值）写诊断日志与时间线。
  /// 只记日志不动作（v1.1.82 定案：主动重挂 view 可能触发同一 mdk
  /// renderer 缺陷）。log handler 可能来自 mdk 内部线程，LogService/
  /// _diag 均为纯 Dart 集合，可直接调用。
  void _feedRenderStorm(String message) {
    final line = _renderStorm.feed(message);
    if (line == null) return;
    _diag.note(line);
    LogService().log('Diag', line);
  }

  /// 喂 EGL 检测器；检测器已置位而本页面尚未自愈时补一次自愈
  /// （log handler 可能来自 mdk 内部线程回调，widget 操作须回到
  /// Dart 事件循环）。
  ///
  /// 不能只看 [EglFaultDetector.feed] 的返回值：一次性命中语义下，
  /// 首个故障签名可能已被 main 全局 handler 或本页面此前实例消费
  /// （feed 返回 false），而 view 仍按 tunnel=false（GL）建过——不
  /// 自愈会停在 GL 路径黑屏（「有时一直黑」根因之一）。触发时
  /// `_onEglFault` 自带 `_eglFaultHandled` 防重入 / `mounted` 守卫。
  ///
  /// v1.2.14 会话级守卫（[PlayerScreen.shouldTriggerEglHeal]）：会话开始
  /// 前已置位的故障不触发——持久标记设备 view 已按直写参数构建，误自愈
  /// 只会做无谓重建并制造起播 renderer 丢帧竞态；仅会话内新故障触发。
  void _feedEglDetector(String message) {
    eglFaultDetector.feed(message);
    if (PlayerScreen.shouldTriggerEglHeal(
      fault: eglFaultDetector.fault,
      handled: _eglFaultHandled,
      faultAtSessionStart: _eglFaultAtSessionStart,
    )) {
      Future.microtask(_onEglFault);
    }
  }

  /// 设置切换视频输出档位后的即时应用（由 build 里的 ref.listen 触发）。
  ///
  /// - 切到 SurfaceView：释放纹理（platform view 通道不经 Flutter 合成），
  ///   widget 分支随后重建出 fvp/video-view；
  /// - 切到纹理/直通：platform view 由 widget 分支卸载（surfaceDestroyed
  ///   自动释放原生 surface），随后按新档位重建纹理。
  Future<void> _applyVideoOutputMode() async {
    if (!mounted) return;
    final mode = _effectiveVideoOutput();
    LogService().log('Player', '视频输出档位切换 → $mode');
    // 档位切换销毁/重建 platform view：绑定标志复位，下次起播重新等待
    _surfaceViewCreated = false;
    if (_usesSurfaceView) {
      if (_player.textureId.value != null) {
        try {
          await _player
              .updateTexture(width: -1)
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          LogService().log('Player', '释放纹理失败: $e');
        }
        _textureOutputApplied = null;
      }
    } else {
      // 档位变化需要按 tunnel 参数重建；_ensureTexture 内部比对
      // _textureOutputApplied 决定是否释放重建。
      await _ensureTexture();
    }
    if (mounted) setState(() {});
  }

  /// 确保纹理存在：首次播放时创建，后续复用现有纹理避免黑屏
  ///
  /// 按设置档位区分：
  /// - 'texture' / 'tunnel'：创建（或在 tunnel 档位变化时重建）纹理，
  ///   tunnel 档位走 updateTexture(tunnel: true)——解码器直写
  ///   SurfaceTexture，绕过 mdk GL 渲染器；
  /// - 'surfaceView' / 'surfaceViewDirect'：不创建纹理，反向释放已存在
  ///   的纹理（platform view 通道由 _buildVideoArea 构建 fvp/video-view）。
  ///
  /// 落盘 updateTexture 返回值/textureId/textureSize/视频流数：
  /// iOS 曾出现「无画面」，纹理链路是否走通全靠这行取证——
  /// 返回 -1 表示 fvp 内部 _videoSize 未就绪（媒体未 loaded 或
  /// 视频流为空），此时纹理恒为 null，UI 永远转圈。
  Future<void> _ensureTexture() async {
    if (!mounted || _disposed) return;
    final mode = _effectiveVideoOutput();

    if (_usesSurfaceView) {
      if (_player.textureId.value != null) {
        try {
          await _player
              .updateTexture(width: -1)
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        _textureOutputApplied = null;
        if (!mounted || _disposed) return;
        LogService().log('Player', 'SurfaceView 通道：已释放纹理');
      }
      return;
    }

    final tunnel = mode == 'tunnel';
    if (_player.textureId.value != null) {
      if (_textureOutputApplied == mode) return;
      // 档位（tunnel 开关）变化：释放旧纹理后按新参数重建
      LogService().log('Player', '纹理档位 $_textureOutputApplied → $mode，重建纹理');
      try {
        await _player
            .updateTexture(width: -1)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      _textureOutputApplied = null;
    }
    if (!mounted || _disposed) return;
    // 播中尺寸变化不重建纹理（_textureOutputApplied 按档位去重），
    // 规避「释放+重建」黑屏族问题（958fcb7/6f2fb5b 教训）。
    // 渲染尺寸夹紧仅在 SurfaceView 档生效（fvp#379 size clamp），
    // 纹理档恒传 null 让 mdk 使用原生尺寸。
    try {
      final texId = await _player
          .updateTexture(
            width: null,
            height: null,
            tunnel: tunnel,
          )
          .timeout(const Duration(seconds: 5));
      if (!mounted || _disposed) return;
      // 返回 -1 说明 _videoSize 未 resolve：短暂等待 loaded 事件后重试一次
      if (texId < 0) {
        LogService().log('Player', 'updateTexture 返回 $texId，200ms 后重试');
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || _disposed) return;
        if (_player.textureId.value == null) {
          await _player
              .updateTexture(
                width: null,
                height: null,
                tunnel: tunnel,
              )
              .timeout(const Duration(seconds: 5));
          if (!mounted || _disposed) return;
        }
      }
      if (_player.textureId.value != null) _textureOutputApplied = mode;
      String videoStreams = '?';
      try {
        videoStreams = '${_player.mediaInfo.video.length} 路';
      } catch (_) {}
      LogService().log(
          'Player',
          '纹理: 返回 $texId, textureId ${_player.textureId.value}, '
              '视频流 $videoStreams, tunnel $tunnel');
    } catch (e) {
      LogService().log('Player', 'updateTexture 失败: $e');
    }
  }

  /// 换源渐出：仅在有声音播放时渐出到 0，避免首播/暂停态做无意义延迟。
  /// 返回是否真的执行了渐出（调用方据此决定是否渐入）。
  Future<bool> _fadeOutForSwitch() async {
    if (_player.state != AdapterPlaybackState.playing) return false;
    final from = _player.volume;
    if (from <= 0) return false;
    // 渐出前记录用户目标音量：窗口内 _volume 若被污染，渐入仍收敛到此值
    _volGuard.markFadeOutStart(_volume / 100);
    await _fader.fadeTo((v) {
      if (mounted) _player.volume = v;
    }, from, 0);
    return true;
  }

  /// 起播渐入：从当前音量（渐出后为 0）线性恢复到用户音量。
  /// 目标以 [SwitchVolumeGuard] 记录值优先（防换源窗口回写污染）；
  /// 已在目标音量时直接跳过（首播、未渐出的换源均走此短路）。
  Future<void> _fadeInForSwitch() async {
    if (!mounted) return;
    final target = _volGuard.fadeInTarget(_volume / 100);
    final from = _player.volume;
    if ((from - target).abs() >= 0.001) {
      await _fader.fadeTo((v) {
        if (mounted) _player.volume = v;
      }, from, target);
    }
    // 渐入结束（含短路）即换源音量窗口关闭；期间 _volume 可能已被
    // 污染为 0，此处对齐回目标（其后 switching 尚未清除时回写仍被挡），
    // 残留的 switching 期回写会写入 player.volume(=target) 自洽值。
    _volGuard.endSwitch();
    if (mounted && (_volume / 100 - target).abs() >= 0.001) {
      _volume = target * 100;
      _volumeNotifier.value = _volume;
    }
  }

  /// 截帧取证（面板相机按钮）：mdk snapshot 双调用后取平均亮度。
  ///
  /// mdk wiki：首调常因无已渲染帧返回 null，须连调两次。判读：
  /// - 亮度非黑 → mdk 已渲染出帧，黑屏在 Flutter 合成侧（SurfaceView 档可解）；
  /// - null/全黑 → mdk 渲染输出即黑（tunnel/解码侧问题）。
  /// tunnel 档无 GL 渲染器不支持回读，直接标注。
  Future<void> _probeSnapshot() async {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastSnapshotAt != null &&
        now.difference(_lastSnapshotAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSnapshotAt = now;
    setState(() => _snapshotInfo = '取帧中…');
    try {
      if (_effectiveVideoOutput() == 'tunnel' || _surfaceViewDirect) {
        setState(() => _snapshotInfo = '直写档无渲染器，不支持回读');
        return;
      }
      // wiki：首调往往无帧；3s 超时防黑屏设备 readback 挂死（实测
      // 该机型纹理档 snapshot 触发 native crash，按钮已在 Android 隐藏）
      await _player.snapshot().timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final data = await _player.snapshot().timeout(const Duration(seconds: 3));
      if (!mounted) return;
      if (data == null || data.isEmpty) {
        setState(() => _snapshotInfo = 'null（无已渲染帧）');
      } else {
        final lum = SnapshotProbe.avgLuminancePercent(data);
        setState(() =>
            _snapshotInfo = '${data.length}B · 亮度 ${lum.toStringAsFixed(1)}%');
      }
    } catch (e) {
      if (mounted) setState(() => _snapshotInfo = '失败: $e');
    }
    if (mounted) LogService().log('Diag', '截帧: $_snapshotInfo');
  }

  /// 切换/重建前释放旧引擎：可 await 的 await（Erika/media_kit），
  /// fvp(mdk) 为 `void async` → settle 等待其原生 teardown 落定。
  ///
  /// 目的：避免新引擎在旧引擎**异步释放窗口**内创建 —— 否则音频输出争用
  /// （TrueHD 卡顿）、原生状态回调劣化（播放/暂停图标不动）。
  Future<void> _disposeOldEngine() async {
    final old = _player;
    if (old is AsyncDisposablePlayer) {
      final disposable = old as AsyncDisposablePlayer;
      try {
        await disposable.disposeAsync().timeout(const Duration(seconds: 2));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } else {
      try {
        old.dispose();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    // 复位 per-player 去重态：确保新引擎一定重写 audio.avfilter/后端
    _lastAudioFilter = null;
    _lastAudioFilterCodec = '';
  }

  /// 开播前按内容重建引擎/适配器（此时尚未 open，无"播放中拆台"）。
  Future<void> _recreateEngineForLoad(
      PlayerEngine engine, ErikaOutputMode outputMode) async {
    if (!mounted) return;
    LogService().log('Player',
        '内容路由重建引擎: ${_currentEngine.label} → ${engine.label} (erikaMode=$outputMode)');
    // 先停旧引擎（原生视图还在渲染时摘掉会访问已分离 surface → 卡顿/崩溃）
    try {
      _player.state = AdapterPlaybackState.stopped;
    } catch (_) {}
    _stateSub?.cancel();
    _statusSub?.cancel();
    _eventSub?.cancel();
    _tracksSubscription?.cancel();
    _positionTimer?.cancel();
    _skipPromptTimer?.cancel();
    _diagnosticTimer?.cancel();
    _sampleTimer?.cancel();
    // 换内核后位置会重新落点，清掉旧引擎的片段判定基线。
    _skipPromptSuppressed = true;
    _skipController.reset();
    _skipPromptPlaybackWatch.reset();
    _skipPromptTimer?.cancel();
    _skipPromptTimer = null;
    _skipPromptSegment = null;
    // 停后再卸载旧视频视图（避免旧 widget 访问已释放播放器）
    setState(() => _switchingEngine = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _disposed) return;
    await _disposeOldEngine();
    if (!mounted || _disposed) return;
    // 原子赋值：_currentEngine 与 _player 紧邻同步更新（中间无 await），避免帧内错配。
    _currentEngine = engine;
    _lastMediaKitFitKey = null;
    _player = PlayerEngineFactory.create(engine, erikaOutputMode: outputMode);
    _switchingEngine = false;
    await _initPlayerProperties();
    if (!mounted || _disposed) return;
    // _initPlayerProperties 不覆盖的三项（initState 单独写、重建后会丢）：
    // 字幕属性 / 音频后端 / 音频滤镜策略（_disposeOldEngine 已复位去重态，
    // 此处重写保证新引擎与起播一致）。
    if (_currentEngine != PlayerEngine.mpv) {
      _player.setProperty('subtitle', '1');
      _player.setProperty('subtitle.font.size', '40');
      _player.setProperty('subtitle.border', '2');
      _player.setProperty('subtitle.shadow', '1');
    }
    _applySubtitleStyle();
    final renderer = AppSettings.effectiveAudioRenderer(
        ref.read(settingsProvider).audioRenderer);
    if (renderer != 'auto') {
      _player.audioBackends = [renderer];
    }
    _applyAudioFilterPolicy(codec: _currentAudioCodec());
    _setupPlayerListeners();
    if (engine == PlayerEngine.erika) _applyErikaDanmaku();
  }

  /// 加载流并返回 texture 是否就绪
  ///
  /// 加载中返回（dispose）会与本协程竞争：每个 native 调用与 `await` 续体
  /// 前都必须查 `mounted`，否则会对已销毁的 mdk 对象发起调用导致原生崩溃。
  Future<bool> _loadStream({
    String? itemId,
    int? subtitleStreamIndex,
    String? mediaSourceId,
    String? serverId,
    int startMs = 0,
    int? fallbackDurationMs,
  }) async {
    _fallbackDurationMs = fallbackDurationMs ?? 0;
    if (!mounted) return false;
    _beginSkipPromptSuppression();
    // 会话级 EGL 守卫基准（v1.2.14）：本次流加载前的检测器状态快照。
    _eglFaultAtSessionStart = eglFaultDetector.fault;
    final targetItemId = itemId ?? widget.itemId;
    final effectiveMediaSourceId = mediaSourceId ??
        (targetItemId == widget.itemId ? widget.mediaSourceId : null);

    final effectiveServerId = serverId ?? widget.serverId;
    // 换内容：按内容 id 恢复字幕样式（无记录沿用当前内存值）
    unawaited(_restoreSubtitleStyleForContent());
    try {
      if (!mounted) return false;
      final embyService = ref.read(embyServiceForProvider(effectiveServerId));
      final config = ref.read(embyConfigForProvider(effectiveServerId));
      final token = config?.accessToken ?? '';

      final proxyUrl = embyService.getStreamUrl(
        targetItemId,
        mediaSourceId: effectiveMediaSourceId,
        subtitleStreamIndex: subtitleStreamIndex,
      );

      // 播放会话上报上下文（切集重生成 sessionId、重置 start 标记）
      _reportService = embyService;
      _reportItemId = targetItemId;
      _reportServerConfigId = config?.id;
      _reportMediaSourceId = effectiveMediaSourceId;
      _reportStarted = false;
      _stopReportTimer();
      // 官方 PlaySessionId（Emby 据此把进度写入 UserData）+ 媒体源
      // （STRM 直链播放解析 DirectStreamUrl 用）；失败回退本地生成
      final playbackInfo = await embyService.getPlaybackInfo(
        itemId: targetItemId,
        mediaSourceId: effectiveMediaSourceId,
      );
      _playSessionId = playbackInfo.playSessionId ?? const Uuid().v4();

      // STRM 直链播放：开启且未请求内嵌字幕时，优先服务器返回的绝对直链
      // （DirectStreamUrl / .strm 内容 URL），服务器不兼容则回退代理。
      final strmEnabled =
          subtitleStreamIndex == null && (config?.strmDirectPlay ?? false);
      final source = playbackInfo.sourceById(effectiveMediaSourceId);
      final sourceRuntimeMs =
          source?.runTimeTicks != null && source!.runTimeTicks! > 0
              ? source.runTimeTicks! ~/ 10000
              : 0;
      if (sourceRuntimeMs > 0) {
        _fallbackDurationMs = sourceRuntimeMs;
      }
      final streamUrl = strmEnabled
          ? resolveStrmDirectUrl(source: source, proxyUrl: proxyUrl)
          : proxyUrl;
      if (strmEnabled && streamUrl != proxyUrl) {
        LogService().log('Player', 'STRM 直链播放: $streamUrl');
      }

      _currentPlayUrl = streamUrl;
      _currentToken = token;

      // 重置进度（与首次播放状态一致）；续播目标先占位，避免 UI 跳 0。
      _position = Duration(milliseconds: startMs > 0 ? startMs : 0);
      _positionNotifier.value = _position;
      _duration = Duration.zero;
      _durationNotifier.value = _duration;
      _endHandled = false;
      // 切集零重建（v1.1.82 根修）：不拆 FvpSurfaceView、不置空尺寸、
      // 不动 epoch——旧 view/surface/EGL 上下文在遮罩下全程复用。
      // 此前 epoch+1 拆建会让 mdk renderer 在重建上下文上渲 1 帧后
      // 永久丢帧（himi_logs_5：切集后画面定格首帧、音频进度正常）。
      // 分辨率变化由 _syncVideoNativeSize 探测后走 _remountSurfaceView
      // 两阶段重建；textureSize/重试计数照常复位。
      _videoSizeRetry = 0;
      _videoSizeRetryPending = false;
      _renderStorm.reset();

      // 设置媒体并准备播放（native 调用前必须 mounted）
      if (!mounted) return false;
      if (token.isNotEmpty) {
        _player.setHttpHeaders({'X-Emby-Token': token});
      }

      // HDR image=0 实验（1.1.190 官方 setDecoders 方式）：Emby 元数据
      // 判定 HDR/DV 时，起播前注入 image=0 到解码器列表，禁用
      // AImageReader/AHardwareBuffer 路径，回退旧 Surface/BufferQueue
      // 输出。A/B 验证「AImageReader P010 慢路径」假设。SDR 内容显式
      // 恢复 image=1 防残留。运行期判定由 _refreshHdrContent 兜底注入。
      // 属性内嵌在解码器名中（AMediaCodec:image=0），不受 mdk 内部
      // video.decoder=scale=WxH 覆写影响。
      //
      // low_latency=1 实验（1.1.192）：AMediaCodec 解码器属性，改变
      // 硬解器内部 buffer 管理路径，A/B 验证 10-bit P010 簇状丢帧。
      if (Platform.isAndroid) {
        final s = ref.read(settingsProvider);
        final expNoImage = s.videoDecoderNoImage;
        final expLowLatency = s.videoDecoderLowLatency;
        if (expNoImage || expLowLatency) {
          final embyHdr = _embyVideoStream?.isHDR == true ||
              _embyVideoStream?.isDolbyVision == true;
          var decoders = DecodeModeService.resolveDecoders(s.decodeMode);
          if (expNoImage) {
            final target = embyHdr ? '0' : '1';
            decoders = PlayerScreen.mergeDecoderListImage(decoders, target);
            LogService().log(
                'Player',
                'HDR image=0 实验: ${embyHdr ? "HDR/DV" : "SDR"} → '
                    'videoDecoders $decoders');
          }
          if (expLowLatency) {
            decoders = PlayerScreen.mergeDecoderLowLatency(decoders);
            LogService()
                .log('Player', 'low_latency=1 实验: videoDecoders $decoders');
          }
          _player.videoDecoders = decoders;
        }
      }

      // 换源前渐出：同 player 硬切 media 时新旧音频波形不连续会爆音
      // （Windows XAudio2 已复现），渐出→换源→起播渐入消除爆音。
      await _fadeOutForSwitch();
      if (!mounted || _disposed) return false;

      // 输出色彩空间：防 player 状态重置丢失 initState 的设置。
      // DV 内容按平台策略（Android HDR10/SDR、Windows 恒 HDR、iOS 不设置）；
      // 其余仅 Android + hdrGlWorkaround 且显示无 HDR 能力时强制 bt709。
      await _routeHdrToMpvIfNeeded();
      if (!mounted || _disposed) return false;
      _applyOutputColorSpace();
      _isSwitchingMedia = true;
      _applyMpvContentHints();
      _player.media = streamUrl;
      await _player.prepare(startMs: startMs);
      // prepare 期间可能已 dispose：必须先复查再触碰 player。
      if (!mounted || _disposed) return false;
      // 播放器不报 duration 时，用 Emby RunTimeTicks 兜底显示总进度。
      _syncDurationFromPlayer();
      // 媒体重载不携带倍速：恢复用户所选档（fvp 侧为 Dart 状态）
      _player.playbackRate = _speed;

      // 确保纹理存在（首次创建，后续复用，避免切集黑屏）
      await _ensureTexture();
      if (!mounted) return false;

      // 同步设置视频原生尺寸（从 mediaInfo 读取）
      await _syncVideoNativeSize();
      if (!mounted) return false;

      // SurfaceView：等 surfaceCreated 完成 nativeSetSurface 绑定后再
      // 起播（tunnel 档 setDecoders(surface) 在此重开新集解码器）；
      // 非 SurfaceView 档立即通过，超时兜底不阻塞起播
      await _waitSurfaceCreated();
      if (!mounted) return false;

      // 继续观看：prepare 已尝试定位；这里等待媒体就绪并校验/兜底。
      await _ensureInitialPosition(startMs);
      if (!mounted) return false;

      // 启动播放（无条件，首播和切集都需要）
      if (mounted) {
        _player.state = AdapterPlaybackState.playing;
        _skipPromptSuppressed = false;
        _syncPlayState();
        // 起播成功重新起算自动隐藏：慢流首开可能远超 5s，进入页时的
        // 计时器已到点（当时 state!=playing 被跳过），不重开则控件常驻。
        _resetHideTimer();
        setState(() {});
      }
      // 起播渐入恢复用户音量（未渐出/已在目标音量时内部直接跳过）
      await _fadeInForSwitch();
      // Emby 播放会话开始上报（单人/房主）
      unawaited(_reportStart());
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        await _detectDolbyVision();
      });

      // 延迟清除切换锁，确保旧媒体的 MediaStatus.end 事件被完全过滤
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _isSwitchingMedia = false;
      });

      // 加载成功：复位同线路重载预算（v1.1.245）
      _streamReload.reset();

      return _videoOutputReady();
    } catch (e) {
      LogService().log('Player', '加载流失败: $e');
      _isSwitchingMedia = false;
      // 换源途中失败：把渐出到 0 的音量恢复，避免整场静音
      _fader.cancel();
      final restore = _volGuard.fadeInTarget(_volume / 100);
      _volGuard.endSwitch();
      if (mounted) {
        _player.volume = restore;
        if ((_volume / 100 - restore).abs() >= 0.001) {
          _volume = restore * 100;
          _volumeNotifier.value = _volume;
        }
        // 视频流同线路自动重载（v1.1.245）：取流失败按退避重载当前流
        final willSchedule = _streamReload.canSchedule;
        _maybeStreamReload('取流失败');
        if (!willSchedule && _streamReload.exhausted) {
          // 已耗尽且本次未能调度：明确提示中断
          showAppToast(context, '网络异常，播放已中断');
        } else if (willSchedule) {
          // 首次进入重载流程：提示一次（后续退避重试静默）
          showAppToast(context, '播放失败，正在重试...');
        }
      }
      return false;
    }
  }

  /// 观众播放：从 syncPlay 消息中的 playUrl 直接播放
  void _playFromUrl({
    required String playUrl,
    required String token,
    double position = 0.0,
    int? epIndex,
  }) async {
    if (!mounted) return;

    // 同 URL 单飞：丢弃并发重复调用（roomInfo+syncPlay+requestRoomInfo 响应
    // 可能对同一 URL 先后/并发触发），避免并发 media=/prepare/纹理/引擎重建。
    if (playUrl == _inFlightPlayUrl) {
      LogService().log('Sync', '忽略重复 _playFromUrl（同 URL 在飞）');
      return;
    }

    final requestId = ++_playRequestId;
    _inFlightPlayUrl = playUrl;
    // 会话级 EGL 守卫基准（v1.2.14）：本次流加载前的检测器状态快照。
    _eglFaultAtSessionStart = eglFaultDetector.fault;
    // 同步写入当前播放地址（原先在 media= 之后写，多个 await 前守卫失效）：
    // 使 roomInfo 的 `playUrl != _currentPlayUrl` 去重立即生效。
    _currentPlayUrl = playUrl;
    _currentToken = token;
    _isSyncing = true;
    try {
      _addBroadcastMessage('同步主持人播放');

      // fvp 原生处理重定向，直接使用 playUrl
      LogService().log('Sync', '直接使用 playUrl: ${playUrl.length}字符');

      // 检查是否已被更新的请求抢占
      if (requestId != _playRequestId || !mounted) return;

      // 切换视频前重置进度（与首次播放状态一致）
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _duration = Duration.zero;
      _durationNotifier.value = _duration;
      _endHandled = false;
      // 切集零重建（v1.1.82 根修，同 _loadStream）：view/surface/
      // EGL 上下文全程复用，尺寸变化才走 _remountSurfaceView。
      _videoSizeRetry = 0;
      _videoSizeRetryPending = false;
      _renderStorm.reset();
      _diag.reset();
      _decoderReport = DecoderReport.empty;
      _codecProbeKey = '';
      _bufProgress = -1;

      // 设置媒体并准备播放
      if (token.isNotEmpty) {
        _player.setHttpHeaders({'X-Emby-Token': token});
      }

      // prepare 前探测 DV 解码能力
      await _probeDvCapability();
      await _loadBuildIdentity();
      if (!mounted || _disposed) return;

      // 换源前渐出（同 player 硬切 media 的爆音修复），渐出后复查抢占：
      // 被新请求抢占时恢复音量并交给赢家流程接管。
      await _fadeOutForSwitch();
      if (requestId != _playRequestId || !mounted || _disposed) {
        final restore = _volGuard.fadeInTarget(_volume / 100);
        _volGuard.endSwitch();
        if (mounted) {
          _fader.cancel();
          _player.volume = restore;
        }
        return;
      }

      // 抢占复查（关闭 2850→2891 之间的守卫空洞）：被更新请求抢占则不再触碰
      // media/prepare/纹理，避免落败调用在赢家流程上叠加渲染操作。
      if (requestId != _playRequestId || !mounted || _disposed) return;

      await _routeHdrToMpvIfNeeded();
      if (requestId != _playRequestId || !mounted || _disposed) return;
      _isSwitchingMedia = true;
      _applyOutputColorSpace();
      _applyMpvContentHints();
      // _currentPlayUrl/_currentToken 已在入口同步写入。
      _player.media = playUrl;
      await _player.prepare();
      if (requestId != _playRequestId || !mounted || _disposed) return;
      _player.playbackRate = _speed;

      // 确保纹理存在（首次创建，后续复用，避免切集黑屏）
      await _ensureTexture();
      if (!mounted) return;
      // 同步设置视频原生尺寸（从 mediaInfo 读取）
      await _syncVideoNativeSize();
      if (!mounted) return;

      // SurfaceView：等 surfaceCreated 绑定完成后再起播（超时兜底）
      await _waitSurfaceCreated();
      if (!mounted) return;

      // 单人模式自动横屏
      if (widget.roomCode == null && mounted) {
        _switchToLandscape(_OrientationMode.landscapeLeft);
      }

      // 缓冲完成，再次检查是否已被抢占
      if (requestId != _playRequestId || !mounted) return;

      setState(() {
        if (epIndex != null) _currentEpisodeIndex = epIndex;
        _isPlayerReady = true;
      });
      // 集就绪后拉取弹幕（覆盖房间/同步起播路径）
      if (_danmakuOn && _currentEpisodeIndex >= 0) _loadDanmaku();

      // 仅在视频输出就绪时启动播放，避免有声无画
      if (_videoOutputReady()) {
        if (position > 0) {
          await _seekGuarded((position * 1000).toInt());
        }

        _player.state = AdapterPlaybackState.playing;
        _syncPlayState();
        // 起播成功重新起算自动隐藏（慢流首开超 5s 时首计时已空转跳过）
        _resetHideTimer();
        // 起播渐入恢复用户音量（无渐出时内部直接跳过）
        await _fadeInForSwitch();
      } else if (mounted) {
        // 输出未就绪不启动播放：把可能的渐出音量恢复，避免误判为静音故障
        _fader.cancel();
        final restore = _volGuard.fadeInTarget(_volume / 100);
        _volGuard.endSwitch();
        _player.volume = restore;
        if ((_volume / 100 - restore).abs() >= 0.001) {
          _volume = restore * 100;
          _volumeNotifier.value = _volume;
        }
      }
      _rebuildGroups();
      _logSyncEvent('播放器打开成功');
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _queryHwdecStatus();
      });
      LogService().log('Sync', '播放器打开成功');

      // 延迟清除切换锁，确保旧媒体的 MediaStatus.end 事件被完全过滤
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _isSwitchingMedia = false;
      });
    } catch (e) {
      _isSwitchingMedia = false;
      // 渐出后异常退出：恢复音量，避免整场静音
      _fader.cancel();
      final restore = _volGuard.fadeInTarget(_volume / 100);
      _volGuard.endSwitch();
      if (mounted) {
        _player.volume = restore;
        if ((_volume / 100 - restore).abs() >= 0.001) {
          _volume = restore * 100;
          _volumeNotifier.value = _volume;
        }
      }
      _logSyncEvent('播放器打开失败: $e');
      LogService().log('Sync', '播放器打开失败: $e');
      _addBroadcastMessage('同步播放失败: $e');
    } finally {
      if (requestId == _playRequestId) {
        _isSyncing = false;
        _inFlightPlayUrl = null;
      }
    }
  }

  /// 首次确认已经真正起播：时长可读、位置推进或进入 playing。
  ///
  /// 转码/直播流可能永远报不出时长，不能只靠 duration 判断起播；
  /// 置位后刷新一次，让初始转圈和加载期控件强显立即结束。
  void _markPlaybackStarted() {
    if (_hasStartedPlayback) return;
    _hasStartedPlayback = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _syncDurationFromPlayer() {
    final next = Duration(
      milliseconds: PlayerScreen.effectiveDurationMs(
        playerMs: _player.duration,
        fallbackMs: _fallbackDurationMs,
      ),
    );
    if (next.inMilliseconds <= 0) return;
    _markPlaybackStarted();
    if (next.inMilliseconds == _duration.inMilliseconds) return;
    _duration = next;
    _durationNotifier.value = _duration;
    _refreshTracks();
    final segmentItem = _segmentMediaItem;
    if (segmentItem != null && _segmentDurationMs <= 0 && !_isSwitchingMedia) {
      unawaited(_loadSkipSegments(segmentItem, resetController: false));
    }
  }

  Future<void> _ensureInitialPosition(int startMs) async {
    if (startMs <= 0 || !mounted) return;
    final player = _player;
    if (player is MediaLoadWaitPlayer) {
      try {
        await (player as MediaLoadWaitPlayer)
            .waitUntilMediaReady(timeout: const Duration(seconds: 10));
      } catch (_) {}
    }
    if (!mounted) return;

    _isSeekingPlayback = true;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final current = _player.position;
        if ((current - startMs).abs() <= 1500) break;
        try {
          await _player
              .seek(positionMs: startMs)
              .timeout(const Duration(seconds: 2));
        } catch (error) {
          LogService().log('Player', '初始续播 seek 失败: $error');
        }
        if (!mounted) return;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
        }
      }
    } finally {
      _isSeekingPlayback = false;
      _lastSeekCompletedAt = DateTime.now();
    }
    if (!mounted) return;
    final actual = _player.position;
    _position = Duration(
      milliseconds: actual > 0 ? actual : startMs,
    );
    _positionNotifier.value = _position;
    if ((actual - startMs).abs() > 1500) {
      LogService().log(
        'Player',
        '初始续播未落到目标: target=${startMs}ms actual=${actual}ms',
      );
    }
  }

  void _setupPlayerListeners() {
    // 使用 onStateChanged 监听播放状态变化
    _stateSub = _player.onStateChanged.listen((event) {
      if (!mounted) return;
      // 更新音量（换源渐变期间跳过：渐变把 player.volume 压到 0，
      // 回写会让音量条跟着跳 0 且目标音量丢失；换源窗口同理——渐出
      // 完成→渐入开始之间回写 0 会污染渐入目标导致永久静音）
      if (_volGuard.canWriteBack(
          fading: _fader.active, switching: _isSwitchingMedia)) {
        _volume = _player.volume * 100;
        _volumeNotifier.value = _volume;
      }
      if (event.newValue == AdapterPlaybackState.playing) {
        _syncDurationFromPlayer();
      }
      _syncPlayState();
    });

    // 使用 onMediaStatus 监听媒体状态变化
    _statusSub = _player.onMediaStatus.listen((event) {
      if (!mounted) return;

      // duration 可能晚于 loaded/buffering 事件到达；任意状态事件都补读一次。
      _syncDurationFromPlayer();

      // 检查是否播放结束
      if (event.newValue.test(AdapterMediaStatus.end)) {
        // mdk keyframe seek 窗口会误报 end 位（拖进度条误切集）：
        // seek/拖动中或位置远离结尾的 end 一律忽略。
        final seekAt = _lastSeekCompletedAt;
        final seekInProgress = _isSeekingPlayback ||
            _isDraggingSlider ||
            (seekAt != null &&
                DateTime.now().difference(seekAt) <
                    PlayerScreen.autoNextSeekCooldown);
        if (PlayerScreen.shouldHandleEngineEnd(
          seekInProgress: seekInProgress,
          positionMs: _player.position,
          durationMs: _duration.inMilliseconds,
        )) {
          unawaited(_handleEpisodeFinished(
            completedAtMs:
                _duration.inMilliseconds > 0 ? _duration.inMilliseconds : null,
          ));
        }
      }

      // 播放错误处理
      if (event.newValue.test(AdapterMediaStatus.invalid)) {
        LogService().log('Player', '播放错误: ${event.newValue}');
        _addBroadcastMessage('播放出错');
        // 视频流同线路自动重载（v1.1.245）：invalid 按退避重载当前流
        final willSchedule = _streamReload.canSchedule;
        _maybeStreamReload('播放错误');
        if (!willSchedule && _streamReload.exhausted) {
          // 已耗尽且本次未能调度：明确提示中断
          showAppToast(context, '网络异常，播放已中断');
        } else if (willSchedule) {
          // 首次进入重载流程：提示一次（后续退避重试静默）
          showAppToast(context, '播放出错，正在重试...');
        }
      }

      // 卡顿边沿检测：buffering 进入 / buffered 或 stalled 退出
      final wasBuffering = event.oldValue.test(AdapterMediaStatus.buffering);
      final isBuffering = event.newValue.test(AdapterMediaStatus.buffering);
      if (!wasBuffering && isBuffering) {
        _diag.onStallStart('buffering');
        LogService().log('Diag', '开始缓冲');
        _startStallWatchdog();
      }
      final isRecovered = !event.newValue.test(AdapterMediaStatus.buffering) &&
          !event.newValue.test(AdapterMediaStatus.stalled);
      if (wasBuffering && isRecovered) {
        _diag.onStallEnd();
        LogService().log('Diag', '缓冲结束');
        _cancelStallWatchdog();
      }
      if (event.newValue.test(AdapterMediaStatus.stalled)) {
        _diag.onStallStart('underflow');
        _diag.note('underflow(数据供给中断)');
        _startStallWatchdog();
      }
    });

    // 采集 mdk 运行时事件：缓冲进度、解码线程启停、解码错误、首帧
    // 事件 category/detail 的具体取值官方未完整文档化，因此原样记录 detail，
    // 便于拿到真机数据后确认语义。
    _eventSub = _player.onEvent.listen((event) {
      if (!mounted) return;
      switch (event.category) {
        case 'reader.buffering':
          // error 即缓冲进度 0-100，可区分网络慢与解码慢
          _bufProgress = event.error;
        case 'thread.video':
        case 'thread.audio':
        case 'render.video':
          _diag.addEvent(event.category, event.detail, event.error);
          if (event.detail.contains('error')) {
            LogService().log('Diag',
                '${event.category} 错误: ${event.detail} (${event.error})');
          }
        case 'decoder.video':
        case 'decoder.audio':
          // 拆出来单独处理：实际生效的解码框架即来自这两个事件
          _noteDecoderEvent(event);
          _diag.addEvent(event.category, event.detail, event.error);
          if (event.detail.contains('error')) {
            LogService().log('Diag',
                '${event.category} 错误: ${event.detail} (${event.error})');
          }
      }
    });

    // 定时更新播放位置（fvp 没有直接的 position stream）
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // 冻结兜底（v1.1.69 F-h；v1.2.14 修条件漏洞）：直写档（故障直写 /
      // 手动 surfaceViewDirect）下 fvp 未装 render callback，mdk renderer
      // 可能在等外部驱动（himi_logs_4：帧被内部 renderer 持续 not rendered
      // 丢弃、进度由音频时钟推进但画面冻结）。手动 renderVideo() 补充推进；
      // 无效时无副作用（空渲染一次）。旧条件写死 `output == 'surfaceView'`，
      // v1.2.11 新增 surfaceViewDirect 档后 10-bit 内容失去兜底 → 起播
      // 竞态下永久定格；现与视图 tunnel 参数共用 [surfaceViewDirectWrite]。
      if (_surfaceViewDirectWrite &&
          _player.state == AdapterPlaybackState.playing) {
        try {
          _player.renderVideo();
        } catch (_) {}
      }
      if (_isDraggingSlider || _isSeekingPlayback) {
        return; // 拖动/seek 中不更新，避免进度条回弹/跳回开头
      }
      final pos = _player.position;
      // 原生负值防御：seek 窗口/异常时 mdk position 可能返回 -1 等，
      // 不写入（跳过本 tick，等 seek 完成后回读同步）。
      if (pos < 0) return;
      if (pos > 0) _markPlaybackStarted();
      if (pos != _positionNotifier.value.inMilliseconds) {
        _position = Duration(milliseconds: pos);
        _positionNotifier.value = _position;
      }
      _evaluateSkipPrompt(pos);
      // 播完自动下一集兜底：仅服务不上报 end 位的引擎（media_kit/Erika）；
      // mdk 有 MediaStatus.end，走兜底会把拖进度条到结尾误判为播完切集。
      // seek 冷却期内同样忽略。
      final seekAt = _lastSeekCompletedAt;
      if (PlayerScreen.shouldAutoNextEpisode(
        positionMs: pos,
        durationMs: _duration.inMilliseconds,
        playing: _player.state == AdapterPlaybackState.playing,
        engineEmitsEnd: _currentEngine == PlayerEngine.mdk ||
            _currentEngine == PlayerEngine.mpv,
        seekCooldownActive: seekAt != null &&
            DateTime.now().difference(seekAt) <
                PlayerScreen.autoNextSeekCooldown,
      )) {
        unawaited(_handleEpisodeFinished(
          completedAtMs:
              _duration.inMilliseconds > 0 ? _duration.inMilliseconds : null,
        ));
      }
    });

    // 定时采集播放诊断数据
    _diagnosticTimer?.cancel();
    _diagnosticTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _queryDiagnostics();
    });

    // 250ms 轻量采样（时间线），捕捉亚秒级缓冲波动
    _sampleTimer?.cancel();
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _samplePlayback();
    });

    _syncDeepDiagnostics();
  }

  /// 深度诊断：开启 mdk log.status 以获取实测 fps / 缓存占用。
  ///
  /// mdk 未暴露任何统计回调，这是唯一途径。但 log.status 的行格式官方未文档化，
  /// 因此这里**原样保留**最近若干行原始文本，同时做防御式 fps 解析。
  /// 拿到真机数据后可据此精确化解析规则。
  ///
  /// 安全阀：单秒内保留行数超限则自动关闭，避免日志风暴影响播放。
  void _syncDeepDiagnostics() {
    // media_kit / Erika 档：mdk 深度诊断不可用（依赖 mdk.setGlobalOption/logHandler）
    if (_currentEngine == PlayerEngine.mediaKit ||
        _currentEngine == PlayerEngine.erika ||
        _currentEngine == PlayerEngine.mpv) {
      if (_deepLogActive) {
        _deepLogActive = false;
        _deepLogLines.clear();
        _deepNoteLines.clear();
        _stopDeepDiagnostics();
      }
      return;
    }
    final enabled = ref.read(settingsProvider).deepDiagnostics;
    if (enabled == _deepLogActive) {
      // 普通态常驻「EGL 检测」handler（幂等）：否则 3004 只会被
      // main 全局 handler 消费，本页面永不自愈（见 _resumeLogHandlerInstalled）。
      if (!enabled && !_resumeLogHandlerInstalled) {
        _installResumeLogHandler();
      }
      return;
    }
    if (enabled) {
      _startDeepDiagnostics();
    } else {
      _deepLogActive = false;
      _deepLogLines.clear();
      _deepNoteLines.clear();
      _stopDeepDiagnostics();
    }
  }

  void _startDeepDiagnostics() {
    try {
      _deepLogLines.clear();
      _deepNoteLines.clear();
      // 2 = 启用（不依赖 log level）
      mdk.setGlobalOption('log.status', 2);
      mdk.setLogHandler((level, message) {
        // EGL 故障检测与渲染风暴计数不受深诊开关影响（但丢帧行本身为
        // FINE 级，仍依赖 log.status=2 才产出）
        _feedEglDetector(message);
        _feedRenderStorm(message);
        if (!_deepLogActive) return;
        final line = message.trim();
        if (line.isEmpty) return;

        // 只保留两类行：mdk 状态行（含 fps/cache）与值得关注的关键行
        // （解码器选择、丢帧、错误等）。`buffering progress` 这类每数十毫秒
        // 一条的进度刷屏直接丢弃——它既无诊断价值，又无谓占用缓冲。
        final isStatus = _isStatusLine(line);
        if (!isStatus && !_isNotableLine(line)) return;

        if (isStatus) {
          // 速率安全阀只统计状态行。关键行在 prepare 阶段会突发上千行
          // （解码器初始化），若一并统计会在开启后 0.04 秒内误触发，
          // 导致深度诊断立刻关闭、一条数据都留不下。
          final now = DateTime.now();
          if (now.difference(_deepWindowStart) >=
              const Duration(milliseconds: 1000)) {
            _deepWindowStart = now;
            _deepPerSecond = 0;
          }
          _deepPerSecond++;
          if (_deepPerSecond > _deepLinesPerSecondLimit) {
            _deepLogActive = false;
            _stopDeepDiagnostics();
            _diag.note('状态行过密(>$_deepLinesPerSecondLimit 行/秒)，已自动关闭');
            LogService().log('Diag', '深度诊断日志过密，已自动关闭');
            return;
          }

          _deepLogLines.add(line);
          while (_deepLogLines.length > _deepStatusLineCap) {
            _deepLogLines.removeAt(0);
          }
          final fps = _parseFps(line);
          if (fps != null) _diag.updateFps(fps);

          // 视频缓存秒数：卡顿时是否归零是区分「网络喂不进」与
          // 「解码跟不上」的直接证据，一并进时间线。
          final cache = MdkLogParser.parseCacheSeconds(line);
          if (cache != null) _latestCacheSeconds = cache;
        } else {
          _deepNoteLines.add(line);
          while (_deepNoteLines.length > _deepNoteLineCap) {
            _deepNoteLines.removeAt(0);
          }
          // 关键行里可能带 mdk 实际创建的解码器名（真值），一并采集。
          _noteActualCodec(line);
          // 关键行同时转发到 LogService：面板「日志」区与 adb logcat
          // 都能实时看到（原实现只进内存导出，RenderAPI/Surface 这类
          // 黑屏定案证据无法从 logcat 观察）。
          LogService().log('mdk', line);
        }
      });
      _deepLogActive = true;
      // 深诊 handler 已接管，普通态标记作废（关深诊时会重挂）
      _resumeLogHandlerInstalled = false;
      _deepWindowStart = DateTime.now();
      _deepPerSecond = 0;
      LogService().log('Diag', '深度诊断已开启(log.status=2)');
    } catch (e) {
      LogService().log('Diag', '深度诊断开启失败: $e');
    }
  }

  /// 关闭 log.status 并恢复普通态的「EGL 检测」handler。
  /// 不用 setLogHandler(null)：fvp 启动时已注册自己的 handler，
  /// 置空会永久关闭 mdk 内部日志。
  void _stopDeepDiagnostics() {
    try {
      mdk.setGlobalOption('log.status', 0);
      _installResumeLogHandler();
    } catch (e) {
      LogService().log('Diag', '关闭深度诊断失败: $e');
    }
  }

  /// 挂普通态 handler（EGL 检测 + 渲染风暴计数 + error 转发）。
  /// 幂等；由 [_stopDeepDiagnostics] 与普通态 [_syncDeepDiagnostics] 共用。
  void _installResumeLogHandler() {
    try {
      mdk.setLogHandler((level, message) {
        _feedEglDetector(message);
        _feedRenderStorm(message);
        if (level == mdk.LogLevel.error) {
          LogService().log('mdk', message.trim());
        }
      });
      _resumeLogHandlerInstalled = true;
    } catch (e) {
      LogService().log('Diag', 'EGL 检测 handler 安装失败: $e');
    }
  }

  /// mdk 状态行解析委托给 [MdkLogParser]（纯 Dart，可单测）。
  ///
  /// 关键：媒体信息行也含 `fps: 24`，那是**声明帧率**，不随卡顿变化。
  /// 旧版正则不区分二者，导致面板永远显示 24fps，掩盖了真实的掉帧。
  static bool _isStatusLine(String line) => MdkLogParser.isStatusLine(line);

  static bool _isNotableLine(String line) => MdkLogParser.isNotableLine(line);

  static double? _parseFps(String line) => MdkLogParser.parseFps(line);

  /// 组装完整的诊断导出文本（时间线 + 卡顿 + 事件 + 媒体信息）。
  String _exportFullDiagnostics() {
    _diagTimeline = _diag.exportTimeline();
    _diagStalls = _diag.exportStalls();
    _diagNotes = _diag.exportNotes();
    final raw =
        _deepLogLines.isEmpty ? '(深度诊断未开启或无数据)' : _deepLogLines.join('\n');
    final notable = _deepNoteLines.isEmpty ? '(无)' : _deepNoteLines.join('\n');
    return DiagnosticExport.build(
      buildSummary: _buildSummary,
      diagSummary: _diagSummary,
      // 完整报告此前没有播放状态/帧率/码率段，补同一份快照，
      // 帧率/码率 0 时统一输出 `-`（与面板复制诊断一致）
      quickSnapshot: DiagnosticExport.buildQuick(
        playbackState: _playbackState,
        mediaStatus: _mediaStatusStr,
        position: DiagnosticExport.formatClock(_positionMs),
        duration: DiagnosticExport.formatClock(_durationMs),
        bufferedMs: _bufferedMs,
        mediaBitrate: _mediaBitrate,
        mediaFormat: _mediaFormat,
        videoCodec: _videoCodecName,
        videoResolution: _videoResolution,
        videoFps: _videoFps,
        videoBitrate: _videoBitrate,
        pixelFormat: _pixelFormat,
        doviProfile: _doviProfile,
        hdrType: _hdrType,
        audioCodec: _audioCodecName,
        audioSampleRate: _audioSampleRate,
        audioChannels: _audioChannels,
        audioBitrate: _audioBitrate,
        stereoDownmix: _stereoDownmix,
        audioFilter: _audioFilterText,
        textureId: _player.textureId.value,
        textureSize: _textureSizeText,
        videoFilter: _videoFilterText,
      ),
      decodeMode:
          AppSettings.decodeModeLabels[ref.read(settingsProvider).decodeMode] ??
              '-',
      videoOutput: _effectiveVideoOutput(),
      videoDecoders: _player.videoDecoders.join(','),
      isDolbyVisionContent: _embyVideoStream?.isDolbyVision == true,
      dvCapability: _dvProbe.summary,
      decoderReport: _decoderReport,
      mdkRawDecoder: _mdkRawDecoder,
      bufProgress: _bufProgress,
      timeline: _diagTimeline,
      stalls: _diagStalls,
      events: _diag.exportEvents(),
      notes: _snapshotInfo == null
          ? _diagNotes
          : '$_diagNotes\n截帧: $_snapshotInfo',
      statusLines: raw,
      notableLines: notable,
    );
  }

  void _autoSelectDefaultTracks() {
    // 详情页预选（字幕/音轨选择器）优先：消费后清空，下次切集回退默认
    final pending = ref.read(pendingTrackSelectionProvider);
    if (pending != null) {
      ref.read(pendingTrackSelectionProvider.notifier).state = null;
      final resolved = resolveInitialTracks(
        pending: pending,
        audioStreams: _embyAudioStreams,
        subtitleStreams: _embySubtitleStreams,
      );
      if (resolved != null) {
        if (resolved.applySubtitle) {
          final pos = resolved.subtitlePosition;
          if (pos == null) {
            // 预选「关闭字幕」
            _player.activeSubtitleTracks = [];
            _activeSubtitleIndex = null;
            _activeLocalSubtitlePath = null;
            _subtitleDelayReloadTimer?.cancel();
          } else {
            // 复用面板选择逻辑（含外挂轨 setMedia 分支）
            _selectEmbySubtitle(pos);
          }
        } else {
          // 字幕预选未匹配到轨 → 回退现状默认
          _selectDefaultEmbeddedSubtitle();
        }

        if (resolved.applyAudio && resolved.audioPosition != null) {
          _player.activeAudioTracks = [resolved.audioPosition!];
          _applyAudioFilterPolicy();
        } else if (_embyDefaultAudioIndex != null) {
          final embyIdx = _embyAudioStreams.indexWhere(
            (s) => s.index == _embyDefaultAudioIndex!,
          );
          if (embyIdx >= 0) {
            _player.activeAudioTracks = [embyIdx];
            _applyAudioFilterPolicy();
          }
        }
        // 字幕轨已定型：延迟 ≠0 时立即套用（偏移重载）
        _maybeApplySubtitleDelay(immediate: true);
        return;
      }
      // resolved == null：预选全部未匹配，落回下方默认逻辑
    }

    // fvp: 自动选择第一个字幕轨道
    _selectDefaultEmbeddedSubtitle();

    if (_embyDefaultAudioIndex != null) {
      final embyIdx = _embyAudioStreams.indexWhere(
        (s) => s.index == _embyDefaultAudioIndex!,
      );
      if (embyIdx >= 0) {
        _player.activeAudioTracks = [embyIdx];
      }
    }
    // 音轨编码此时才随 mediaInfo 可得，按策略刷新滤镜
    _applyAudioFilterPolicy();
    _maybeApplySubtitleDelay(immediate: true);
  }

  /// 默认激活第一条字幕轨并同步面板选中态：
  /// `_activeSubtitleIndex` 记 Emby 流 index（面板高亮与延迟重载取源用）。
  /// 若首条为外挂字幕，走 `_selectEmbySubtitle`（需 setMedia 加载外部文件），
  /// 否则用内嵌轨 0。
  void _selectDefaultEmbeddedSubtitle() {
    if (_embySubtitleStreams.isNotEmpty) {
      final first = _embySubtitleStreams.first;
      if (first.isExternal || first.subtitleLocationType == 'ExternalStream') {
        _selectEmbySubtitle(0);
        return;
      }
    }
    _player.activeSubtitleTracks = [0];
    _activeSubtitleIndex =
        _embySubtitleStreams.isNotEmpty ? _embySubtitleStreams[0].index : null;
    _activeLocalSubtitlePath = null;
    _applySubtitleStyle();
  }

  void _refreshTracks() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (!_subtitleAutoSelected) {
        _subtitleAutoSelected = true;
        _autoSelectDefaultTracks();
      }
    });
  }

  void _setupRoomSync() async {
    if (_roomSyncInitializing) return;
    _roomSyncInitializing = true;

    // 平台能力检查：macOS/Linux 无 agora_rtm 原生实现，Windows 走
    // himi_windows_rtm；不支持时明确提示，避免静默卡死
    final rtmService = ref.read(rtmServiceProvider);
    if (!rtmService.isSupported) {
      _roomSyncInitializing = false;
      if (!mounted) return;
      setState(() => _syncRtmStatus = '不支持此平台');
      _logSyncEvent('当前平台不支持房间同步信令');
      showAppToast(context, '当前平台暂不支持房间同步');
      return;
    }

    // 仅主持人需要检查声网配置
    if (_isHost) {
      final agoraConfig = ref.read(agoraConfigProvider);
      if (agoraConfig == null || !agoraConfig.isConfigured) {
        _roomSyncInitializing = false;
        if (mounted) {
          showAppToast(context, '声网未配置');
        }
        return;
      }
    }

    _roomData ??= RoomCode.decode(widget.roomCode!);
    if (_roomData == null) {
      _roomSyncInitializing = false;
      if (mounted) {
        showAppToast(context, '房间码无效');
      }
      return;
    }

    _rtmChannel = _roomData!['channel'] as String?;
    _rtmAppId = _roomData!['appId'] as String?;

    if (_rtmChannel == null || _rtmAppId == null) {
      _roomSyncInitializing = false;
      if (mounted) {
        showAppToast(context, '房间数据不完整');
      }
      return;
    }

    // Host: 使用自己的 userId 初始化; Audience: 从 token 中获取 tokenId
    String? loginToken;
    String rtmUserId;

    if (_isHost) {
      rtmUserId = _myUserId!;
      await rtmService.initialize(
        appId: _rtmAppId!,
        userId: rtmUserId,
      );
      final agoraConfig = ref.read(agoraConfigProvider)!;
      loginToken = RtmTokenBuilder.buildToken(
        appId: _rtmAppId!,
        appCertificate: agoraConfig.appCertificate,
        userId: rtmUserId,
        tokenExpireSeconds: 86400,
      );
    } else {
      final tokenData = RoomCode.consumeToken(_roomData!);
      if (tokenData == null) {
        _roomSyncInitializing = false;
        if (mounted) {
          showAppToast(context, '无可用水_token');
        }
        return;
      }
      rtmUserId = tokenData['tokenId'] as String;
      loginToken = tokenData['token'] as String;

      await rtmService.initialize(
        appId: _rtmAppId!,
        userId: rtmUserId,
      );
    }

    final loginOk = await rtmService.login(_rtmAppId!, token: loginToken);
    if (!loginOk) {
      _roomSyncInitializing = false;
      if (!mounted) return;
      setState(() => _syncRtmStatus = '登录失败');
      _logSyncEvent('RTM 登录失败');
      if (mounted) {
        showAppToast(context, 'RTM 登录失败，请检查声网配置');
      }
      return;
    }
    final subscribeOk = await rtmService.subscribe(_rtmChannel!);
    if (!subscribeOk) {
      _roomSyncInitializing = false;
      if (!mounted) return;
      setState(() => _syncRtmStatus = '订阅失败');
      _logSyncEvent('RTM 订阅失败');
      if (mounted) {
        showAppToast(context, 'RTM 频道订阅失败，请检查网络');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _syncRtmChannel = _rtmChannel ?? '-';
      _syncRtmStatus = '已连接';
    });
    _logSyncEvent('RTM 已连接, 频道: $_rtmChannel');

    // 观众：检测频道内是否有人（房主是否在线）
    if (!_isHost) {
      final onlineCount = await rtmService.getOnlineUserCount(_rtmChannel!);
      _logSyncEvent('频道在线人数: $onlineCount');
      if (onlineCount == 0) {
        _logSyncEvent('频道无人在线，房间已解散');
        _showRoomDestroyedDialog();
        return;
      }
      // 启动 roomInfo 等待超时（10 秒）
      _roomInfoTimeout?.cancel();
      _roomInfoTimeout = Timer(const Duration(seconds: 10), () {
        if (mounted && !_hasReceivedRoomInfo) {
          _logSyncEvent('等待 roomInfo 超时，房间可能已解散');
          _showRoomDestroyedDialog();
        }
      });
    }

    // 元数据自检（延迟 1 秒等 channel 稳定）
    Future.delayed(const Duration(seconds: 1), () async {
      if (!mounted || _rtmChannel == null) return;
      final rtmService = ref.read(rtmServiceProvider);
      final result = await rtmService.testMetadata(_rtmChannel!);
      if (mounted) {
        setState(() {
          _syncMetadataTestResult = result;
        });
        _logSyncEvent('元数据自检: $result');
      }
    });

    // 1. 设置消息监听器（subscribe 之后立即设置，确保不丢消息）
    LogService().log('Room',
        '${_isHost ? "主持人" : "观众"} 设置消息监听器, userId=$_myUserId, channel=$_rtmChannel, episodes=${_episodes.length}');
    _rtmSubscription = rtmService.messageStream.listen((message) async {
      if (!mounted) return;
      final senderId = message['userId'];
      if (senderId == _myUserId) return;

      final type = message['type'];
      LogService().log('Room', '收到消息 type=$type, sender=$senderId');
      if (type == AppConstants.msgTypeHeartbeat) {
        _handleHeartbeat(message);
      } else if (type == AppConstants.msgTypeRoomInfo) {
        LogService().log('Room',
            '收到 roomInfo, episodeIds=${message['episodeIds']?.length ?? 0}');
        _logSyncEvent('收到 roomInfo (${message['episodeIds']?.length ?? 0}集)');
        _handleRoomInfo(message);
      } else if (type == AppConstants.msgTypeCommand) {
        final action = message['action'] as String?;
        LogService().log('Room', '收到命令 action=$action');
        if (action == 'join') {
          final name = message['userName'] as String? ?? '观众';
          _addBroadcastMessage('$name 加入了房间');
          _logSyncEvent('$name 加入房间');
          _countRetryScheduler.restart();
          // 主持人发送房间信息（含媒体数据 + 剧集列表 + playUrl）
          if (_isHost) {
            LogService().log(
                'Room', '主持人发送 roomInfo, episodeCount=${_episodes.length}');
            await _broadcastRoomInfo();
            // 主持人发送当前播放状态（同步播放进度）
            if (_isPlayerReady &&
                _currentEpisodeIndex >= 0 &&
                _currentEpisodeIndex < _episodes.length) {
              final position = _player.position / 1000.0;
              LogService().log('Room',
                  '主持人发送 syncPlay: episode=$_currentEpisodeIndex, pos=$position');
              await rtmService.sendCommand(
                action: AppConstants.actionSyncPlay,
                episodeIndex: _currentEpisodeIndex,
                itemId: _episodes[_currentEpisodeIndex].id,
                position: position,
                playUrl: _currentPlayUrl,
                token: _currentToken,
                subtitleStreams:
                    _embySubtitleStreams.map((s) => s.toJson()).toList(),
                audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
                videoStream: _embyVideoStream?.toJson(),
                defaultAudioStreamIndex: _embyDefaultAudioIndex,
              );
            }
          }
        } else if (action == 'leave') {
          final name = message['userName'] as String? ?? '观众';
          _addBroadcastMessage('$name 离开了房间');
          _countRetryScheduler.restart();
        } else if (action == AppConstants.actionRequestRoomInfo) {
          if (_isHost) {
            _broadcastRoomInfo();
          }
        } else if (action == AppConstants.actionTimePing) {
          // 观众时钟校准探测：房主回显 t1 并附本机发送时刻 t2
          if (_isHost) {
            final t1 = message['t1'];
            if (t1 is int) {
              rtmService.sendTimePong(
                  t1, DateTime.now().millisecondsSinceEpoch);
            }
          }
        } else if (action == AppConstants.actionTimePong) {
          // 观众收到 pong：t1(本机发出)/t2(房主发出)/t4(本机收到)
          if (!_isHost) {
            final t1 = message['t1'];
            final t2 = message['t2'];
            if (t1 is int && t2 is int) {
              final wasCalibrated = _clockOffset.isCalibrated;
              _clockOffset.addSample(
                t1: t1,
                t2: t2,
                t4: DateTime.now().millisecondsSinceEpoch,
              );
              if (mounted) setState(() {});
              if (!wasCalibrated && _clockOffset.isCalibrated) {
                _logSyncEvent('时钟校准完成: 偏移='
                    '${_clockOffset.offsetMs!.toStringAsFixed(0)}ms, '
                    'RTT=${_clockOffset.bestRttMs}ms');
              }
            }
          }
        } else {
          _handleCommand(message);
        }
      }
    });

    // 2. 监听 Presence 事件（在线人数变化）
    _presenceSubscription = rtmService.presenceStream.listen((event) async {
      if (mounted && !_isHost && _hostUserId != null) {
        final type = event['type'];
        final publisher = event['publisher'] as String?;
        if (publisher == _hostUserId &&
            (type == RtmPresenceEventType.remoteLeaveChannel ||
                type == RtmPresenceEventType.remoteTimeout)) {
          _showRoomDestroyedDialog();
          return;
        }
      }
      if (mounted) {
        _countRetryScheduler.restart();
      }
    });

    // 3. 发送 join 命令（通知已在频道的人）
    _addBroadcastMessage('${_audienceName} 加入了房间');
    rtmService.sendJoinLeave(
      action: 'join',
      userName: _audienceName!,
    );

    // 初始化在线人数（自己）
    _onlineUserCount = 1;
    if (mounted) setState(() {});

    // 延迟刷新在线人数（等待 RTM presence 同步）
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _refreshOnlineCount(rtmService);
      }
    });

    // 主持人开始心跳
    if (_isHost) {
      _startHeartbeat();
    } else {
      // 观众启动时钟校准（消除跨设备系统时钟差导致的进度恒定偏差）
      _startClockSync();
    }
  }

  void _refreshOnlineCount(RtmService rtmService) async {
    if (_rtmChannel == null) return;
    final count = await rtmService.getOnlineUserCount(_rtmChannel!);
    if (mounted) {
      setState(() {
        _onlineUserCount = count;
      });
      _logSyncEvent('在线人数更新: $count');
      LogService().log('Room', '在线人数更新: $count, channel: $_rtmChannel');
    }
  }

  /// 成员变化（join/leave/presence）后的重查序列：
  /// presence 同步延迟由 1s/2s/3s/5s 兜底重查覆盖，新事件重排序列。
  late final CountRetryScheduler _countRetryScheduler = CountRetryScheduler(
    delaysSec: const [1, 2, 3, 5],
    onTick: () {
      if (mounted) {
        _refreshOnlineCount(ref.read(rtmServiceProvider));
      }
    },
  );

  void _handleHeartbeat(Map<String, dynamic> message) {
    if (_isHost) return;
    if (_syncPaused) return;
    if (_isSyncing) return;
    // fvp: 检查是否在缓冲中
    if (_player.mediaStatus.test(AdapterMediaStatus.buffering)) return;
    if (_player.mediaStatus.test(AdapterMediaStatus.seeking)) return;

    final position = (message['position'] as num?)?.toDouble() ?? 0.0;
    final playing = message['playing'] as bool? ?? false;
    final rate = (message['rate'] as num?)?.toDouble() ?? 1.0;
    final timestamp = message['ts'] as int? ?? 0;

    // 用时钟校准把房主时间戳换算到本机时钟，再算流逝时间；未校准时
    // 回退旧行为（两机假设同钟，等效 offset=0）。
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = nowMs + (_clockOffset.offsetMs ?? 0) - timestamp;
    final elapsed = elapsedMs / 1000.0;
    final expectedPos = position + (elapsed * rate);

    final currentPos = _player.position / 1000.0;
    final diff = (expectedPos - currentPos).abs();

    if (diff < AppConstants.syncThresholdMicro) {
      // 差值 < 0.3s，不做操作
    } else if (diff < AppConstants.syncThresholdMedium) {
      _rateRestoreTimer?.cancel();
      _player.playbackRate = 1.02;
      _rateRestoreTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _player.playbackRate = rate;
      });
    } else {
      // seek 防抖：距上次 seek 不足 2 秒则跳过
      if (_lastSeekTime != null &&
          DateTime.now().difference(_lastSeekTime!).inMilliseconds < 2000) {
        return;
      }
      _lastSeekTime = DateTime.now();
      try {
        _player.seek(positionMs: (expectedPos * 1000).toInt());
      } catch (_) {}
    }

    // 主持人控制播放/暂停状态
    if (playing && _player.state != AdapterPlaybackState.playing) {
      _player.state = AdapterPlaybackState.playing;
      _syncPlayState();
    } else if (!playing && _player.state == AdapterPlaybackState.playing) {
      _player.state = AdapterPlaybackState.paused;
      _syncPlayState();
    }
  }

  void _handleCommand(Map<String, dynamic> message) {
    final action = message['action'] as String?;
    if (action == null) return;

    _syncPaused = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _syncPaused = false;
    });

    switch (action) {
      case AppConstants.actionPlay:
        _player.state = AdapterPlaybackState.playing;
        _syncPlayState();
        break;
      case AppConstants.actionPause:
        _player.state = AdapterPlaybackState.paused;
        _syncPlayState();
        break;
      case AppConstants.actionSeek:
        final pos = (message['position'] as num?)?.toDouble() ?? 0.0;
        try {
          _player.seek(positionMs: (pos * 1000).toInt());
        } catch (_) {}
        break;
      case AppConstants.actionRate:
        final r = (message['rate'] as num?)?.toDouble() ?? 1.0;
        _player.playbackRate = r;
        break;
      case AppConstants.actionSyncPlay:
        final position = (message['position'] as num?)?.toDouble() ?? 0.0;
        final playUrl = message['playUrl'] as String?;
        final token = message['token'] as String?;
        final epIndex = message['episodeIndex'] as int?;
        _logSyncEvent(
            '收到 syncPlay, pos=${position.toStringAsFixed(1)}s, urlLen=${playUrl?.length ?? 0}');
        // 流随 syncPlay 下发（C3）：roomInfo 丢失/晚到时仍能拿到字幕音轨
        _applyStreamsFromRoomInfo(message);
        // 与 roomInfo 路径同款去重（v1.2.7 修 HDR 观众黑屏）：房主 join 时
        // 先 roomInfo(带 URL) 后 syncPlay(同 URL)，两条都会触发起播 → 并发
        // media=/prepare/引擎重建 → 竞态黑屏。_playFromUrl 入口已同步写入
        // _currentPlayUrl，故同 URL 的后续消息在此被拦截。
        if (playUrl != null &&
            PlayerScreen.shouldStartAudiencePlay(
              playUrl: playUrl,
              currentPlayUrl: _currentPlayUrl,
              inFlightPlayUrl: _inFlightPlayUrl,
            )) {
          _playFromUrl(
              playUrl: playUrl,
              token: token ?? '',
              position: position,
              epIndex: epIndex);
        } else if (playUrl != null && playUrl.isNotEmpty) {
          _logSyncEvent('syncPlay 同 URL 已就绪，跳过重复起播');
        }
        break;
      case AppConstants.actionRemoveEpisode:
        final epIndex = message['episodeIndex'] as int?;
        if (epIndex != null) {
          _removeEpisode(epIndex, sendRtm: false);
        }
        break;
      case AppConstants.actionAddResource:
        _handleAddResource(message);
        break;
      case AppConstants.actionRoomDestroyed:
        _showRoomDestroyedDialog();
        break;
    }
  }

  /// 房主向房间广播完整 roomInfo（媒体数据 + 剧集列表 + playUrl + 流）。
  /// 起播/切集/收到请求时调用；流晚于列表就绪时靠它补齐观众侧字幕音轨。
  Future<void> _broadcastRoomInfo() async {
    if (!_isHost || _rtmChannel == null) return;
    try {
      await ref.read(rtmServiceProvider).sendRoomInfo(
            channelName: _rtmChannel!,
            serverId: widget.serverId,
            mediaItemId: RoomInfoCodec.normalizeMediaItemId(widget.itemId),
            mediaSourceId: widget.mediaSourceId,
            mediaItemName: _episodes.isNotEmpty ? _episodes.first.name : null,
            seriesName: _seriesName,
            episodeIds: _episodes.map((e) => e.id).toList(),
            episodeNames: _episodes.map((e) => e.name).toList(),
            episodeSeasons: _episodes.map((e) => e.season).toList(),
            episodeNumbers: _episodes.map((e) => e.number).toList(),
            episodePosters: _episodes.map((e) => e.poster).toList(),
            episodeSeriesNames: _episodes.map((e) => e.seriesName).toList(),
            // 逐集版本：观众按索引对齐应用
            episodeMediaSourceIds:
                _episodes.map((e) => e.mediaSourceId).toList(),
            playUrl: _currentPlayUrl,
            token: _currentToken,
            subtitleStreams:
                _embySubtitleStreams.map((s) => s.toJson()).toList(),
            audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
            videoStream: _embyVideoStream?.toJson(),
            defaultAudioStreamIndex: _embyDefaultAudioIndex,
          );
    } catch (e) {
      LogService().log('Room', '_broadcastRoomInfo 失败: $e');
    }
    LogService().log('Room',
        '_broadcastRoomInfo 已发: 集=${_episodes.length}, 字幕=${_embySubtitleStreams.length}, 音轨=${_embyAudioStreams.length}, urlLen=${_currentPlayUrl.length}');
  }

  void _handleRoomInfo(Map<String, dynamic> message) {
    if (_isHost) return;

    // 收到 roomInfo，取消超时
    _hasReceivedRoomInfo = true;
    _roomInfoTimeout?.cancel();

    // 记录房主 userId（用于 Presence 检测房主离线）
    final hostId = message['userId'] as String?;
    if (hostId != null && hostId.isNotEmpty) {
      _hostUserId = hostId;
    }

    LogService().log('Room', '_handleRoomInfo: keys=${message.keys.toList()}');

    // 1. 剧集/单集列表：仅首次构建。房主起播后可能再次广播 roomInfo，
    //    此时列表已存在，不应重建（否则会打断正在播放的选集状态）。
    if (!_hasEpisodeList) {
      _buildEpisodeListFromRoomInfo(message);
    }

    // 2. 字幕/音轨/视频流：每次都刷新。修核心 bug——观众早于房主起播
    //    进入时，首条 roomInfo 流字段为空；房主随后重广播才带流，必须
    //    在列表已建的情况下仍应用流。
    _applyStreamsFromRoomInfo(message);

    // 3. playUrl：仅当与当前播放地址不同才起播（避免重复 roomInfo 重启）
    final playUrl = message['playUrl'] as String?;
    final token = message['token'] as String?;
    if (playUrl != null &&
        PlayerScreen.shouldStartAudiencePlay(
          playUrl: playUrl,
          currentPlayUrl: _currentPlayUrl,
          inFlightPlayUrl: _inFlightPlayUrl,
        )) {
      _playFromUrl(playUrl: playUrl, token: token ?? '');
    }
  }

  /// 用 roomInfo 构建剧集/单集列表（仅首次调用生效）。
  void _buildEpisodeListFromRoomInfo(Map<String, dynamic> message) {
    final epIds = message['episodeIds'];
    final roomServerId = message['serverId'] as String?;
    LogService().log('Room',
        '_handleRoomInfo: epIds type=${epIds.runtimeType}, len=${epIds is List ? epIds.length : "N/A"}');
    if (epIds is List && epIds.isNotEmpty) {
      // 电视剧：接收完整剧集列表
      final names = List<String>.from(message['episodeNames'] ?? []);
      final seasons = List<int>.from(message['episodeSeasons'] ?? []);
      final numbers = List<int>.from(message['episodeNumbers'] ?? []);
      final posters = List<String>.from(message['episodePosters'] ?? []);
      final seriesNames =
          List<String>.from(message['episodeSeriesNames'] ?? []);
      // 逐集版本（与 episodeIds 索引对齐，缺省 null = 默认版本）
      final sourceIdsRaw = message['episodeMediaSourceIds'];
      final sourceIds = sourceIdsRaw is List
          ? List<dynamic>.from(sourceIdsRaw)
          : const <dynamic>[];
      setState(() {
        _episodes = List.generate(
            epIds.length,
            (i) => EpisodeInfo(
                  id: epIds[i] as String? ?? '',
                  name: i < names.length ? names[i] : '',
                  season: i < seasons.length ? seasons[i] : 0,
                  number: i < numbers.length ? numbers[i] : 0,
                  poster: i < posters.length ? posters[i] : '',
                  seriesName: i < seriesNames.length ? seriesNames[i] : '',
                  mediaSourceId:
                      i < sourceIds.length ? sourceIds[i] as String? : null,
                  serverId: roomServerId,
                ));
        _seriesName = message['seriesName'] ?? '';
        _hasEpisodeList = true;
      });
    } else {
      // 电影：用 mediaItemId 构建单集（过滤占位符 `_`，防空房间凭空建条目）
      final mediaItemId =
          RoomInfoCodec.normalizeMediaItemId(message['mediaItemId'] as String?);
      final mediaItemName = message['mediaItemName'] as String?;
      if (mediaItemId != null) {
        setState(() {
          _episodes = [
            EpisodeInfo(
              id: mediaItemId,
              name: mediaItemName ?? '电影',
              serverId: roomServerId,
            )
          ];
          _seriesName = '';
          _hasEpisodeList = true;
        });
      }
    }
    if (_hasEpisodeList) {
      _rebuildGroups();
      _addBroadcastMessage('已同步房间资源列表');
    }
  }

  /// 应用 roomInfo 中的流信息（每次调用都生效，流变化时重新选轨）。
  void _applyStreamsFromRoomInfo(Map<String, dynamic> message) {
    final subtitleStreamsRaw = message['subtitleStreams'];
    final audioStreamsRaw = message['audioStreams'];
    if (subtitleStreamsRaw is List) {
      _embySubtitleStreams = subtitleStreamsRaw
          .whereType<Map<String, dynamic>>()
          .map((s) => MediaStream.fromJson(s))
          .toList();
    }
    if (audioStreamsRaw is List) {
      _embyAudioStreams = audioStreamsRaw
          .whereType<Map<String, dynamic>>()
          .map((s) => MediaStream.fromJson(s))
          .toList();
    }
    // 接收视频流信息（用于 DV 检测）
    final videoStreamRaw = message['videoStream'];
    if (videoStreamRaw is Map<String, dynamic>) {
      _embyVideoStream = MediaStream.fromJson(videoStreamRaw);
      // 房间观众：元数据到达 → 复核 HDR（自动路由依据）
      _refreshHdrContent();
    }
    _embyDefaultAudioIndex = message['defaultAudioStreamIndex'] as int?;
    LogService().log('Room',
        '字幕=${_embySubtitleStreams.length}条, 音轨=${_embyAudioStreams.length}条, 视频=${_embyVideoStream?.codec ?? "无"}');

    // 流晚到/变更：允许重新自动选轨（修「观众菜单全空」）
    final signature = '${_embySubtitleStreams.length}/'
        '${_embyAudioStreams.length}/${_embyDefaultAudioIndex ?? "x"}';
    if (signature != _remoteStreamSignature) {
      _remoteStreamSignature = signature;
      _subtitleAutoSelected = false;
      _refreshTracks();
    }

    // 观众：流仍为空则退避重试请求 roomInfo（房主可能还没起播）
    _scheduleStreamRetry();
  }

  /// 观众侧字幕/音轨都为空时，按退避（2/4/8/16s，最多 6 次）重请求 roomInfo。
  void _scheduleStreamRetry() {
    if (_isHost) return;
    if (_embySubtitleStreams.isNotEmpty || _embyAudioStreams.isNotEmpty) {
      _stopStreamRetry();
      return;
    }
    if (_streamRequestAttempts >= 6) return;
    final delaySec = 2 << _streamRequestAttempts.clamp(0, 4);
    _streamRequestAttempts++;
    _streamRequestTimer?.cancel();
    _streamRequestTimer = Timer(Duration(seconds: delaySec), () {
      if (!mounted) return;
      _logSyncEvent('观众流为空，重请求 roomInfo (#$_streamRequestAttempts)');
      ref.read(rtmServiceProvider).sendRequestRoomInfo();
      _scheduleStreamRetry();
    });
  }

  void _stopStreamRetry() {
    _streamRequestTimer?.cancel();
    _streamRequestTimer = null;
    _streamRequestAttempts = 0;
  }

  void _showRoomDestroyedDialog() {
    _heartbeatTimer?.cancel();
    _stopClockSync();
    _player.state = AdapterPlaybackState.stopped;
    _syncPlayState();
    if (_rtmChannel != null) {
      try {
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.unsubscribe(_rtmChannel!);
      } catch (_) {}
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('房间已解散'),
        content: const Text('房主已离开，房间已解散'),
      ),
    );
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Future<bool> _confirmLeaveRoom() async {
    if (!_isHost || widget.roomCode == null) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散房间'),
        content: const Text('离开将解散当前房间，所有观众将被退出。确定离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            // TV 模式：打开即聚焦确认键，遥控器 OK 一步完成确认
            autofocus: ref.read(settingsProvider.select((s) => s.tvMode)),
            child: const Text('确定离开'),
          ),
        ],
      ),
    );
    if (result == true && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      await rtmService.sendJoinLeave(
        action: AppConstants.actionRoomDestroyed,
        userName: _audienceName ?? '房主',
      );
      await rtmService.sendJoinLeave(
        action: AppConstants.actionRoomDestroyed,
        userName: _audienceName ?? '房主',
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return result ?? false;
  }

  void _addBroadcastMessage(String msg) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _broadcastMessages.add('[$time] $msg');
    _broadcastVersion.value++;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_broadcastScrollController.hasClients) {
        _broadcastScrollController.animateTo(
          _broadcastScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  int get _totalEpisodeCount => _episodes.length;

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.rtmHeartbeatIntervalMs),
      (_) {
        if (!mounted || _player.state != AdapterPlaybackState.playing) return;
        final rtmService = ref.read(rtmServiceProvider);
        rtmService.sendHeartbeat(
          position: _player.position / 1000.0,
          playing: _player.state == AdapterPlaybackState.playing,
          rate: _player.playbackRate,
        );
      },
    );
  }

  /// 观众启动时钟校准：连上即探一次，未校准前每 3s 重试，校准后每 30s 复核。
  void _startClockSync() {
    _stopClockSync();
    _sendClockPing();
    _scheduleClockSync();
  }

  void _sendClockPing() {
    if (!mounted) return;
    ref
        .read(rtmServiceProvider)
        .sendTimePing(DateTime.now().millisecondsSinceEpoch);
  }

  void _scheduleClockSync() {
    final period = _clockOffset.isCalibrated
        ? AppConstants.clockSyncIntervalMs
        : AppConstants.clockSyncRetryMs;
    _clockPingTimer = Timer(Duration(milliseconds: period), () {
      if (!mounted) return;
      _sendClockPing();
      _scheduleClockSync();
    });
  }

  void _stopClockSync() {
    _clockPingTimer?.cancel();
    _clockPingTimer = null;
    _clockOffset.reset();
  }

  void _sendCommand(String action, {double? position, double? rate}) {
    final rtmService = ref.read(rtmServiceProvider);
    rtmService.sendCommand(
      action: action,
      position: position,
      rate: rate,
    );
  }

  void _togglePlayPause() {
    if (_player.state == AdapterPlaybackState.playing) {
      _player.state = AdapterPlaybackState.paused;
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPause);
      }
    } else {
      _player.state = AdapterPlaybackState.playing;
      // 回前台重载后恢复到暂停态的管线：恢复播放前对当前进度 seek 一次，
      // 强制重新驱动解码（否则可能「有图标无画面/无响应」）。
      if (_pendingResumeSeek) {
        _pendingResumeSeek = false;
        final pos = _player.position;
        if (pos > 0) unawaited(_reengageAfterResume(pos));
      }
      if (widget.roomCode != null) {
        _sendCommand(AppConstants.actionPlay);
      }
    }
    _syncPlayState();
    unawaited(_reportProgress());
  }

  /// 回前台重载后恢复播放的兜底：对 [pos] 做一次 keyFrame seek，
  /// 让 mdk 重新从当前位置驱动解码出帧。
  Future<void> _reengageAfterResume(int pos) async {
    if (!mounted) return;
    try {
      await _player.seek(positionMs: pos);
    } catch (_) {}
  }

  /// 空格键播放/暂停（仅房主/本地可控制）
  void _handleHotkeyTogglePlayPause() {
    if (_lockController.locked) return;
    if (!_canControlPlayback) return;
    _resetHideTimer();
    _togglePlayPause();
  }

  /// 切换窗口全屏（桌面），读回真实状态刷新图标
  Future<void> _toggleWindowFullscreen() async {
    await _windowFullscreenService.setFullScreen(!_isWindowFullscreen);
    final now = await _windowFullscreenService.isFullScreen();
    if (mounted) setState(() => _isWindowFullscreen = now);
  }

  /// 退出窗口全屏（ESC 热键入口；非全屏时为空操作）
  Future<void> _exitWindowFullscreen() async {
    if (!_isWindowFullscreen) return;
    await _windowFullscreenService.setFullScreen(false);
    if (mounted) setState(() => _isWindowFullscreen = false);
  }

  /// 音量键：±5% 应用内音量，并显示左侧音量柱 1 秒
  void _handleHotkeyVolumeDelta(double deltaPercent) {
    if (_lockController.locked) return;
    _resetHideTimer();
    final newVol = (_volume + deltaPercent).clamp(0.0, 100.0);
    _volume = newVol;
    _player.volume = newVol / 100.0;
    _volumeNotifier.value = newVol;
    _showVolumeBarNotifier.value = true;
    _showBrightnessBarNotifier.value = false;
    _startGestureBarTimer();
  }

  void _syncPlayState() {
    final playing = _player.state == AdapterPlaybackState.playing;
    if (playing) _markPlaybackStarted();
    if (_isPlayingNotifier.value != playing) {
      _isPlayingNotifier.value = playing;
      // 开播边沿重启自动隐藏计时：初进计时若在加载期（非 playing）烧掉，
      // 此后无人续期 → 控件常显；此处保证"播放中 5 秒隐藏"始终成立。
      if (playing) _resetHideTimer();
    }
  }

  // ---- Emby 播放会话上报（续播/自动已观看，仅单人/房主）----

  bool get _shouldReportPlayback => widget.roomCode == null;

  /// 初始终点尚未被引擎确认时，避免把 0 写回服务器清掉续播。
  int get _reportPosition {
    final enginePosition = _player.position;
    if (enginePosition > 0) return enginePosition;
    return _position.inMilliseconds > 0 ? _position.inMilliseconds : 0;
  }

  Future<void> _reportStart() async {
    final svc = _reportService;
    final id = _reportItemId;
    if (!_shouldReportPlayback || svc == null || id == null) return;
    _reportStarted = true;
    await svc.reportPlaybackStart(
      itemId: id,
      playSessionId: _playSessionId,
      mediaSourceId: _reportMediaSourceId,
      positionMs: _reportPosition,
    );
    _startReportTimer();
  }

  Future<void> _reportProgress() async {
    final svc = _reportService;
    final id = _reportItemId;
    if (!_shouldReportPlayback ||
        !_reportStarted ||
        svc == null ||
        id == null) {
      return;
    }
    final ok = await svc.reportPlaybackProgress(
      itemId: id,
      playSessionId: _playSessionId,
      mediaSourceId: _reportMediaSourceId,
      positionMs: _reportPosition,
      isPaused: _player.state == AdapterPlaybackState.paused,
    );
    // 进度变化即刷新续播栏（节流 ≤1 次/2s）
    if (ok && mounted) {
      _reportFailCount = 0;
      // 首个成功上报后解除「重播乐观隐藏」，交回服务器真相（自动回填新进度）
      _clearResumeHidden(id);
      _bumpResumeThrottled();
    } else if (!ok) {
      _reportFailCount++;
      if (_reportFailCount >= 2) {
        unawaited(_maybeFailover('进度上报'));
      }
    }
  }

  /// 播放中故障转移（v1.1.242）：API 报错/取流失败/流无效时
  /// 若当前线路不可达则切到延迟最低可达线路并复播。
  /// 单次播放只自动切 1 次（`_failoverAttempted`，换集重置）。
  Future<void> _maybeFailover(String reason) async {
    if (!mounted || _failoverAttempted || _failoverInFlight) return;
    // 仅房主/单人模式处理；观众跟随房主
    if (!_isHost && widget.roomCode != null) return;
    final config = ref.read(embyConfigForProvider(widget.serverId));
    if (config == null || !config.autoFailover || config.routes.isEmpty) {
      return;
    }
    _failoverInFlight = true;
    try {
      final switched =
          await ref.read(serverRouteServiceProvider).failoverIfNeeded(config);
      if (!mounted || switched == null) return;
      _failoverAttempted = true;
      _reportFailCount = 0;
      LogService()
          .log('Player', '$reason失败，已自动切换到线路: ${switched.effectiveUrl}');
      showAppToast(context, '当前线路不可达，已自动切换');
      // 用切换后的 service 复播（显式重跑，不走 _switchToEpisode）
      final startMs = _player.position;
      await _loadStream(
        serverId: widget.serverId,
        startMs: startMs,
      );
    } finally {
      _failoverInFlight = false;
    }
  }

  // ---- 视频流同线路自动重载（v1.1.245）----

  /// 视频流中断（invalid / 取流失败 / 缓冲超时）时按退避序列调度同线路重载。
  ///
  /// 与 [_maybeFailover]（线路切换，API 层）互补：本方法不切线路，
  /// 仅用当前位置 seek 复播当前流；观众同样处理（重载后由心跳纠偏）。
  void _maybeStreamReload(String reason) {
    if (!mounted || !_streamReload.canSchedule) return;
    _streamReload.schedule(() {
      LogService().log('Player', '$reason → 调度同线路重载');
      unawaited(_reloadSameLine());
    });
  }

  /// 同线路重载：捕获当前位置，复用已验证的加载路径 seek 复播。
  ///
  /// 分发对齐 [_recoverVideoAfterResume]：
  /// - 观众：[_playFromUrl]（重载后心跳纠偏回房主进度）
  /// - 有剧集：[_loadEpisodeStream]（带 startMs，不复位退避预算）
  /// - 单集：[_loadStream]（带 startMs，不复位退避预算）
  Future<void> _reloadSameLine() async {
    if (!mounted || !_streamReload.beginFlight()) return;
    _cancelStallWatchdog();
    final posMs = _player.position;
    final wasPlaying = _player.state == AdapterPlaybackState.playing;
    LogService().log('Player', '同线路自动重载 pos=${posMs}ms playing=$wasPlaying');
    try {
      if (!_isPlayerReady) return;
      // 房间观众：走同步播放重载（内部自行起播/seek）
      if (widget.roomCode != null && !_isHost) {
        if (_currentPlayUrl.isEmpty) return;
        _playFromUrl(
          playUrl: _currentPlayUrl,
          token: _currentToken,
          position: posMs / 1000.0,
          epIndex: _currentEpisodeIndex >= 0 ? _currentEpisodeIndex : null,
        );
        return;
      }
      // 单人 / 房主：走已验证的加载路径（重载会重新起播）
      if (_hasEpisodeList && _currentEpisodeIndex >= 0) {
        await _loadEpisodeStream(_currentEpisodeIndex,
            startMs: posMs, resetBudget: false);
      } else {
        // 不复位退避预算：重载成功 ≠ 播放恢复健康。健康复位交给
        // _samplePlayback 的稳定兜底（playing 且非卡顿），否则重置预算
        // 会让退避上限失效形成无界重载环。
        await _loadStream(startMs: posMs);
      }
      if (!mounted) return;
      // 暂停态还原：重载默认起播，需恢复暂停（同 resume 路径）
      if (!wasPlaying) {
        _player.state = AdapterPlaybackState.paused;
        _position = Duration(milliseconds: posMs);
        _positionNotifier.value = _position;
        _syncPlayState();
      }
    } finally {
      _streamReload.endFlight();
    }
    // 重载结束（endFlight 后）：按健康度决定下一步。
    // inFlight 期间 _loadStream 内部 catch 的 _maybeStreamReload 会被
    // canSchedule 吞掉，需在此补处理，否则重试链断裂。
    if (!mounted) return;
    final ms = _player.mediaStatus;
    final st = _player.state;
    final broken = ms.test(AdapterMediaStatus.invalid) ||
        ms.test(AdapterMediaStatus.stalled);
    final healthy = st == AdapterPlaybackState.playing &&
        !broken &&
        !ms.test(AdapterMediaStatus.buffering);
    if (!healthy) {
      if (broken) {
        // 明确损坏：立即按退避调度下一次重载。
        _maybeStreamReload('重载后仍异常');
      } else {
        // 仅 buffering 位未落（高码率/弱网常见）：不立即重载（会清缓冲
        // 加剧卡顿成环），改交「进度感知 watchdog」判定——位置持续推进
        // 即视为慢但在播，不重载；真停滞才在 10s 后重载。
        _startStallWatchdog();
      }
    }
  }

  /// 缓冲 watchdog：持续 buffering/stalled 且**播放位置停滞**超过 10s
  /// 才触发同线路重载。
  ///
  /// 网络波动断连常表现为流挂起不报 invalid，仅停在 buffering/stalled；
  /// 状态位可能永不翻转（diag.reapStaleStall 兜底同理），需独立计时兜底。
  /// 但高码率 4K + 弱网下降速播放也会长期置位 buffering 而位置持续推进，
  /// 此时不得重载（清缓冲只会加剧卡顿），故以「位置推进」区分真卡死。
  void _startStallWatchdog() {
    // 已有重载调度/进行中：不重复武装
    if (_streamReload.hasPending || _streamReload.inFlight) return;
    _stallWatchdogTimer?.cancel();
    // 记录武装时位置：采样时据此判断是否仍有推进（真卡死才重载）。
    _stallWatchdogStartPosMs = _player.position;
    _stallWatchdogTimer = Timer(StreamReloadScheduler.stallTimeout, () {
      if (!mounted) return;
      // 触发前再确认一次：位置有推进则说明慢但在播，不重载。
      final startPos = _stallWatchdogStartPosMs;
      if (startPos != null &&
          StreamStallGuard.progressed(startPos, _player.position)) {
        LogService().log('Diag', '缓冲超时但进度已推进 → 不重载');
        _diag.onStallEnd();
        _cancelStallWatchdog();
        return;
      }
      LogService().log('Player', '缓冲超时 → 调度同线路重载');
      _maybeStreamReload('缓冲超时');
    });
  }

  /// 取消缓冲 watchdog（缓冲恢复 / 重载开始 / dispose）。
  void _cancelStallWatchdog() {
    _stallWatchdogTimer?.cancel();
    _stallWatchdogTimer = null;
    _stallWatchdogStartPosMs = null;
  }

  /// 从「重播乐观隐藏」集合移除当前条目（服务器真相已回来）。
  void _clearResumeHidden(String id) {
    final notifier = ref.read(resumeOptimisticHiddenProvider.notifier);
    if (notifier.state.contains(id)) {
      notifier.state = {...notifier.state}..remove(id);
      ref.read(resumeRevisionProvider.notifier).state++;
    }
  }

  /// 节流 bump 续播修订号（≤1 次/2s，避免 3s 上报导致首页每 3s 重取）。
  void _bumpResumeThrottled() {
    final now = DateTime.now();
    if (_lastProgressBump != null &&
        now.difference(_lastProgressBump!).inMilliseconds < 2000) {
      return;
    }
    _lastProgressBump = now;
    ref.read(resumeRevisionProvider.notifier).state++;
  }

  /// 停止上报并（成功时）bump 续播修订号 → 首页「继续观看」即时刷新。
  /// [positionMs] 可指定最终位置：跳过片尾时用总时长，避免把片尾起点
  /// 写回续播。
  Future<void> _reportStopped({int? positionMs}) async {
    _stopReportTimer();
    final svc = _reportService;
    final id = _reportItemId;
    if (!_shouldReportPlayback ||
        !_reportStarted ||
        svc == null ||
        id == null) {
      return;
    }
    final finalPosition = positionMs ?? _reportPosition;
    final ok = await svc.reportPlaybackStopped(
      itemId: id,
      playSessionId: _playSessionId,
      mediaSourceId: _reportMediaSourceId,
      positionMs: finalPosition,
    );
    if (!ok) return;
    _reportStarted = false;
    if (!mounted) return;
    _lastProgressBump = null;
    _clearResumeHidden(id);
    ref.read(resumeRevisionProvider.notifier).state++;
    _reportTraktProgress(id, finalPosition);
  }

  void _reportTraktProgress(String itemId, int positionMs) {
    final serverConfigId = _reportServerConfigId;
    if (serverConfigId == null || positionMs <= 0) return;
    final durationMs = _duration.inMilliseconds;
    if (durationMs > 0 && positionMs >= durationMs * 0.9) return;
    unawaited(ref.read(traktProvider.notifier).reportPlaybackProgress(
          serverConfigId: serverConfigId,
          itemId: itemId,
          positionMs: positionMs,
        ));
  }

  void _startReportTimer() {
    _reportTimer?.cancel();
    _reportTimer = Timer.periodic(
      PlayerScreen.playbackReportInterval,
      (_) => _reportProgress(),
    );
  }

  void _stopReportTimer() {
    _reportTimer?.cancel();
    _reportTimer = null;
  }

  void _startOrientationSensor() {
    // sensors_plus 仅 android/ios/web 有原生实现：桌面端订阅前的
    // invokeMethod 会抛未处理的 MissingPluginException → FATAL 误报
    if (!OrientationSensorGate.shouldSubscribeOrientationSensor(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    )) {
      LogService().log('Sensor', '当前平台无加速度计实现，跳过摇一摇翻转');
      return;
    }
    double filteredX = 0;
    const alpha = 0.45;
    int flipCount = 0;
    // 灵敏度（iOS 实测「不够灵敏」逐档调高）：
    // - 采样 uiInterval(~67ms) 替代 normalInterval(200ms)，样本更密；
    // - 低通 alpha 0.2 → 0.45，滤波不再把翻转拖慢数秒；
    // - 阈值 8.0 → 6.5（手持倾角不必接近竖直）+ 连续 2 次 + 0.7s 冷却。
    const double flipThreshold = 6.5;
    const int requiredSamples = 2;
    const Duration flipCooldown = Duration(milliseconds: 700);
    DateTime? lastFlipAt;

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      filteredX = alpha * event.x + (1 - alpha) * filteredX;

      // 仅在横屏模式下检测180度翻转
      final cooldownOver = lastFlipAt == null ||
          DateTime.now().difference(lastFlipAt!) >= flipCooldown;
      if (_orientationMode == _OrientationMode.landscapeLeft) {
        if (filteredX < -flipThreshold) {
          flipCount++;
          if (flipCount >= requiredSamples) {
            if (cooldownOver) {
              _switchToLandscape(_OrientationMode.landscapeRight);
              lastFlipAt = DateTime.now();
            }
            flipCount = 0;
          }
        } else {
          flipCount = 0;
        }
      } else if (_orientationMode == _OrientationMode.landscapeRight) {
        if (filteredX > flipThreshold) {
          flipCount++;
          if (flipCount >= requiredSamples) {
            if (cooldownOver) {
              _switchToLandscape(_OrientationMode.landscapeLeft);
              lastFlipAt = DateTime.now();
            }
            flipCount = 0;
          }
        } else {
          flipCount = 0;
        }
      }
    }, onError: (Object error) {
      // sensors_plus 无 Windows/macOS/Linux 实现：吞掉 MissingPluginException，
      // 摇一摇翻转在桌面端自然失效
      LogService().log('Sensor', '加速度计事件流错误: $error');
    });
  }

  void _switchToLandscape(_OrientationMode mode) {
    if (!mounted) return;
    setState(() => _orientationMode = mode);
    // 单方向强制：双方向列表在引擎侧解码为 USER_LANDSCAPE（尊重系统
    // 旋转锁，系统关转屏时不生效）；单方向 → LANDSCAPE/REVERSE_LANDSCAPE
    // 固定值，锁转屏下也能 180° 翻转。
    requestPlayerLandscape(
      mode == _OrientationMode.landscapeRight
          ? PlayerLandscapeSide.right
          : PlayerLandscapeSide.left,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _toggleOrientation() {
    if (_orientationMode == _OrientationMode.portraitUp) {
      _switchToLandscape(_OrientationMode.landscapeLeft);
    } else {
      setState(() => _orientationMode = _OrientationMode.portraitUp);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _cycleVideoFit() {
    final nextIndex =
        (_videoFitModes.indexOf(_videoFit) + 1) % _videoFitModes.length;
    setState(() => _videoFit = _videoFitModes[nextIndex]);
  }

  void _onSeekStart(double value) {
    _isDraggingSlider = true;
    _positionNotifier.value = Duration(milliseconds: value.toInt());
  }

  void _onSeekEnd(double value) {
    _isDraggingSlider = false;
    // 立即更新 UI 到目标位置，不等 Timer.periodic
    _position = Duration(milliseconds: value.toInt());
    _positionNotifier.value = _position;
    _skipController.onSeek(
      positionMs: value.toInt(),
      segments: _skipSegments,
      markOutroHandled: false,
    );
    unawaited(_seekGuarded(value.toInt()).then((_) {
      if (mounted) unawaited(_reportProgress());
    }));
    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: value / 1000);
    }
  }

  /// 带守卫的 seek：置 `_isSeekingPlayback` → await adapter seek（2s
  /// 超时兜底）→ 清零并回读 position 同步 UI（防止原生 seek 窗口内
  /// position 报 0/负值被 _positionTimer 写入 → 进度条跳回开头）。
  Future<void> _seekGuarded(int targetMs) async {
    _isSeekingPlayback = true;
    try {
      await _player
          .seek(positionMs: targetMs)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    _isSeekingPlayback = false;
    _lastSeekCompletedAt = DateTime.now();
    if (!mounted) return;
    final pos = _player.position;
    if (pos >= 0) {
      _position = Duration(milliseconds: pos);
      _positionNotifier.value = _position;
    }
  }

  // ========== 跳过片头/片尾 ==========

  bool get _segmentFeatureEnabled =>
      _canControlPlayback && ref.read(settingsProvider).skipIntroOutroEnabled;

  bool get _autoSkipSegmentEnabled => PlayerScreen.shouldAutoSkipSegment(
        canControlPlayback: _canControlPlayback,
        skipEnabled: ref.read(settingsProvider).skipIntroOutroEnabled,
        autoSkipEnabled: ref.read(settingsProvider).autoSkipIntroOutroEnabled,
      );

  bool get _isSeriesPlayback {
    if (!_hasEpisodeList ||
        _currentEpisodeIndex < 0 ||
        _currentEpisodeIndex >= _episodes.length) {
      return false;
    }
    final episode = _episodes[_currentEpisodeIndex];
    return _seriesName.isNotEmpty ||
        episode.seriesName.isNotEmpty ||
        episode.season > 0 ||
        episode.number > 0;
  }

  bool get _segmentMarkGestureEnabled =>
      PlayerPlatform.mediaLongPressSpeedBoost &&
      !ref.read(settingsProvider).tvMode &&
      _segmentFeatureEnabled &&
      !_lockController.locked &&
      !_showSubtitleMenu &&
      !_showAudioMenu &&
      !_showKernelMenu &&
      !_showDecodeModeMenu &&
      !_showSpeedMenu &&
      !_showSubtitleStyleMenu &&
      !_showEpisodeMenu &&
      !_showVersionMenu &&
      !_showSegmentMarkPanel &&
      !_showBrightnessBarNotifier.value &&
      !_showVolumeBarNotifier.value;

  String get _segmentKey {
    final item = _segmentMediaItem;
    if (item == null) return '';
    final scope = item.seriesId ?? item.id;
    return '${_segmentServerId.isEmpty ? 'unknown' : _segmentServerId}|$scope';
  }

  int? get _segmentIntroEndMs => _manualSegmentRecord?.introEndMs;
  int? get _segmentCreditsStartMs => _manualSegmentRecord?.creditsStartMs;

  Future<void> _loadSkipSegments(
    MediaItem item, {
    bool suppressAtCurrent = false,
    bool resetController = true,
  }) async {
    final seq = ++_skipLoadSeq;
    final enabled =
        _canControlPlayback && ref.read(settingsProvider).skipIntroOutroEnabled;
    if (!enabled) {
      if (mounted && seq == _skipLoadSeq) {
        setState(() {
          _skipSegments = const [];
          _manualSegmentRecord = null;
          _skipPromptSegment = null;
        });
      }
      return;
    }

    final durationMs = item.runTimeTicks != null && item.runTimeTicks! > 0
        ? item.runTimeTicks! ~/ 10000
        : (_duration.inMilliseconds > 0
            ? _duration.inMilliseconds
            : _segmentDurationMs);
    ManualSegmentRecord? manual;
    final scope = item.seriesId ?? item.id;
    final key =
        '${_segmentServerId.isEmpty ? 'unknown' : _segmentServerId}|$scope';
    if (scope.isNotEmpty) {
      try {
        manual = await _manualSegments.get(key);
      } catch (_) {}
    }
    if (!mounted || seq != _skipLoadSeq) return;

    final segments = MediaSegmentResolver.resolve(
      chapters: item.chapters,
      manual: manual,
      durationMs: durationMs,
    );
    if (resetController) _skipController.reset();
    if (suppressAtCurrent) {
      _skipController.onSeek(
        positionMs: _position.inMilliseconds,
        segments: segments,
      );
    }
    setState(() {
      _segmentMediaItem = item;
      _manualSegmentRecord = manual;
      _segmentDurationMs = durationMs;
      _skipSegments = segments;
      _skipPromptSegment = null;
    });
    _skipPromptTimer?.cancel();
    _resetHideTimer();
  }

  void _beginSkipPromptSuppression() {
    _skipPromptSuppressed = true;
    _skipPromptTimer?.cancel();
    _skipPromptTimer = null;
    _skipController.reset();
    _skipPromptPlaybackWatch.reset();
    if (mounted && _skipPromptSegment != null) {
      setState(() => _skipPromptSegment = null);
    } else {
      _skipPromptSegment = null;
    }
  }

  void _evaluateSkipPrompt(int positionMs) {
    if (!PlayerScreen.canEvaluateSkipPrompt(
      suppressed: _skipPromptSuppressed,
      switchingMedia: _isSwitchingMedia,
    )) {
      return;
    }
    final playing = _player.state == AdapterPlaybackState.playing;
    if (!playing) {
      _skipPromptPlaybackWatch.stop();
      return;
    }
    if (!_skipPromptPlaybackWatch.isRunning) {
      _skipPromptPlaybackWatch.start();
    }
    if (!_segmentFeatureEnabled || _skipSegments.isEmpty) return;
    final insideIntro = _skipSegments.any(
      (segment) =>
          segment.type == MediaSegmentType.intro &&
          segment.contains(positionMs),
    );
    if (PlayerScreen.shouldDelayIntroPrompt(
      playbackElapsedMs: _skipPromptPlaybackWatch.elapsedMilliseconds,
      insideIntro: insideIntro,
    )) {
      return;
    }
    final durationMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : _segmentDurationMs;
    final segment = _skipController.evaluate(
      positionMs: positionMs,
      durationMs: durationMs,
      playing: _player.state == AdapterPlaybackState.playing,
      enabled: true,
      segments: _skipSegments,
    );
    if (segment == null || !mounted) return;
    if (_autoSkipSegmentEnabled) {
      _autoSkipSegment(segment);
      return;
    }
    _skipPromptTimer?.cancel();
    setState(() {
      _skipPromptSegment = segment;
      _showControls = true;
    });
    _resetHideTimer();
    _skipPromptTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) _dismissSkipPrompt();
    });
    if (ref.read(settingsProvider).tvMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _skipPromptSegment != null) {
          _skipPromptFocusNode.requestFocus();
        }
      });
    }
  }

  /// 焦点是否落在玩家可见控件上。
  ///
  /// skipTraversal 根锚点（PlayerHotkey/控制条根/顶栏根等）虽然可能持有
  /// 焦点，但屏幕没有对应焦点环；不能把它们当成有效落点。
  bool _isVisiblePlayerFocus(FocusNode? node) {
    if (node == null || node.skipTraversal) return false;
    return PlayerScreen.focusWithin(_controlsRootFocusNode, node) ||
        PlayerScreen.focusWithin(_topBarRootFocusNode, node) ||
        PlayerScreen.focusWithin(_selectorPanelRootFocusNode, node) ||
        PlayerScreen.focusWithin(_segmentMarkScopeNode, node);
  }

  /// 提示消失/跳过后的焦点兜底：控制条可见时回进度条，隐藏/锁屏时回热键层。
  void _restoreFocusAfterSkipPrompt() {
    if (!mounted) return;
    if (_showControls && !_lockController.locked) {
      _controlsFocusNode.requestFocus();
    } else {
      _hotkeyFocusNode.requestFocus();
    }
  }

  void _dismissSkipPrompt() {
    _skipPromptTimer?.cancel();
    _skipPromptTimer = null;
    if (!mounted || _skipPromptSegment == null) return;
    final primary = FocusManager.instance.primaryFocus;
    // 焦点可能已被方向键/焦点历史送到不可见热键层；此时也不能只判断
    // primary 是否仍在提示按钮上，否则提示移除后焦点会永久悬空。
    final needsRestore =
        primary == _skipPromptFocusNode || !_isVisiblePlayerFocus(primary);
    setState(() => _skipPromptSegment = null);
    // 提示期间控制条保持可见，但计时器可能已临近到点；给用户完整操作窗口。
    _resetHideTimer();
    if (needsRestore) {
      _restoreFocusAfterSkipPrompt();
      // 重建可能再次改写焦点；下一帧确认仍不是可见控件再补一次。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_isVisiblePlayerFocus(FocusManager.instance.primaryFocus)) {
          _restoreFocusAfterSkipPrompt();
        }
      });
    }
  }

  void _autoSkipSegment(MediaSegment segment) {
    _dismissSkipPrompt();
    _skipSegment(segment);
  }

  void _performSkipSegment() {
    final segment = _skipPromptSegment;
    if (segment == null || !_canControlPlayback) return;
    _dismissSkipPrompt();
    _skipSegment(segment);
  }

  void _skipSegment(MediaSegment segment) {
    if (!_canControlPlayback) return;
    final durationMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : _segmentDurationMs;
    final targetMs =
        durationMs > 0 ? segment.endMs.clamp(0, durationMs) : segment.endMs;

    if (segment.type == MediaSegmentType.outro) {
      final completedAtMs = durationMs > 0 ? durationMs : targetMs;
      final hasNextEpisode = PlayerScreen.shouldAdvanceAfterOutroSkip(
        hasEpisodeList: _hasEpisodeList,
        currentEpisodeIndex: _currentEpisodeIndex,
        episodeCount: _episodes.length,
      );
      if (hasNextEpisode) {
        unawaited(_handleEpisodeFinished(completedAtMs: completedAtMs));
        return;
      }
      unawaited(_finishOutroAndExit(
        targetMs: targetMs,
        completedAtMs: completedAtMs,
        showSeriesFinished: PlayerScreen.shouldShowSeriesFinishedAfterOutroSkip(
          isSeries: _isSeriesPlayback,
          hasNextEpisode: hasNextEpisode,
        ),
      ));
      return;
    }

    _position = Duration(milliseconds: targetMs);
    _positionNotifier.value = _position;
    _skipController.onSeek(
      positionMs: targetMs,
      segments: _skipSegments,
    );
    unawaited(_seekGuarded(targetMs).then((_) {
      if (mounted) unawaited(_reportProgress());
    }));
    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: targetMs / 1000);
    }
  }

  /// 片尾无下一集：跳到片尾终点、标记已观看并退出播放器。
  Future<void> _finishOutroAndExit({
    required int targetMs,
    required int completedAtMs,
    required bool showSeriesFinished,
  }) async {
    if (!mounted) return;
    _endHandled = true;
    final reportService = _reportService;
    final reportItemId = _reportItemId;

    _position = Duration(milliseconds: targetMs);
    _positionNotifier.value = _position;
    _skipController.onSeek(
      positionMs: targetMs,
      segments: _skipSegments,
    );
    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: targetMs / 1000);
    }
    await _seekGuarded(targetMs);
    if (!mounted) return;

    try {
      _player.state = AdapterPlaybackState.paused;
    } catch (_) {}
    _syncPlayState();
    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionPause);
    }

    if (showSeriesFinished) {
      _addBroadcastMessage('所有剧集播放完毕');
      showAppToast(context, '所有剧集播放完毕');
    } else {
      showAppToast(context, '播放完毕');
    }

    if (widget.roomCode != null) {
      // 房间会继续换资源播放：只停在片尾，不写进度、不标记、不解散。
      return;
    }

    await _reportStopped(positionMs: completedAtMs);
    await _markWatched(service: reportService, itemId: reportItemId);
    if (!mounted) return;

    Navigator.pop(context);
  }

  /// 显式标记当前条目已观看，并刷新本地续播/列表状态。
  Future<void> _markWatched({
    EmbyService? service,
    String? itemId,
  }) async {
    if (!_shouldReportPlayback) return;
    final svc = service ?? _reportService;
    final id = itemId ?? _reportItemId;
    if (svc == null || id == null) return;
    final ok = await svc.setWatched(id, true);
    if (!mounted) return;
    if (!ok) {
      LogService().log('Player', '跳过片尾标记已观看失败: $id');
      return;
    }
    ref.read(mediaStateOverrideProvider.notifier).setWatched(id, true);
    _clearResumeHidden(id);
    ref.read(resumeRevisionProvider.notifier).state++;
    final serverConfigId = _reportServerConfigId;
    if (serverConfigId != null) {
      unawaited(ref.read(traktProvider.notifier).reportWatched(
            serverConfigId: serverConfigId,
            itemId: id,
          ));
    }
  }

  Future<void> _markSegmentAt(MediaSegmentType type) async {
    if (!_segmentFeatureEnabled) return;
    final item = _segmentMediaItem;
    if (item == null) {
      showAppToast(context, '尚未获取到影片信息，请稍后再试');
      return;
    }
    final positionMs = _position.inMilliseconds;
    final durationMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : _segmentDurationMs;
    if (positionMs <= 0) {
      showAppToast(context, '当前位置为 0，无法标记');
      return;
    }
    if (type == MediaSegmentType.intro &&
        !PlayerScreen.canSetIntroAt(positionMs)) {
      showAppToast(context, '播放 3 秒后才能设置片头');
      return;
    }
    if (durationMs > 0 && positionMs >= durationMs) {
      showAppToast(context, '当前位置已到结尾，无法标记');
      return;
    }

    final key = _segmentKey;
    final providerIds = item.providerIds;
    try {
      if (type == MediaSegmentType.intro) {
        await _manualSegments.setIntroEnd(
          key: key,
          serverId: _segmentServerId,
          seriesId: item.seriesId,
          itemId: item.id,
          providerIds: providerIds,
          introEndMs: positionMs,
        );
      } else {
        await _manualSegments.setCreditsStart(
          key: key,
          serverId: _segmentServerId,
          seriesId: item.seriesId,
          itemId: item.id,
          providerIds: providerIds,
          creditsStartMs: positionMs,
        );
      }
      await _loadSkipSegments(item, suppressAtCurrent: true);
      if (!mounted) return;
      final label = type == MediaSegmentType.intro ? '片头结束点' : '片尾开始点';
      showAppToast(
        context,
        '已设置$label：${SegmentMarkPanel.formatMs(positionMs)}'
        '${item.seriesId != null ? '（本剧所有集共用）' : ''}',
      );
    } catch (e) {
      LogService().log('Player', '保存片头片尾标记失败: $e');
      if (mounted) showAppToast(context, '保存失败，请重试');
    }
  }

  Future<void> _clearSegmentAt(MediaSegmentType type) async {
    if (!_segmentFeatureEnabled) return;
    final item = _segmentMediaItem;
    if (item == null) return;
    try {
      if (type == MediaSegmentType.intro) {
        await _manualSegments.clearIntro(_segmentKey);
      } else {
        await _manualSegments.clearCredits(_segmentKey);
      }
      await _loadSkipSegments(item, suppressAtCurrent: true);
      if (!mounted) return;
      showAppToast(
        context,
        type == MediaSegmentType.intro ? '已清除片头标记' : '已清除片尾标记',
      );
    } catch (e) {
      LogService().log('Player', '清除片头片尾标记失败: $e');
      if (mounted) showAppToast(context, '清除失败，请重试');
    }
  }

  Future<void> _onSegmentMarkSelected(MediaSegmentType type) async {
    final existing = type == MediaSegmentType.intro
        ? _segmentIntroEndMs
        : _segmentCreditsStartMs;
    _closeSegmentMarkPanel();
    if (!PlayerScreen.hasExistingSegmentMark(existing)) {
      await _markSegmentAt(type);
      return;
    }
    final existingMs = existing!;
    final isIntro = type == MediaSegmentType.intro;
    final action = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isIntro ? '片头已设置' : '片尾已设置'),
          content: Text(
            '当前标记：${SegmentMarkPanel.formatMs(existingMs)}\n'
            '要用当前位置（${SegmentMarkPanel.formatMs(_position.inMilliseconds)}）更新，还是清除？',
          ),
          actions: [
            TvFocusable(
              onTap: () => Navigator.pop(dialogContext, null),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('取消'),
              ),
            ),
            TvFocusable(
              onTap: () => Navigator.pop(dialogContext, false),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('清除'),
              ),
            ),
            TvFocusable(
              autofocus: true,
              onTap: () => Navigator.pop(dialogContext, true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('更新'),
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null) return;
    if (action) {
      await _markSegmentAt(type);
    } else {
      await _clearSegmentAt(type);
    }
  }

  void _openSegmentMarkPanel() {
    if (!_segmentFeatureEnabled) return;
    setState(() {
      _showSegmentMarkPanel = true;
      _showControls = true;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
      _showDecodeModeMenu = false;
    });
    _resetHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showSegmentMarkPanel) {
        _segmentMarkFirstFocusNode.requestFocus();
      }
    });
  }

  void _closeSegmentMarkPanel() {
    if (!_showSegmentMarkPanel) return;
    setState(() => _showSegmentMarkPanel = false);
    if (ref.read(settingsProvider).tvMode) {
      _controlsFocusNode.requestFocus();
    }
    _resetHideTimer();
  }

  void _onVideoLongPressStart(LongPressStartDetails details) {
    final x = details.globalPosition.dx;
    final width = MediaQuery.sizeOf(context).width;
    if (_segmentMarkGestureEnabled) {
      if (x < width / 3) {
        unawaited(_onSegmentMarkSelected(MediaSegmentType.intro));
        return;
      }
      if (x > width * 2 / 3) {
        unawaited(_onSegmentMarkSelected(MediaSegmentType.outro));
        return;
      }
    }
    if (_speedBoostGestureEnabled) _onSpeedBoostStart();
  }

  void _onVideoLongPressEnd(LongPressEndDetails _) {
    _onSpeedBoostEnd();
  }

  Widget _buildSkipPromptButton() {
    final segment = _skipPromptSegment;
    if (segment == null) return const SizedBox.shrink();
    final isIntro = segment.type == MediaSegmentType.intro;
    return TvFocusable(
      focusNode: _skipPromptFocusNode,
      onTap: _performSkipSegment,
      // 提示可见时方向键显式转到进度条：默认方向遍历/焦点历史可能把焦点
      // 送到不可见热键层，提示随后消失就会永久悬空。
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.arrowLeft &&
            key != LogicalKeyboardKey.arrowRight &&
            key != LogicalKeyboardKey.arrowUp &&
            key != LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.ignored;
        }
        _resetHideTimer();
        _restoreFocusAfterSkipPrompt();
        return KeyEventResult.handled;
      },
      radius: 14,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIntro ? Icons.skip_next : Icons.skip_previous,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              isIntro ? '跳过片头' : '跳过片尾',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _logControlsVisibility('点屏');
    _resetHideTimer();
  }

  /// TV 唤出控制条：隐藏时显示 + 重置自动隐藏计时 + 焦点落进度滑杆
  /// （焦点在滑杆时左右键调进度，上下键移动到控制条按钮）；
  /// 已可见时仅顺延自动隐藏——不抢焦点，否则按钮上按 OK 打开菜单后
  /// 焦点被拽回滑杆（"很难选到"）。
  void _showControlsForTv() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _logControlsVisibility('遥控唤出');
      _resetHideTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showControls) _controlsFocusNode.requestFocus();
      });
    } else {
      _resetHideTimer();
    }
  }

  /// 控制条/顶栏即将卸载：若焦点在其子树内（滑杆、按钮、菜单面板），
  /// 先回落热键层，避免卸载后焦点悬空（方向键"选不到"）。
  /// 焦点在底部弹窗等其他路由时不抢。
  void _releaseFocusFromControls() {
    if (PlayerScreen.focusWithin(
        _hotkeyFocusNode, FocusManager.instance.primaryFocus)) {
      _hotkeyFocusNode.requestFocus();
    }
  }

  /// 顺延自动隐藏计时（任何真实操作调用；控件隐藏时为空操作）。
  void _resetHideTimer() => _autoHide.reset();

  /// 控件显隐留证（真机排查「控件自己冒出来」）：调用点均在状态已变更
  /// 之后，日志记录本次变化与触发来源，便于对照时间线确认是否真实输入。
  void _logControlsVisibility(String trigger) {
    LogService().log('Diag', '控件${_showControls ? '显示' : '隐藏'}（$trigger）');
  }

  /// 焦点变更监听：焦点**移动到**控件内算操作；焦点停留原地不触发，
  /// 因此"焦点静置在控件上长时间不操作"仍会到点隐藏。
  void _onPrimaryFocusChanged() {
    _autoHide.onFocusChanged(FocusManager.instance.primaryFocus);
  }

  /// 长时间无操作：隐藏全部控件（含选择器面板）并回落焦点。
  void _onControlsIdleHide() {
    if (!mounted) return;
    // 跳过提示有效期内保持控件可见，提示自身 8 秒后消失
    if (_skipPromptSegment != null) {
      _autoHide.reset();
      return;
    }
    // 片头片尾标记面板打开期间保持控件与焦点，避免计时到点回落热键层
    if (_showSegmentMarkPanel) {
      _autoHide.reset();
      return;
    }
    if (_player.state != AdapterPlaybackState.playing) {
      // 起播未完成（慢流首开常见）：本次计时空转，日志留证；
      // 起播成功处会重新起算（见 _loadStream/_playFromUrl）。
      LogService().log('Diag', '自动隐藏跳过（state=${_player.state}）');
      return;
    }
    _releaseFocusFromControls();
    _selectorOpenerNode = null;
    setState(() {
      _showControls = false;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showDecodeModeMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
    });
    _logControlsVisibility('自动隐藏');
  }

  /// 打开字幕/音轨/倍速选择器面板：记录来源按钮，postFrame 把焦点精确
  /// 送进面板选中行（TV 按钮已持焦时行内 autofocus 不抢占，必须显式
  /// requestFocus）。
  void _openSelectorPanel(FocusNode opener) {
    _selectorOpenerNode = opener;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectorFirstFocusNode.enclosingScope != null) {
        _selectorFirstFocusNode.requestFocus();
      }
    });
  }

  /// 关闭选择器面板并把焦点还给来源按钮（TV 遥控可立即 OK 重开）。
  void _closeSelectorPanel() {
    final opener = _selectorOpenerNode;
    _selectorOpenerNode = null;
    setState(() {
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
    });
    _restoreSelectorOpenerFocus(opener, force: true);
  }

  /// 焦点在面板内时（或 [force]）把焦点还给来源按钮。
  void _restoreSelectorOpenerFocus(FocusNode? opener, {bool force = false}) {
    if (opener == null) return;
    final focusInPanel = PlayerScreen.focusWithin(
      _selectorPanelRootFocusNode,
      FocusManager.instance.primaryFocus,
    );
    if (!force && !focusInPanel) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // enclosingScope == null：未挂树（非 TV 的 TvFocusable 不接管节点），
      // 此时 requestFocus 会置 deferred 标记，须跳过防日后误抢焦
      if (mounted && opener.enclosingScope != null) opener.requestFocus();
    });
  }

  void _closeAllMenus() {
    final opener = _selectorOpenerNode;
    _selectorOpenerNode = null;
    setState(() {
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showDecodeModeMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
      _showSegmentMarkPanel = false;
    });
    // 焦点正在面板行上（如 Back 关闭）：原路返回来源按钮，防悬空
    _restoreSelectorOpenerFocus(opener);
    _showBrightnessBarNotifier.value = false;
    _showVolumeBarNotifier.value = false;
  }

  // 切集（房主操作 + 发送RTM命令）
  /// 当前集播放完毕：自动切下一集；已是最后一集则提示完播。
  /// `_endHandled` 保证单集只触发一次（mdk end 事件与位置兜底并存）。
  /// [completedAtMs] 用于跳过片尾：按总时长上报并显式标记已观看。
  Future<void> _handleEpisodeFinished({int? completedAtMs}) async {
    if (!mounted || _endHandled) return;
    if (_isSwitchingMedia) return;
    if (!_hasEpisodeList || !_canControlPlayback) return;
    _endHandled = true;
    final completed = completedAtMs ??
        (_duration.inMilliseconds > 0 ? _duration.inMilliseconds : null);
    final nextIndex = _currentEpisodeIndex + 1;
    if (nextIndex < _episodes.length) {
      unawaited(_switchToEpisode(nextIndex, completedAtMs: completed));
      return;
    }
    if (widget.roomCode != null) {
      final message = _isSeriesPlayback ? '所有剧集播放完毕' : '播放完毕';
      _addBroadcastMessage(message);
      showAppToast(context, message);
      return;
    }
    unawaited(_finishPlaybackAndExit(completedAtMs: completed));
  }

  Future<void> _finishPlaybackAndExit({required int? completedAtMs}) async {
    final reportService = _reportService;
    final reportItemId = _reportItemId;
    await _reportStopped(positionMs: completedAtMs);
    await _markWatched(service: reportService, itemId: reportItemId);
    if (!mounted) return;
    _addBroadcastMessage('播放完毕');
    showAppToast(context, _isSeriesPlayback ? '所有剧集播放完毕' : '播放完毕');
    Navigator.pop(context);
  }

  Future<void> _switchToEpisode(int index, {int? completedAtMs}) async {
    if (index < 0 || index >= _episodes.length) return;
    if (index == _currentEpisodeIndex && _isPlayerReady) return;
    _beginSkipPromptSuppression();

    final requestId = ++_playRequestId;
    final previousReportService = _reportService;
    final previousReportItemId = _reportItemId;

    // 切集前先落上一集的停止/已看；房间模式这两个能力内部自动 no-op。
    await Future.wait([
      _reportStopped(positionMs: completedAtMs),
      if (completedAtMs != null)
        _markWatched(
          service: previousReportService,
          itemId: previousReportItemId,
        ),
    ]);

    // 换集：先清空上一集弹幕（新集由 _loadEpisodeStream 就绪后并行触发加载，
    // 旧集在飞的请求由 _danmakuLoadSeq 作废）
    if (mounted && _danmakuOn) {
      _cancelDanmakuRetry();
      setState(() {
        _danmakuComments = const [];
        _danmakuLoadedIndex = -1;
        _danmakuLoading = false;
      });
    }

    // 先加载新集，获取 playUrl
    await _loadEpisodeStream(index);
    if (requestId != _playRequestId || !mounted) return;

    // 加载完成后，主持人发送带 playUrl 的 syncPlay 给观众
    if (_isHost && _rtmChannel != null) {
      final rtmService = ref.read(rtmServiceProvider);
      final position = _player.position / 1000.0;
      _logSyncEvent(
          '发送 syncPlay: ep=$index, pos=${position.toStringAsFixed(1)}s');
      await rtmService.sendCommand(
        action: AppConstants.actionSyncPlay,
        episodeIndex: index,
        itemId: _episodes[index].id,
        position: position,
        playUrl: _currentPlayUrl,
        token: _currentToken,
        subtitleStreams: _embySubtitleStreams.map((s) => s.toJson()).toList(),
        audioStreams: _embyAudioStreams.map((s) => s.toJson()).toList(),
        videoStream: _embyVideoStream?.toJson(),
        defaultAudioStreamIndex: _embyDefaultAudioIndex,
      );
      // 切集后重广播 roomInfo，确保观众字幕/音轨菜单随新集刷新
      unawaited(_broadcastRoomInfo());
    }

    _rebuildGroups();
  }

  /// 播放中切换当前条目的媒体版本（仅非房间模式）：
  /// 记录当前进度与字幕/音轨选择 → 更新当前集版本 → 重载流并从原进度续播
  /// → 新版本轨按语言迁移后重新应用；暂停态切换后仍保持暂停。
  Future<void> _switchMediaSource(MediaSource source) async {
    if (widget.roomCode != null) return;
    final index = _currentEpisodeIndex;
    if (index < 0 || index >= _episodes.length) return;
    if (source.id == _activeMediaSourceId) return;

    // 切换前快照：进度 + 当前轨（供语言迁移）+ 播放态
    final posMs = _player.position;
    final wasPlaying = _player.state == AdapterPlaybackState.playing;
    final oldAudio = List<MediaStream>.of(_embyAudioStreams);
    final oldSubtitle = List<MediaStream>.of(_embySubtitleStreams);
    final activeAudioPos = _player.activeAudioTracks.isNotEmpty
        ? _player.activeAudioTracks.first
        : -1;
    final oldAudioIndex =
        (activeAudioPos >= 0 && activeAudioPos < oldAudio.length)
            ? oldAudio[activeAudioPos].index
            : null;
    final oldSubtitleIndex = _activeSubtitleIndex;

    // 更新当前集版本并记录生效版本
    setState(() {
      _episodes[index] = _episodes[index].copyWith(mediaSourceId: source.id);
      _activeMediaSourceId = source.id;
    });

    final requestId = ++_playRequestId;
    await _loadEpisodeStream(index, startMs: posMs);
    if (requestId != _playRequestId || !mounted) return;

    // 轨道语言迁移：新版本里找同语言轨，找到才应用
    final migrated = migrateTrackSelection(
      TrackSelection(
        audioIndex: oldAudioIndex,
        subtitleIndex: oldSubtitleIndex,
      ),
      oldAudio: oldAudio,
      newAudio: _embyAudioStreams,
      oldSubtitle: oldSubtitle,
      newSubtitle: _embySubtitleStreams,
    );
    if (migrated != null) {
      final audioPos =
          _embyAudioStreams.indexWhere((s) => s.index == migrated.audioIndex);
      if (migrated.audioIndex != null && audioPos >= 0) {
        _selectEmbyAudio(audioPos);
      }
      final subIndex = migrated.subtitleIndex;
      if (subIndex != null && subIndex >= 0) {
        final subPos =
            _embySubtitleStreams.indexWhere((s) => s.index == subIndex);
        if (subPos >= 0) _selectEmbySubtitle(subPos);
      }
    }

    // 暂停态切换后保持暂停（_loadStream 内部无条件起播）
    if (!wasPlaying && mounted) {
      _player.state = AdapterPlaybackState.paused;
      _syncPlayState();
      setState(() {});
    }

    _rebuildGroups();
  }

  // 删除剧集（sendRtm=true 时为房主操作，false 时为观众端本地删除）
  void _removeEpisode(int index, {bool sendRtm = true}) {
    if (index < 0 || index >= _episodes.length) return;
    if (sendRtm && !_isHost) return;

    final removedName = _episodes[index].name;
    _episodes.removeAt(index);

    if (_currentEpisodeIndex == index) {
      _currentEpisodeIndex = -1;
      _isPlayerReady = false;
      _player.state = AdapterPlaybackState.stopped;
      _syncPlayState();
    } else if (_currentEpisodeIndex > index) {
      _currentEpisodeIndex--;
    }

    _hasEpisodeList = _episodes.isNotEmpty;
    _addBroadcastMessage('已移除: $removedName');
    setState(() {
      _rebuildGroups();
    });

    // 房主发送删除命令
    if (sendRtm && _rtmChannel != null) {
      ref.read(rtmServiceProvider).sendCommand(
            action: AppConstants.actionRemoveEpisode,
            episodeIndex: index,
          );
    }
  }

  void _handleAddResource(Map<String, dynamic> message) {
    _addResourceLocally(message);
  }

  void _addResourceLocally(Map<String, dynamic> data) {
    final isSeries = data['isSeries'] as bool? ?? false;
    final name = data['name'] as String? ?? '';
    final poster = data['poster'] as String? ?? '';
    final seriesName = data['seriesName'] as String? ?? '';
    final serverId = data['serverId'] as String?;

    if (isSeries) {
      final episodes = data['episodes'] as List<dynamic>?;
      if (episodes != null && episodes.isNotEmpty) {
        for (final ep in episodes) {
          if (ep is! Map<String, dynamic>) continue;
          final epMap = ep;
          _episodes.add(EpisodeInfo(
            id: epMap['id'] as String? ?? '',
            name: epMap['name'] as String? ?? '',
            season: epMap['season'] as int? ?? 0,
            number: epMap['number'] as int? ?? 0,
            poster: epMap['poster'] as String? ?? '',
            seriesName: seriesName,
            // 加入资源时逐集单选的版本
            mediaSourceId: epMap['mediaSourceId'] as String?,
            serverId: (epMap['serverId'] as String?) ?? serverId,
          ));
        }
        if (_seriesName.isEmpty) {
          _seriesName = seriesName;
        }
        _hasEpisodeList = true;
        _addBroadcastMessage('已添加: $name (${episodes.length}集)');
      }
    } else {
      final itemId = data['itemId'] as String?;
      if (itemId != null && itemId.isNotEmpty) {
        _episodes.add(EpisodeInfo(
          id: itemId,
          name: name,
          poster: poster,
          mediaSourceId: data['mediaSourceId'] as String?,
          serverId: serverId,
        ));
        _hasEpisodeList = true;
        _addBroadcastMessage('已添加: $name');
      }
    }
    setState(() {
      _rebuildGroups();
    });
  }

  void _sendAddResourceRTM(Map<String, dynamic> data) {
    if (_rtmChannel == null) return;
    final rtmService = ref.read(rtmServiceProvider);
    final isSeries = data['isSeries'] as bool? ?? false;
    rtmService.sendAddResource(
      itemId: data['itemId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      poster: data['poster'] as String? ?? '',
      isSeries: isSeries,
      seriesName: data['seriesName'] as String? ?? '',
      episodes:
          isSeries ? (data['episodes'] as List<Map<String, dynamic>>?) : null,
      serverId: data['serverId'] as String?,
    );
  }

  // 复制房间码
  Future<void> _copyRoomCode() async {
    final roomCode = widget.roomCode;
    if (roomCode == null) return;
    await Clipboard.setData(ClipboardData(text: roomCode));
    if (mounted) showAppToast(context, '已复制房间码');
  }

  Future<Uint8List?> _captureQrImage() async {
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveQrToGallery() async {
    final bytes = await _captureQrImage();
    if (bytes == null) {
      if (mounted) showAppToast(context, '二维码生成失败，请重试');
      return;
    }
    if (!mounted) return;
    try {
      if (Platform.isWindows) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存二维码',
          fileName: 'himi_qr.png',
          type: FileType.custom,
          allowedExtensions: const ['png'],
        );
        if (path == null) return;
        final target = path.toLowerCase().endsWith('.png') ? path : '$path.png';
        await File(target).writeAsBytes(bytes, flush: true);
        if (mounted) showAppToast(context, '二维码已保存');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/himi_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (Platform.isAndroid) {
        final dcimDir = Directory('/storage/emulated/0/DCIM/Himi');
        if (!dcimDir.existsSync()) dcimDir.createSync(recursive: true);
        await file.copy('${dcimDir.path}/himi_qr.png');
      }
      if (mounted) {
        showAppToast(context, '已保存到相册');
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '保存失败: $e');
      }
    }
  }

  Future<void> _shareQrImage() async {
    final bytes = await _captureQrImage();
    if (bytes == null) {
      if (mounted) showAppToast(context, '二维码生成失败，请重试');
      return;
    }
    if (!mounted) return;
    if (Platform.isWindows) {
      final copied = await copyPngToClipboard(bytes);
      if (mounted) {
        showAppToast(
          context,
          copied ? '二维码图片已复制，可直接粘贴' : '复制二维码失败，请重试',
        );
      }
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/himi_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'HIMI 房间二维码',
          text: '来一起看电影吧！用 HIMI 扫描二维码加入房间',
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, '分享失败: $e');
      }
    }
  }

  void _showShareRoomDialog() {
    final roomCode = widget.roomCode;
    if (_shareDialogOpen || roomCode == null) return;
    _shareDialogOpen = true;
    showDialog<void>(
      context: context,
      builder: (_) => RoomShareDialog(
        roomCode: roomCode,
        qrKey: _qrKey,
        onShareQr: _shareQrImage,
        onSaveQr: _saveQrToGallery,
        onCopyCode: _copyRoomCode,
      ),
    ).whenComplete(() {
      _shareDialogOpen = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退后台/失去焦点：抢在可能被系统回收前上报一次进度
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_reportProgress());
    }
    // 熄屏/切后台（同一条事件链）：记录状态，回前台时统一恢复视频输出。
    // 实测（himi_logs）：纹理档在后台后 mdk 原生管线停死，仅换纹理无法
    // 重启，回前台须按当前进度重载当前流（SurfaceView 档由 platform view 自愈）。
    if (PlayerLifecyclePolicy.enterBackground(state)) {
      if (!_appBackgrounded) {
        _appBackgrounded = true;
        _wasPlayingBeforeBackground =
            _isPlayerReady && _player.state == AdapterPlaybackState.playing;
        LogService().log('Player',
            '进入后台/熄屏: output=${_effectiveVideoOutput()} wasPlaying=$_wasPlayingBeforeBackground');
      }
    } else if (state == AppLifecycleState.resumed && _appBackgrounded) {
      _appBackgrounded = false;
      unawaited(_recoverVideoAfterResume());
    }
  }

  /// 回前台/亮屏后恢复视频输出：
  /// - 纹理/直通档：mdk 的解码/渲染管线在后台停死，按当前进度**重载当前
  ///   流**重建整条管线（复用已验证可用的加载路径）；
  /// - SurfaceView 档：platform view 自行重绑，不处理；
  /// - 按熄屏前状态还原：在播则播、暂停则回到暂停帧。
  Future<void> _recoverVideoAfterResume() async {
    if (!mounted || _recoveringVideo) return;
    if (!_isPlayerReady) return;
    final action = PlayerLifecyclePolicy.resumeAction(_effectiveVideoOutput());
    if (action != PlayerResumeAction.reprime) return;
    if (_currentPlayUrl.isEmpty) return;
    _recoveringVideo = true;
    final posMs = _position.inMilliseconds;
    final wasPlaying = _wasPlayingBeforeBackground;
    try {
      LogService()
          .log('Player', '回前台重载当前流恢复管线: pos=$posMs wasPlaying=$wasPlaying');
      // 房间观众：走同步播放重载（内部自行起播/seek）
      if (widget.roomCode != null && !_isHost) {
        _playFromUrl(
          playUrl: _currentPlayUrl,
          token: _currentToken,
          position: posMs / 1000.0,
          epIndex: _currentEpisodeIndex >= 0 ? _currentEpisodeIndex : null,
        );
        return;
      }
      // 单人 / 房主：走已验证的加载路径（重载会重新起播）
      if (_hasEpisodeList && _currentEpisodeIndex >= 0) {
        await _loadEpisodeStream(_currentEpisodeIndex, startMs: posMs);
      } else {
        await _loadStream(startMs: posMs);
      }
      if (!mounted) return;
      // 暂停态：重载默认会起播，需还原暂停。载入时的 keyFrame seek 已把
      // 画面定位到原进度，直接暂停即可——不再做 AnyFrame 精确 seek /
      // renderVideo（那会让 mdk 停在「暂停但仍在 seek/decode」的半死状态，
      // 导致之后点播放无响应）。
      if (!wasPlaying) {
        _player.state = AdapterPlaybackState.paused;
        _position = Duration(milliseconds: posMs);
        _positionNotifier.value = _position;
        _syncPlayState();
        // 管线刚重建，标记「恢复播放前先 seek 兜底」
        _pendingResumeSeek = true;
      }
    } catch (e) {
      LogService().log('Player', '回前台重载恢复失败: $e');
    } finally {
      _recoveringVideo = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // 捕获当前适配器：延迟释放期间若引擎字段被替换，也不能释放错对象。
    final player = _player;
    // 先停止播放器，确保音频立即停止；适配器内部会忽略已销毁后的写入。
    try {
      player.state = AdapterPlaybackState.stopped;
    } catch (_) {}

    _positionTimer?.cancel();
    _diagnosticTimer?.cancel();
    _sampleTimer?.cancel();
    _danmakuRetryTimer?.cancel();
    // 同线路重载清理（v1.1.245）：取消 pending 定时器防泄漏
    _streamReload.cancelPending();
    _cancelStallWatchdog();
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    _autoHide.dispose();
    // 兜底上报：异常 pop/系统 kill 未走 onConfirm 时，尽力补一次「停止」
    final reportSvc = _reportService;
    final reportId = _reportItemId;
    if (_shouldReportPlayback &&
        _reportStarted &&
        reportSvc != null &&
        reportId != null) {
      reportSvc
          .reportPlaybackStopped(
            itemId: reportId,
            playSessionId: _playSessionId,
            mediaSourceId: _reportMediaSourceId,
            positionMs: _player.position,
          )
          .catchError((_) => false);
    }
    _stopReportTimer();
    _speedMeter?.stop();
    _lockController.removeListener(_onLockStateChanged);
    _lockController.dispose();
    _hotkeyFocusNode.dispose();
    _controlsFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _controlsRootFocusNode.dispose();
    _topBarRootFocusNode.dispose();
    _nextEpisodeFocusNode.dispose();
    _danmakuButtonFocusNode.dispose();
    _subtitleButtonFocusNode.dispose();
    _audioButtonFocusNode.dispose();
    _speedButtonFocusNode.dispose();
    _episodeButtonFocusNode.dispose();
    _versionButtonFocusNode.dispose();
    _selectorFirstFocusNode.dispose();
    _selectorPanelRootFocusNode.dispose();
    _subtitleStyleButtonFocusNode.dispose();
    _kernelButtonFocusNode.dispose();
    _skipPromptFocusNode.dispose();
    _segmentMarkFirstFocusNode.dispose();
    _segmentMarkScopeNode.dispose();
    _subtitleDelayReloadTimer?.cancel();
    _subtitleStyleSaveTimer?.cancel();
    _subtitleStyleApplyTimer?.cancel();
    _heartbeatTimer?.cancel();
    _rateRestoreTimer?.cancel();
    _stopClockSync();
    _gestureHintTimer?.cancel();
    _gestureBarTimer?.cancel();
    _roomInfoTimeout?.cancel();
    _stopStreamRetry();
    _countRetryScheduler.cancel();
    _rtmSubscription?.cancel();
    _presenceSubscription?.cancel();
    _tracksSubscription?.cancel();
    _accelSub?.cancel();
    _stateSub?.cancel();
    _statusSub?.cancel();
    _eventSub?.cancel();
    try {
      _broadcastScrollController.dispose();
    } catch (_) {}

    // 关闭深度诊断日志，避免全局 handler 泄漏
    if (_deepLogActive) {
      _deepLogActive = false;
      _stopDeepDiagnostics();
    }

    // 作废进行中的换源音量渐变，避免 dispose 续体继续写音量
    _fader.cancel();

    // 释放 ValueNotifier（包 try-catch 确保后续代码执行）
    try {
      _positionNotifier.dispose();
    } catch (_) {}
    try {
      _durationNotifier.dispose();
    } catch (_) {}
    try {
      _brightnessNotifier.dispose();
    } catch (_) {}
    try {
      _volumeNotifier.dispose();
    } catch (_) {}
    try {
      _isPlayingNotifier.dispose();
    } catch (_) {}
    try {
      _broadcastVersion.dispose();
    } catch (_) {}
    try {
      _syncEventsVersion.dispose();
    } catch (_) {}
    try {
      _showBrightnessBarNotifier.dispose();
    } catch (_) {}
    try {
      _showVolumeBarNotifier.dispose();
    } catch (_) {}

    // 恢复屏幕亮度
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}

    // 离开播放器时退出窗口全屏，回到普通窗口
    if (_isWindowFullscreen) {
      _isWindowFullscreen = false;
      _windowFullscreenService.setFullScreen(false);
    }

    // 释放锁屏保持
    try {
      WakelockPlus.disable();
    } catch (_) {}

    // 清理 RTM
    if (widget.roomCode != null) {
      try {
        final rtmService = ref.read(rtmServiceProvider);
        if (_rtmChannel != null) {
          rtmService.unsubscribe(_rtmChannel!);
        }
        rtmService.logout();
      } catch (_) {}
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    WidgetsBinding.instance.removeObserver(this);
    // 延迟释放 native player（v1.1.69）：state=stopped 已在 dispose 开头
    // 同步执行（音频立即停）；fvp dispose 内部 updateTexture(width:-1)
    // 会触发 ReleaseRT，与 platform view 销毁时序的 surfaceDestroyed
    // 并发是「返回播放页闪退回桌面」的主嫌。错开 150ms 让 surface 先
    // 释放；随后由适配器等待进行中的 prepare/updateTexture 落定再 delete
    // （加载中返回时 prepare 可能仍在原生线程运行）。
    unawaited(_disposePlayerAfterDelay(player));
    super.dispose();
  }

  Future<void> _disposePlayerAfterDelay(PlayerAdapter player) async {
    if (_playerDisposeStarted) return;
    _playerDisposeStarted = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final disposable = player is AsyncDisposablePlayer
          ? player as AsyncDisposablePlayer
          : null;
      if (disposable != null) {
        await disposable.disposeAsync().timeout(const Duration(seconds: 5));
      } else {
        player.dispose();
      }
    } catch (_) {}
  }

  bool get _canControlPlayback {
    if (widget.roomCode == null) return true;
    return _isHost;
  }

  /// 手机版长按临时倍速是否可用：仅手机、非 TV、未锁定、可控、无面板打开。
  bool get _speedBoostGestureEnabled {
    if (!PlayerPlatform.mediaLongPressSpeedBoost) return false;
    if (_lockController.locked || !_canControlPlayback) return false;
    if (ref.read(settingsProvider).tvMode) return false;
    if (_showSubtitleMenu ||
        _showAudioMenu ||
        _showKernelMenu ||
        _showSpeedMenu ||
        _showSubtitleStyleMenu ||
        _showEpisodeMenu ||
        _showVersionMenu ||
        _showDecodeModeMenu ||
        _showBrightnessBarNotifier.value ||
        _showVolumeBarNotifier.value) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // 视频输出档位（设置页/TV 底部弹窗）变化时即时应用：
    // 切纹理/直通档 → 按 tunnel 参数重建纹理；切 SurfaceView 档 →
    // 释放纹理并由 _buildVideoArea 分支重建 platform view。
    ref.listen(settingsProvider.select((s) => s.videoOutput), (prev, next) {
      if (prev != next) {
        _applyVideoOutputMode();
      }
    });
    return TvBackConfirm(
      // TV：首按提示、2 秒窗口内第二按才确认退出；非 TV 直接确认（现状）
      enabled: ref.watch(settingsProvider.select((s) => s.tvMode)),
      // 选择器/标记面板打开时：返回键收起面板并把焦点还给来源控件，不退出播放器
      onBack: () {
        if (_showSegmentMarkPanel) {
          _closeSegmentMarkPanel();
          return true;
        }
        if (_showSubtitleMenu ||
            _showAudioMenu ||
            _showKernelMenu ||
            _showSpeedMenu ||
            _showSubtitleStyleMenu ||
            _showEpisodeMenu ||
            _showVersionMenu) {
          _closeSelectorPanel();
          _resetHideTimer();
          return true;
        }
        return false;
      },
      onConfirm: () async {
        // 退出前按「停止」上报（带最终位置）→ 服务器写入续播/自动已观看
        await _reportStopped();
        final shouldPop = await _confirmLeaveRoom();
        if (shouldPop && mounted) Navigator.pop(context);
      },
      child: PlayerHotkey(
        onTogglePlayPause: _handleHotkeyTogglePlayPause,
        onEscape: _isWindowFullscreen ? _exitWindowFullscreen : null,
        tvMode: ref.watch(settingsProvider.select((s) => s.tvMode)),
        controlsVisible: _showControls,
        onSeekRelative: (deltaMs) => _seekRelative(deltaMs),
        onVolumeDelta: _handleHotkeyVolumeDelta,
        onShowControls: _showControlsForTv,
        focusNode: _hotkeyFocusNode,
        seekFocusNode: _controlsFocusNode,
        playPauseFocusNode: _playPauseFocusNode,
        // 左右组跨界定向：满宽 Spacer 使几何导航跳回上方滑杆
        hopRight: (
          from: (_hasEpisodeList && _totalEpisodeCount > 1)
              ? _nextEpisodeFocusNode
              : _playPauseFocusNode,
          to: _danmakuButtonFocusNode,
        ),
        hopLeft: (
          from: _danmakuButtonFocusNode,
          to: (_hasEpisodeList && _totalEpisodeCount > 1)
              ? _nextEpisodeFocusNode
              : _playPauseFocusNode,
        ),
        child: Scaffold(
          backgroundColor:
              _usesMpvNativeSurface ? Colors.transparent : Colors.black,
          // 视频手势（点屏/双击/拖动 seek/音量亮度）在 _buildVideoArea
          // 内只包视频层：若放 body 层做浮层/控制条的祖先，拖动起点在
          // 字幕/音轨/倍速面板内时祖先 drag recognizer 先进手势竞技场
          // 并抢走拖动，面板 ListView 滚不动（且误触音量/亮度）。
          body: _buildResponsiveLayout(),
        ),
      ),
    );
  }

  Widget _buildResponsiveLayout() {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait &&
            PlayerPlatform.isMobile;

    final showPanel = widget.roomCode != null && _showPanel;

    if (isPortrait && showPanel) {
      // 手机竖屏：视频在上，资源面板在下
      return Column(
        children: [
          Expanded(flex: 3, child: _buildVideoArea()),
          SizedBox(
            height: 280,
            child: _buildResourcePanel(),
          ),
        ],
      );
    } else if (showPanel) {
      // 桌面/横屏：视频在左，资源面板在右
      return Row(
        children: [
          Expanded(flex: 3, child: _buildVideoArea()),
          SizedBox(
            width: 320,
            child: _buildResourcePanel(),
          ),
        ],
      );
    } else {
      return _buildVideoArea();
    }
  }

  /// SurfaceView 通道视频内容：fvp/video-view platform view（绕过
  /// Flutter 纹理合成，独立显示层，TV 全分辨率扫描输出）。
  ///
  /// - 尺寸未知时先转圈，_syncVideoNativeSize 拿到 mediaInfo 尺寸后
  ///   setState 重建；
  /// - 用 AspectRatio 按视频比例给 platform view 定框（SurfaceView
  ///   surface buffer 固定为 creationParams 的视频分辨率，合成器按
  ///   视图矩形缩放）；_videoFit 的 fill/cover 裁剪在此档位不生效，
  ///   统一按 contain——platform view 不参与 Flutter Transform。
  Widget _buildSurfaceViewVideo() {
    // 两阶段重建的 detach 窗口：旧 view 已卸下，等 settle 后 attach
    if (_surfaceDetached) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    final size = _videoNativeSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    // 渲染尺寸夹紧（1.1.198 hdrGlWorkaround）：HDR 内容 + 开关开启时
    // SurfaceView buffer contain-fit 到显示器物理尺寸（fvp#379 size
    // clamp），降低弱 GPU 上 SurfaceFlinger 合成负载。SDR/开关关时
    // 恒原生尺寸。
    final clampTarget =
        (ref.read(settingsProvider).hdrGlWorkaround && _hdrContent)
            ? _clampedRenderSize(size)
            : null;
    final direct = _surfaceViewDirectWrite;
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: FvpSurfaceView(
          nativeHandle: _player.nativeHandle,
          videoWidth: (clampTarget?.width ?? size.width).toInt(),
          videoHeight: (clampTarget?.height ?? size.height).toInt(),
          // 直写档恒 true；普通 SurfaceView 档仅 EGL 故障（mdk
          // eglChooseConfig 3004 → GL presenter 无效）时直写，绕开 mdk EGL；
          // 正常时走 GL 以保留 snapshot 回读等能力
          tunnel: direct,
          epoch: _videoSurfaceEpoch,
          onCreated: () {
            if (!mounted) return;
            _surfaceViewCreated = true;
            final vw = (clampTarget?.width ?? size.width).toInt();
            final vh = (clampTarget?.height ?? size.height).toInt();
            LogService().log(
                'Diag',
                'surfaceCreated 绑定完成 (epoch=$_videoSurfaceEpoch '
                    'size=${size.width.toInt()}x${size.height.toInt()}'
                    '${clampTarget != null ? ' → buffer ${vw}x$vh' : ''})');
            // 平台视图首次插入会把视频层放到浮层之上（hybrid composition
            // 重新合成）：补帧让控制条/顶栏回到视频之上，并再补一帧覆盖
            // nativeSetSurface 异步落定 + 解码器重开的窗口。
            _nudgeOverlayRepaint(
                '首次 surfaceCreated (epoch=$_videoSurfaceEpoch)');
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _nudgeOverlayRepaint('surface 后 300ms');
            });
          },
        ),
      ),
    );
  }

  void _onMpvSurfaceCreated() {
    if (!mounted) return;
    LogService().log('Diag', 'mpv 原生 Surface 平台视图已创建');
    _nudgeOverlayRepaint('mpv 原生 Surface 创建后');
  }

  /// MPV 原生 Surface（鸿蒙 XComponent / Android SurfaceView / Windows HWND）：
  /// mpv 直出到平台原生 Surface，Flutter 控件/弹幕叠加在上方。
  Widget _buildMpvNativeVideo() {
    final size = _videoNativeSize;
    final surface = Platform.isAndroid
        ? HimiMpvAndroidSurfaceView(
            onPlatformViewCreated: (_) => _onMpvSurfaceCreated(),
          )
        : Platform.isWindows
            ? const HimiMpvWindowsSurfaceView()
            : HimiMpvSurfaceView(
                onPlatformViewCreated: (_) => _onMpvSurfaceCreated(),
              );

    // 必须先创建原生 Surface，mpv 才能输出 video-params。
    // 无论尺寸是否就绪都保持同一 Widget 层级：尺寸变化只更新 AspectRatio，
    // 不能拆掉 HimiMpvWindowsSurfaceView（否则会销毁 libmpv 正在使用的 HWND）。
    final aspectRatio = size != null && size.width > 0 && size.height > 0
        ? size.width / size.height
        : 16 / 9;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: surface,
      ),
    );
  }

  Widget _buildMediaKitVideo(VideoController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoSize = _videoNativeSize;
        if (videoSize != null && videoSize.width > 0 && videoSize.height > 0) {
          final container = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
          );
          final key = '${_videoFit.index}:'
              '${container.width.round()}x${container.height.round()}:'
              '${videoSize.width.round()}x${videoSize.height.round()}';
          if (key != _lastMediaKitFitKey) {
            _lastMediaKitFitKey = key;
            final player = _player;
            if (player is MediaKitVideoFitApplier) {
              (player as MediaKitVideoFitApplier).applyVideoFit(
                _videoFit,
                container: container,
                video: videoSize,
              );
            }
          }
        }
        return Video(
          controller: controller,
          controls: null,
          fit: _videoFit == BoxFit.cover ? BoxFit.contain : _videoFit,
          wakelock: false,
        );
      },
    );
  }

  Widget _buildVideoArea() {
    final videoAreaTvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final clockFormat = ref.watch(
      settingsProvider.select((s) => s.topBarClockFormat),
    );
    final videoAreaPhoneControls = PlayerScreen.isMobilePhoneControls(
      tvMode: videoAreaTvMode,
      mobilePlatform: PlayerPlatform.isMobile,
    );
    // 选择器面板几何：选集面板上下右贴边铺满，其余面板避开顶栏/控制条
    final panelBox = PlayerScreen.selectorPanelBox(
      fullBleed: _showEpisodeMenu,
      safeTop: MediaQuery.of(context).padding.top,
      safeBottom: MediaQuery.of(context).padding.bottom,
    );
    // 视频 / 占位文字
    final erikaPlayer = _player is ErikaPlayerProvider
        ? (_player as ErikaPlayerProvider).erikaPlayer
        : null;
    final mediaKitController = _player is MediaKitPlayerProvider
        ? (_player as MediaKitPlayerProvider).mediaKitController
        : null;
    final videoContent = _isPlayerReady ||
            (!_hasEpisodeList && widget.roomCode == null)
        ? Center(
            child: _switchingEngine
                ? const SizedBox.shrink()
                : _currentEngine == PlayerEngine.erika && erikaPlayer != null
                    // Erika：原生 surface/TextureView（自绘；含位图字幕 PGS 合成）
                    ? ErikaVideoView(player: erikaPlayer)
                    : _currentEngine == PlayerEngine.mediaKit &&
                            mediaKitController != null
                        ? _buildMediaKitVideo(mediaKitController)
                        : _usesMpvNativeSurface
                            ? _buildMpvNativeVideo()
                            : _usesSurfaceView
                                ? _buildSurfaceViewVideo()
                                : ValueListenableBuilder<int?>(
                                    valueListenable: _player.textureId,
                                    builder: (context, textureId, child) {
                                      if (textureId == null) {
                                        return const Center(
                                          child: CircularProgressIndicator(
                                              color: Colors.white54),
                                        );
                                      }
                                      // 无视频尺寸时先按原尺寸渲染，拿到尺寸后 setState 重新渲染
                                      if (_videoNativeSize == null) {
                                        return Center(
                                          child: Texture(textureId: textureId),
                                        );
                                      }
                                      return LayoutBuilder(
                                        builder: (context, constraints) {
                                          final containerW =
                                              constraints.maxWidth;
                                          final containerH =
                                              constraints.maxHeight;
                                          final renderW =
                                              _videoNativeSize!.width;
                                          final renderH =
                                              _videoNativeSize!.height;

                                          switch (_videoFit) {
                                            case BoxFit.none:
                                              return Texture(
                                                  textureId: textureId);
                                            case BoxFit.fill:
                                              return Center(
                                                child: Transform(
                                                  alignment: Alignment.center,
                                                  transform:
                                                      Matrix4.diagonal3Values(
                                                    containerW / renderW,
                                                    containerH / renderH,
                                                    1.0,
                                                  ),
                                                  child: UnconstrainedBox(
                                                    child: SizedBox(
                                                      width: renderW,
                                                      height: renderH,
                                                      child: Texture(
                                                          textureId: textureId),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            case BoxFit.cover:
                                              final scale = max(
                                                  containerW / renderW,
                                                  containerH / renderH);
                                              return ClipRect(
                                                child: Center(
                                                  child: Transform.scale(
                                                    scale: scale,
                                                    child: UnconstrainedBox(
                                                      child: SizedBox(
                                                        width: renderW,
                                                        height: renderH,
                                                        child: Texture(
                                                            textureId:
                                                                textureId),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            default: // contain
                                              return FittedBox(
                                                fit: BoxFit.contain,
                                                child: SizedBox(
                                                  width: renderW,
                                                  height: renderH,
                                                  child: Texture(
                                                      textureId: textureId),
                                                ),
                                              );
                                          }
                                        },
                                      );
                                    },
                                  ),
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                Text(
                  '请从资源面板选择要播放的内容',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              ],
            ),
          );

    // 指针操作顺延自动隐藏：按下暂停计时（按住不动不隐藏），
    // 松手/取消重新起算 5 秒
    return Listener(
      onPointerDown: (_) => _autoHide.notePointerDown(),
      onPointerUp: (_) => _autoHide.notePointerUp(),
      onPointerCancel: (_) => _autoHide.notePointerUp(),
      child: Stack(
        children: [
          // 视频手势层（VideoGestureLayer：只包视频层，见其类注释）
          VideoGestureLayer(
            onTap: _onVideoAreaTap,
            // 锁定中：双击/横滑(进度)/纵滑(亮度音量)全部解除绑定
            onDoubleTap: _lockController.locked ? null : _onDoubleTap,
            onHorizontalDragUpdate:
                _lockController.locked ? null : _onHorizontalDragUpdate,
            onHorizontalDragEnd:
                _lockController.locked ? null : _onHorizontalDragEnd,
            // Windows 取消音量/亮度垂直手势（改用控制条滑杆），移动平台保留
            onVerticalDragStart:
                PlayerPlatform.verticalVolumeBrightnessGesture &&
                        !_lockController.locked
                    ? _onVerticalDragStart
                    : null,
            onVerticalDragUpdate:
                PlayerPlatform.verticalVolumeBrightnessGesture &&
                        !_lockController.locked
                    ? _onVerticalDragUpdate
                    : null,
            onVerticalDragEnd: PlayerPlatform.verticalVolumeBrightnessGesture &&
                    !_lockController.locked
                ? _onVerticalDragEnd
                : null,
            // 手机版长按：左/右 1/3 标记片头/片尾，中间临时 2× 倍速
            onLongPressStart:
                (_speedBoostGestureEnabled || _segmentMarkGestureEnabled)
                    ? _onVideoLongPressStart
                    : null,
            onLongPressEnd:
                (_speedBoostGestureEnabled || _segmentMarkGestureEnabled)
                    ? _onVideoLongPressEnd
                    : null,
            onLongPressCancel:
                (_speedBoostGestureEnabled || _segmentMarkGestureEnabled)
                    ? _onSpeedBoostEnd
                    : null,
            child: videoContent,
          ),

          // 黑边遮罩（视频层之上、控件之下）：SurfaceView 档接管视频层后，
          // 视频矩形之外的区域引擎不再重绘，会裸露"进入播放器那一刻"含
          // 控件的死帧（隐藏后残留）；整屏铺满 + 视频矩形透明把死帧盖死
          // （见 LetterboxBarsCover）。仅 SurfaceView 档需要。
          if ((_usesSurfaceView || _usesMpvNativeSurface) &&
              !_surfaceDetached &&
              _videoNativeSize != null &&
              _videoNativeSize!.width > 0 &&
              _videoNativeSize!.height > 0)
            Positioned.fill(
              child: LetterboxBarsCover(
                aspect: _videoNativeSize!.width / _videoNativeSize!.height,
              ),
            ),

          // 加载指示器（渲染在控件层之下：转圈期间顶栏/底栏仍可点返回）。
          // 时长未知的转码/直播流在起播后必须隐藏，不能只看 duration==0。
          if (PlayerScreen.shouldShowInitialLoadingSpinner(
            durationMs: _duration.inMilliseconds,
            positionMs: _position.inMilliseconds,
            playerReady: _isPlayerReady,
            startedOnce: _hasStartedPlayback,
            playing: _player.state == AdapterPlaybackState.playing,
          ))
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),

          // 切集遮罩：掩盖旧帧残留，新帧就绪后自动消失（同样在控件之下）
          if (_isSwitchingMedia)
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white54),
              ),
            ),

          // 弹幕层（视频之上、控件之下；IgnorePointer 不抢手势）
          // Erika 档改由引擎原生 GPU 合成 → 不挂 Flutter 层
          if (_danmakuOn &&
              _danmakuComments.isNotEmpty &&
              _currentEngine != PlayerEngine.erika)
            Positioned.fill(
              child: Consumer(
                // 局部重建点：行数/屏蔽/上限/三滑杆任一变化只刷新弹幕层
                builder: (context, watchRef, _) {
                  final s = watchRef.watch(settingsProvider);
                  return DanmakuOverlay(
                    comments: _danmakuComments,
                    config: PlayerScreen.danmakuTimelineConfig(s),
                    position: _positionNotifier,
                    playing: _isPlayingNotifier,
                    speed: s.danmakuSpeed,
                    fontSizeScale: s.danmakuFontSize,
                    opacity: s.danmakuOpacity,
                  );
                },
              ),
            ),

          // TopBar（渐变浮层；锁定中隐藏，手机版锁钮在下栏）。
          // 加载/切集转圈期间强制显示：黑屏时用户仍可点返回退出
          if ((_showControls || _isLoadingMaskVisible) &&
              !_lockController.locked)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Focus(
                // 顶栏根锚点：自动隐藏焦点判定根（OK 按键事件在此顺延计时）
                focusNode: _topBarRootFocusNode,
                skipTraversal: true,
                onKeyEvent: _autoHide.onKeyEvent,
                child: _buildTopBar(),
              ),
            ),

          PlayerClockLayer(format: clockFormat, tvMode: videoAreaTvMode),

          // 左缘锁/解锁钮（手机版已移入底栏左数显列；此处置留给桌面；
          // TV 无锁）
          if (!videoAreaPhoneControls &&
              _showControls &&
              PlayerScreen.showLockButton(tvMode: videoAreaTvMode))
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: PlayerLockButton(
                  locked: _lockController.locked,
                  onToggle: _toggleScreenLock,
                ),
              ),
            ),

          // 解码模式选择面板
          if (_showDecodeModeMenu)
            Positioned(
              top: MediaQuery.of(context).padding.top + 48,
              right: 12,
              child: DecodeModePanel(
                onSwitchMode: _switchDecodeMode,
              ),
            ),

          // 手势提示浮层（快进快退/双击播放暂停）
          if (_showGestureOverlay)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: _buildGestureHint(),
            ),

          // 长按临时倍速指示（手机版，画面中央玻璃小胶囊）
          if (_speedBoostActive)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(child: _buildSpeedBoostChip()),
              ),
            ),

          // 亮度柱式进度条（右侧）
          ValueListenableBuilder<bool>(
            valueListenable: _showBrightnessBarNotifier,
            builder: (context, show, _) =>
                show ? _buildBrightnessBar() : const SizedBox.shrink(),
          ),

          // 音量柱式进度条（左侧）
          ValueListenableBuilder<bool>(
            valueListenable: _showVolumeBarNotifier,
            builder: (context, show, _) =>
                show ? _buildVolumeBar() : const SizedBox.shrink(),
          ),

          // TV 长按进度条：居中的片头/片尾标记玻璃面板
          if (_showSegmentMarkPanel)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeSegmentMarkPanel,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: FocusScope(
                      node: _segmentMarkScopeNode,
                      skipTraversal: true,
                      onKeyEvent: _autoHide.onKeyEvent,
                      child: FocusTraversalGroup(
                        child: SegmentMarkPanel(
                          positionMs: _position.inMilliseconds,
                          introEndMs: _segmentIntroEndMs,
                          creditsStartMs: _segmentCreditsStartMs,
                          firstFocusNode: _segmentMarkFirstFocusNode,
                          onSelect: _onSegmentMarkSelected,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Controls（底部渐变浮层，仅视频区域底部；锁定中隐藏——手机版
          // 例外：底栏在锁定时只保留锁钮以便解锁，见 _buildControls）。
          // 加载/切集转圈期间强制显示（同 TopBar）
          if ((_showControls || _isLoadingMaskVisible) &&
              (!_lockController.locked || videoAreaPhoneControls) &&
              (_isPlayerReady || (!_hasEpisodeList && widget.roomCode == null)))
            Positioned(bottom: 0, left: 0, right: 0, child: _buildControls()),

          // 字幕/音轨/倍速/选集/引擎选择器：右侧玻璃浮层（可滚动；随控制条显隐）。
          // 位于控制条之后：选集面板全高（top/bottom/right 贴边）时绘制在
          // 底部控制条之上（进度条右端被面板盖住，对齐参考观感）。
          if (_showControls &&
              !_lockController.locked &&
              !_switchingEngine &&
              (_showSubtitleMenu ||
                  _showAudioMenu ||
                  _showKernelMenu ||
                  _showSpeedMenu ||
                  _showSubtitleStyleMenu ||
                  _showEpisodeMenu ||
                  _showVersionMenu))
            Positioned(
              top: panelBox.top,
              bottom: panelBox.bottom,
              right: panelBox.right,
              width: PlayerScreen.selectorPanelWidth(
                MediaQuery.sizeOf(context).width,
              ),
              child: Focus(
                // 面板根锚点：自动隐藏判定"焦点在面板内"的依据；
                // 面板内按键（含 TV OK）顺延自动隐藏计时
                focusNode: _selectorPanelRootFocusNode,
                skipTraversal: true,
                onKeyEvent: _autoHide.onKeyEvent,
                child: SelectorSidePanel(
                  // 全高贴边：右侧圆角放平，避免玻璃圆角悬在屏幕边缘
                  borderRadius: _showEpisodeMenu
                      ? const BorderRadius.horizontal(left: Radius.circular(16))
                      : const BorderRadius.all(Radius.circular(16)),
                  title: _showKernelMenu
                      ? '播放内核'
                      : _showSubtitleMenu
                          ? '字幕'
                          : _showAudioMenu
                              ? '音轨'
                              : _showEpisodeMenu
                                  ? '选集'
                                  : _showSubtitleStyleMenu
                                      ? '显示调节'
                                      : _showVersionMenu
                                          ? '版本'
                                          : '倍速',
                  child: _showKernelMenu
                      ? PlayerKernelPanel(
                          current: _currentEngine,
                          onSelect: (engine) {
                            unawaited(_switchPlayerKernel(engine));
                          },
                          onClose: _closeSelectorPanel,
                          focusNode: _selectorFirstFocusNode,
                        )
                      : _showSubtitleStyleMenu
                          ? _buildDisplayAdjustPanel()
                          : _showSubtitleMenu
                              ? SubtitleMenuPanel(
                                  player: _player,
                                  subtitleStreams: _embySubtitleStreams,
                                  activeSubtitleIndex: _activeSubtitleIndex,
                                  useServerBurnIn: _useServerSubtitleBurnIn,
                                  itemId: _episodes.isNotEmpty &&
                                          _currentEpisodeIndex >= 0 &&
                                          _currentEpisodeIndex <
                                              _episodes.length
                                      ? _episodes[_currentEpisodeIndex].id
                                      : widget.itemId,
                                  mediaSourceId: widget.mediaSourceId,
                                  token: _currentToken,
                                  focusNode: _selectorFirstFocusNode,
                                  onSubtitleSelected: (index) {
                                    if (index == null) {
                                      _player.activeSubtitleTracks = [];
                                      _useServerSubtitleBurnIn = false;
                                      _activeSubtitleIndex = null;
                                      _activeLocalSubtitlePath = null;
                                      _subtitleDelayReloadTimer?.cancel();
                                    } else {
                                      _selectEmbySubtitle(index);
                                    }
                                  },
                                  onLoadLocal: _loadLocalSubtitle,
                                  onClose: _closeSelectorPanel,
                                )
                              : _showAudioMenu
                                  ? AudioTrackMenuPanel(
                                      player: _player,
                                      audioStreams: _embyAudioStreams,
                                      focusNode: _selectorFirstFocusNode,
                                      onAudioSelected: _selectEmbyAudio,
                                      onClose: _closeSelectorPanel,
                                    )
                                  : _showEpisodeMenu
                                      ? EpisodeSelectPanel(
                                          episodes: _episodes,
                                          currentIndex: _currentEpisodeIndex,
                                          focusNode: _selectorFirstFocusNode,
                                          onEpisodeSelected: (index) {
                                            _switchToEpisode(index);
                                            _closeSelectorPanel();
                                          },
                                        )
                                      : _showVersionMenu
                                          ? VersionMenuPanel(
                                              sources: _currentMediaSources,
                                              activeSourceId:
                                                  _activeMediaSourceId,
                                              focusNode:
                                                  _selectorFirstFocusNode,
                                              onSourceSelected:
                                                  _switchMediaSource,
                                              onClose: _closeSelectorPanel,
                                            )
                                          : SpeedMenuPanel(
                                              current: _speed,
                                              focusNode:
                                                  _selectorFirstFocusNode,
                                              onSelected: _applySpeed,
                                            ),
                ),
              ),
            ),

          // 同步调试面板（单人模式 + 房间模式均可显示）
          if (ref.watch(settingsProvider).showSyncDebug)
            Positioned(
              left: _debugPanelX,
              top: _debugPanelY,
              child: SyncDebugPanel(
                isHost: _isHost,
                rtmChannel: _syncRtmChannel,
                rtmStatus: _syncRtmStatus,
                metadataTestResult: _syncMetadataTestResult,
                clockOffsetMs: _clockOffset.offsetMs,
                clockRttMs: _clockOffset.bestRttMs,
                clockCalibrated: _clockOffset.isCalibrated,
                voStatus: _voStatus,
                hdrType: _hdrType,
                isSinglePlayer: widget.roomCode == null,
                // 播放状态
                playbackState: _playbackState,
                mediaStatusStr: _mediaStatusStr,
                positionMs: _positionMs,
                durationMs: _durationMs,
                bufferedMs: _bufferedMs,
                mediaBitrate: _mediaBitrate,
                mediaFormat: _mediaFormat,
                // 视频信息
                videoCodecName: _videoCodecName,
                videoResolution: _videoResolution,
                videoFps: _videoFps,
                videoBitrate: _videoBitrate,
                pixelFormat: _pixelFormat,
                doviProfile: _doviProfile,
                // 音频信息
                audioCodecName: _audioCodecName,
                audioSampleRate: _audioSampleRate,
                audioChannels: _audioChannels,
                audioBitrate: _audioBitrate,
                stereoDownmix: _stereoDownmix,
                audioFilter: _audioFilterText,
                textureId: _player.textureId.value,
                textureSize: _textureSizeText,
                videoOutput: _effectiveVideoOutput(),
                renderTarget: _renderTargetDesc,
                videoFilter: _videoFilterText,
                snapshotInfo: _snapshotInfo,
                // Android：mdk snapshot 在 GL 异常设备上触发 native crash
                // （无法 try/catch），隐藏截帧入口；其他平台保留取证能力
                onSnapshot: Platform.isAndroid ? null : _probeSnapshot,
                // 解码器
                decodeMode: ref.read(settingsProvider).decodeMode,
                actualVideoDecoders: _actualVideoDecoders,
                mdkRawDecoder: _mdkRawDecoder,
                decoderReport: _decoderReport,
                audioBackend: _audioBackend,
                dvCapability: _embyVideoStream?.isDolbyVision == true
                    ? _dvProbe.summary
                    : '',
                buildSummary: _buildSummary,
                // 卡顿诊断
                stallSummary: _diagSummary,
                bufProgress: _bufProgress,
                deepLogActive: _deepLogActive,
                onExportStutter: _exportFullDiagnostics,
                onDrag: (delta) {
                  setState(() {
                    _debugPanelX += delta.dx;
                    _debugPanelY += delta.dy;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final settings = ref.watch(settingsProvider);
    final mobilePlatform = PlayerPlatform.isMobile;
    final phoneControls = PlayerScreen.isMobilePhoneControls(
      tvMode: settings.tvMode,
      mobilePlatform: mobilePlatform,
    );
    return PlayerTopBar(
      title: _currentEpisodeTitle,
      showKernelButton: !_switchingKernel,
      kernelLabel: _currentEngine.shortLabel,
      kernelMenuOpen: _showKernelMenu,
      kernelFocusNode: _kernelButtonFocusNode,
      onToggleKernel: _toggleKernelMenu,
      networkSpeedText: settings.showNetworkSpeed && _networkSpeedBps != null
          ? NetworkSpeedMeter.formatMBs(_networkSpeedBps!)
          : null,
      // Erika 无解码档位（自动硬解/软解回退）→ 隐藏解码控件
      showDecodeButton:
          PlayerScreen.showDecodeButton(tvMode: settings.tvMode) &&
              _currentEngine != PlayerEngine.erika,
      decodeMenuOpen: _showDecodeModeMenu,
      // TV 模式「显示调节」入口移到底部控制条（弹幕与字幕之间），顶栏隐藏
      showSubtitleStyleButton:
          PlayerScreen.showTopSubtitleStyleButton(tvMode: settings.tvMode),
      subtitleStyleMenuOpen: _showSubtitleStyleMenu,
      subtitleStyleFocusNode: _subtitleStyleButtonFocusNode,
      onToggleSubtitleStyle: _toggleSubtitleStyleMenu,
      glassEnabled: settings.glassUi,
      // Erika 画面缩放控件暂不可用 → 隐藏
      showVideoFitButton: widget.roomCode == null &&
          !settings.tvMode &&
          _currentEngine != PlayerEngine.erika,
      videoFitIcon: _videoFitIcons[_videoFitModes.indexOf(_videoFit)],
      videoFitLabel: _videoFitLabels[_videoFitModes.indexOf(_videoFit)],
      onCycleVideoFit: _cycleVideoFit,
      // 倍速（网速右侧）/ 转屏（画面比例右侧）：手机版移入顶栏
      showSpeedButton: PlayerScreen.showTopSpeedButton(
        tvMode: settings.tvMode,
        mobilePlatform: mobilePlatform,
        isRoom: widget.roomCode != null,
      ),
      speedLabel: SpeedMenuPanel.formatSpeedLabel(_speed),
      speedMenuOpen: _showSpeedMenu,
      speedButtonFocusNode: _speedButtonFocusNode,
      onToggleSpeed: _toggleSpeedMenu,
      showRotateButton: phoneControls,
      rotateButtonIcon: PlayerScreen.rotateButtonIcon,
      onRotate: _toggleOrientation,
      showShare: widget.roomCode != null,
      onBack: () async {
        final shouldPop = await _confirmLeaveRoom();
        if (shouldPop && context.mounted) Navigator.pop(context);
      },
      onToggleDecode: () =>
          setState(() => _showDecodeModeMenu = !_showDecodeModeMenu),
      onShare: _showShareRoomDialog,
      reserveClockSpace: settings.tvMode && settings.topBarClockFormat.enabled,
    );
  }

  /// 顶栏左上角影视信息；无片单（直链播放）返回空串不渲染。
  String get _currentEpisodeTitle =>
      PlayerScreen.mediaTitleAt(_episodes, _currentEpisodeIndex);

  /// 顶栏「字幕样式」按钮：开关样式面板（与字幕/音轨/倍速/解码/选集互斥）。
  void _toggleSubtitleStyleMenu() {
    // 引擎重建中 [_player] 可能仍指向旧引擎；禁止打开面板，避免滑杆写入。
    if (_switchingEngine) return;
    setState(() {
      _showSubtitleStyleMenu = !_showSubtitleStyleMenu;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showDecodeModeMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
    });
    if (_showSubtitleStyleMenu) {
      _openSelectorPanel(_subtitleStyleButtonFocusNode);
    }
  }

  /// 倍速按钮（顶栏手机 / 底栏 TV・桌面共用）：开关倍速面板
  /// （与字幕/音轨/字幕样式/选集互斥）。
  void _toggleSpeedMenu() {
    setState(() {
      _showSpeedMenu = !_showSpeedMenu;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
    });
    if (_showSpeedMenu) {
      _openSelectorPanel(_speedButtonFocusNode);
    }
  }

  /// 顶栏「播放内核」胶囊：开关内核选择面板。
  void _toggleKernelMenu() {
    if (_switchingEngine || _switchingKernel) return;
    setState(() {
      _showSubtitleMenu = false;
      _showKernelMenu = !_showKernelMenu;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
      _showDecodeModeMenu = false;
    });
    if (_showKernelMenu) _openSelectorPanel(_kernelButtonFocusNode);
  }

  /// 切换播放内核：保留当前位置/音轨/字幕，失败时提示。
  Future<void> _switchPlayerKernel(PlayerEngine target) async {
    // HDR 内容必须走 MPV 原生 Surface 直出，用户手动切内核也不能绕过。
    if (_hdrContent &&
        target != PlayerEngine.mpv &&
        PlayerEngineFactory.isSupported(PlayerEngine.mpv)) {
      target = PlayerEngine.mpv;
    }
    if (_switchingKernel || _switchingEngine || target == _currentEngine) {
      return;
    }
    if (!PlayerEngineFactory.isSupported(target)) {
      if (mounted) showAppToast(context, '当前平台不支持 ${target.label}');
      return;
    }

    final previous = _currentEngine;
    final wasPlaying = _player.state == AdapterPlaybackState.playing;
    final positionMs = _player.position;
    final oldAudioPositions = List<int>.of(_player.activeAudioTracks);
    // 引擎的 activeAudioTracks 是「引擎轨表位置」；先换算成 Emby 流
    // index，重载后按同一流找新引擎位置（与字幕恢复保持一致）。
    final oldAudioStreamIndex = oldAudioPositions.isNotEmpty &&
            oldAudioPositions.first >= 0 &&
            oldAudioPositions.first < _embyAudioStreams.length
        ? _embyAudioStreams[oldAudioPositions.first].index
        : null;
    final oldSubtitleIndex = _activeSubtitleIndex;
    final oldLocalSubtitle = _activeLocalSubtitlePath;
    final oldVolume = _volume;
    final oldSpeed = _speed;

    Future<void> restoreTracks() async {
      final audioPos = oldAudioStreamIndex == null
          ? -1
          : _embyAudioStreams.indexWhere((s) => s.index == oldAudioStreamIndex);
      if (audioPos >= 0) {
        _selectEmbyAudio(audioPos);
      } else if (oldAudioPositions.isNotEmpty) {
        _player.activeAudioTracks = oldAudioPositions;
        _applyAudioFilterPolicy();
      }

      if (oldLocalSubtitle != null) {
        await _loadSubtitleFileIntoPlayer(oldLocalSubtitle);
      } else if (oldSubtitleIndex != null) {
        final pos =
            _embySubtitleStreams.indexWhere((s) => s.index == oldSubtitleIndex);
        if (pos >= 0) await _selectEmbySubtitle(pos);
      }
    }

    setState(() {
      _switchingKernel = true;
      _showKernelMenu = false;
      _showControls = true;
    });
    try {
      await _recreateEngineForLoad(target, ErikaOutputMode.auto);
      if (!mounted) return;

      if (_currentPlayUrl.isNotEmpty) {
        if (_currentToken.isNotEmpty) {
          _player.setHttpHeaders({'X-Emby-Token': _currentToken});
        }
        _player.media = _currentPlayUrl;
        await _player.prepare(startMs: positionMs);
        if (!mounted) return;
        await _ensureTexture();
        await _syncVideoNativeSize();
        await _waitSurfaceCreated();
        if (!mounted) return;
        _player.volume = (oldVolume / 100).clamp(0.0, 1.0);
        _player.playbackRate = oldSpeed;
        await restoreTracks();

        _player.state = wasPlaying
            ? AdapterPlaybackState.playing
            : AdapterPlaybackState.paused;
      }

      _syncPlayState();
    } catch (e) {
      LogService().log('Player', '切换内核失败: $previous -> $target: $e');
      if (mounted) {
        showAppToast(context, '切换内核失败，保留 ${previous.label}');
      }
      // 旧内核已释放；尽可能回滚到原内核并重载当前位置。
      if (mounted && _currentEngine != previous) {
        try {
          await _recreateEngineForLoad(previous, ErikaOutputMode.auto);
          if (_currentPlayUrl.isNotEmpty) {
            if (_currentToken.isNotEmpty) {
              _player.setHttpHeaders({'X-Emby-Token': _currentToken});
            }
            _player.media = _currentPlayUrl;
            await _player.prepare(startMs: positionMs);
            await _ensureTexture();
            await _syncVideoNativeSize();
            await _waitSurfaceCreated();
            if (!mounted) return;
            _player.volume = (oldVolume / 100).clamp(0.0, 1.0);
            _player.playbackRate = oldSpeed;
            await restoreTracks();
            _player.state = wasPlaying
                ? AdapterPlaybackState.playing
                : AdapterPlaybackState.paused;
          }
        } catch (rollbackError) {
          LogService().log('Player', '内核回滚失败: $rollbackError');
        }
      }
    } finally {
      if (mounted) {
        _skipPromptSuppressed = false;
        setState(() => _switchingKernel = false);
        _syncPlayState();
      }
    }
  }

  /// 选集按钮（底栏音轨右侧；仅单人模式多集时显示）：开关选集面板
  /// （与字幕/音轨/倍速/显示调节互斥）。
  void _toggleEpisodeMenu() {
    setState(() {
      _showEpisodeMenu = !_showEpisodeMenu;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showVersionMenu = false;
    });
    if (_showEpisodeMenu) {
      _openSelectorPanel(_episodeButtonFocusNode);
    }
  }

  /// 版本按钮（底栏弹幕右侧；仅非房间模式多版本时显示）：开关版本面板
  /// （与字幕/音轨/倍速/显示调节/选集互斥）。
  void _toggleVersionMenu() {
    if (_switchingEngine) return;
    setState(() {
      _showVersionMenu = !_showVersionMenu;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
    });
    if (_showVersionMenu) {
      _openSelectorPanel(_versionButtonFocusNode);
    }
  }

  // ── 弹幕：开关 / 加载 / 配置 ──

  /// 「显示调节」组合面板：字幕段 + 弹幕段（弹幕三值读写设置）。
  Widget _buildDisplayAdjustPanel() {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return DisplayAdjustPanel(
      subtitleScale: _subtitleScale,
      subtitleMarginY: _subtitleMarginY,
      subtitleDelayMs: _subtitleDelayMs,
      subtitleDelayEnabled: _activeSubtitleIndex != null,
      subtitleStyleDisabled: _erikaActiveSubtitleIsBitmap(),
      glassEnabled: _glassUiOn,
      onSubtitleScaleChanged: _onSubtitleScaleChanged,
      onSubtitleMarginChanged: _onSubtitleMarginYChanged,
      onSubtitleDelayChanged: _onSubtitleDelayChanged,
      onSubtitleReset: _onSubtitleStyleReset,
      danmakuSpeed: s.danmakuSpeed,
      danmakuFontSize: s.danmakuFontSize,
      danmakuOpacity: s.danmakuOpacity,
      onDanmakuSpeedChanged: _onDanmakuSpeedChanged,
      onDanmakuFontSizeChanged: _onDanmakuFontSizeChanged,
      onDanmakuOpacityChanged: _onDanmakuOpacityChanged,
      onDanmakuReset: () {
        notifier.update(
          danmakuSpeed: 1.0,
          danmakuFontSize: 0.5,
          danmakuOpacity: 0.8,
        );
        unawaited(_applyErikaDanmakuConfig());
      },
      focusNode: _selectorFirstFocusNode,
    );
  }

  /// 当前激活字幕是否为 PGS/VobSub/DVB 位图字幕。
  bool get _activeSubtitleIsBitmap {
    final idx = _activeSubtitleIndex;
    if (idx == null || idx < 0) return false;
    final pos = _embySubtitleStreams.indexWhere((s) => s.index == idx);
    if (pos < 0) return false;
    return PlayerScreen.isBitmapSubtitleCodec(_embySubtitleStreams[pos].codec);
  }

  /// 当前引擎 Erika 且激活字幕为位图（PGS/VobSub/DVB）→ 样式/位置/延迟不可调。
  /// 位图字幕由 Erika 以原生尺寸/位置合成，libass 样式/缩放对其无效。
  bool _erikaActiveSubtitleIsBitmap() =>
      _currentEngine == PlayerEngine.erika && _activeSubtitleIsBitmap;

  // ── Erika 原生弹幕（引擎内 GPU 合成）──────────────────────

  /// 把当前已解析弹幕 + 开关 + 配置喂给 Erika 原生弹幕（仅 Erika 档生效）。
  void _applyErikaDanmaku() {
    if (_currentEngine != PlayerEngine.erika) return;
    final p = _player;
    if (p is! ErikaDanmakuPlayer) return;
    final danmaku = p as ErikaDanmakuPlayer;
    unawaited(danmaku.setDanmakuEnabled(_danmakuOn));
    unawaited(danmaku.loadDanmakuJsonString(_danmakuJson()));
    unawaited(_applyErikaDanmakuConfig());
  }

  /// 弹幕列表 → Erika JSON：`[{time, content, type, color}]`。
  String _danmakuJson() => PlayerScreen.danmakuJsonFor(_danmakuComments);

  /// 显示调节/弹幕配置 → Erika `setDanmakuConfig`（引擎内部 50ms 合并）。
  Future<void> _applyErikaDanmakuConfig() async {
    if (_currentEngine != PlayerEngine.erika) return;
    final p = _player;
    if (p is! ErikaDanmakuPlayer) return;
    final s = ref.read(settingsProvider);
    await (p as ErikaDanmakuPlayer).setDanmakuConfigHimi(
      fontSize: DanmakuOverlay.baseFontSize * s.danmakuFontSize,
      opacity: s.danmakuOpacity,
      scrollDurationSeconds: s.danmakuSpeed > 0 ? 8.0 / s.danmakuSpeed : 8.0,
      displayArea: 1.0,
      maxLinesPerMode: s.danmakuScrollRows,
      maxQuantity: s.danmakuLimitCount ? s.danmakuMaxCount : null,
      blockTop: s.danmakuBlockTop,
      blockBottom: s.danmakuBlockBottom,
      blockWords: s.danmakuBlockWords
          .split(',')
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList(),
    );
  }

  void _onDanmakuSpeedChanged(double v) {
    ref.read(settingsProvider.notifier).update(danmakuSpeed: v);
    unawaited(_applyErikaDanmakuConfig());
  }

  void _onDanmakuFontSizeChanged(double v) {
    ref.read(settingsProvider.notifier).update(danmakuFontSize: v);
    unawaited(_applyErikaDanmakuConfig());
  }

  void _onDanmakuOpacityChanged(double v) {
    ref.read(settingsProvider.notifier).update(danmakuOpacity: v);
    unawaited(_applyErikaDanmakuConfig());
  }

  /// 底栏弹幕钮：翻转开关（不占选择器面板；关掉其他已开面板）。
  void _toggleDanmaku() {
    _resetHideTimer();
    setState(() {
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
      _danmakuOn = !_danmakuOn;
    });
    if (_danmakuOn) {
      _loadDanmaku();
    } else {
      _cancelDanmakuRetry();
    }
    // Erika 档：开关直接下发引擎原生弹幕
    if (_currentEngine == PlayerEngine.erika) {
      final p = _wrappedAdapter<ErikaPlayerAdapter>();
      if (p != null) unawaited(p.setDanmakuEnabled(_danmakuOn));
    }
  }

  /// 取（或按地址重建）弹幕客户端。
  DandanplayClient _danmakuClientFor(String baseUrl) {
    final key = DandanplayClient.normalizeBaseUrl(baseUrl) ?? '';
    final existing = _danmakuClient;
    if (existing != null && _danmakuClientKey == key) return existing;
    final client = DandanplayClient(baseUrl: key);
    _danmakuClient = client;
    _danmakuClientKey = key;
    return client;
  }

  /// 匹配用文件名：剧集 `剧名.SxxExx` / 电影单集名。
  String? _danmakuMatchFileName() {
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= _episodes.length) {
      return null;
    }
    final ep = _episodes[_currentEpisodeIndex];
    return DanmakuMatcher.resolve(
      name: ep.name,
      seriesName: ep.seriesName,
      season: ep.season,
      number: ep.number,
    );
  }

  /// 搜索兜底关键词：剧集优先用剧名，电影用片名；清洗发布标签后
  /// 供 `search/episodes` 使用。无可用名返回 null。
  String? _danmakuSearchKeyword() {
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= _episodes.length) {
      return null;
    }
    final ep = _episodes[_currentEpisodeIndex];
    final raw = ep.seriesName.trim().isNotEmpty ? ep.seriesName : ep.name;
    final cleaned = DanmakuMatcher.cleanTitle(raw);
    return cleaned.isEmpty ? null : cleaned;
  }

  /// 当前集号（无 = 0），供候选排序。
  int get _currentEpisodeNumber =>
      _currentEpisodeIndex >= 0 && _currentEpisodeIndex < _episodes.length
          ? _episodes[_currentEpisodeIndex].number
          : 0;

  /// 有序候选 episodeId（错源排除 + 集号优先，详见 [DanmakuCandidateSelector]）。
  List<int> _orderedDanmakuCandidates(
    List<MatchCandidate> matched,
    List<MatchCandidate> searched,
  ) =>
      DanmakuCandidateSelector.ordered(
        matched,
        searched,
        episodeNumber: _currentEpisodeNumber,
        year: widget.year,
        kind: widget.kind,
        isAnimation: widget.isAnimation,
      );

  /// 依次尝试候选 episodeId，返回首个「非空弹幕」结果；全部失败/为空 → null。
  /// 单个候选 500/网络/空结果静默跳过（记日志），成功结果入缓存。
  Future<({int id, List<DanmakuComment> comments})?> _tryDanmakuCandidates(
    DandanplayClient client,
    List<int> ids,
    int seq,
  ) async {
    for (final id in ids) {
      try {
        final key = id.toString();
        final cached = DanmakuCaches.comments.get(key);
        final comments = cached ?? await client.fetchComments(id);
        if (!mounted || seq != _danmakuLoadSeq) return null;
        if (comments.isNotEmpty) {
          if (cached == null) DanmakuCaches.comments.put(key, comments);
          return (id: id, comments: comments);
        }
      } catch (e) {
        LogService().log('Danmaku', 'candidate $id failed: $e');
      }
      if (!mounted || seq != _danmakuLoadSeq) return null;
    }
    return null;
  }

  /// 匹配 → 拉弹幕 → 渲染（失败回弹开关并轻提示）。
  /// episodeId 与弹幕列表均有进程内缓存（6h TTL，key 为单集 id，
  /// 换集不串缓存）。
  Future<void> _loadDanmaku({bool force = false}) async {
    if (_danmakuLoading) return;
    // 当前集弹幕已就绪：起播/恢复/重复触发不再重载（避免闪烁）。
    // force=true 用于静默重试，跳过该守卫。
    if (!force &&
        _danmakuComments.isNotEmpty &&
        _danmakuLoadedIndex == _currentEpisodeIndex) {
      return;
    }
    final client = _danmakuClientFor(
      ref.read(settingsProvider).danmakuApiUrl,
    );
    if (!client.isConfigured) {
      if (mounted) {
        setState(() => _danmakuOn = false);
        _danmakuSnack('请先在 设置 → 弹幕配置 填写弹幕 API 地址');
      }
      return;
    }
    // 影片信息 / 集索引尚未就绪（初始化过早等）：静默跳过，
    // 待集就绪后的触发点再拉取，不弹提示、不关开关。
    final fileName = _danmakuMatchFileName();
    if (fileName == null) {
      LogService().log('Danmaku', 'skip: episode not ready');
      return;
    }
    final seq = ++_danmakuLoadSeq;
    setState(() {
      _danmakuLoading = true;
      // 重试时保留上一次弹幕（失败保留，观感不闪断）；换集正常加载才清空
      if (!force) _danmakuComments = const [];
    });
    try {
      // 单集 id 作缓存 key：换集后同 itemId 也可能指向不同节目
      final cacheKey =
          _currentEpisodeIndex >= 0 && _currentEpisodeIndex < _episodes.length
              ? _episodes[_currentEpisodeIndex].id
              : widget.itemId;
      ({int id, List<DanmakuComment> comments})? found;

      // 1) 复用上次成功的 episodeId（坏源已不复用：失败会继续找其它候选）
      final cachedId = DanmakuCaches.episode.get(cacheKey);
      if (cachedId != null) {
        found = await _tryDanmakuCandidates(client, [cachedId], seq);
        if (!mounted || seq != _danmakuLoadSeq) return;
      }

      // 2) 并行 match + 搜索，合并后按「全局集号命中优先 + 错源排除」逐候选试。
      //    并行可省一次串行往返；match 瞬时失败不致命。
      if (found == null) {
        List<MatchCandidate> matched = const [];
        List<MatchCandidate> searched = const [];
        final keyword = _danmakuSearchKeyword();
        await Future.wait<void>([
          () async {
            try {
              matched = await client.match(fileName: fileName);
            } on DanmakuApiException catch (e) {
              LogService()
                  .log('Danmaku', 'match failed: ${e.kind.name} ${e.message}');
            }
          }(),
          () async {
            if (keyword == null) return;
            try {
              searched = await client.searchEpisodes(keyword);
            } catch (e) {
              LogService().log('Danmaku', 'search failed: $e');
            }
          }(),
        ]);
        if (!mounted || seq != _danmakuLoadSeq) return;

        found = await _tryDanmakuCandidates(
          client,
          _orderedDanmakuCandidates(matched, searched),
          seq,
        );
        if (!mounted || seq != _danmakuLoadSeq) return;
      }

      if (found == null) {
        throw const DanmakuApiException(
          DanmakuApiError.business,
          '未匹配到弹幕',
        );
      }

      DanmakuCaches.episode.put(cacheKey, found.id);
      _cancelDanmakuRetry();
      setState(() {
        _danmakuComments = found!.comments;
        _danmakuLoadedIndex = _currentEpisodeIndex;
        _danmakuLoading = false;
      });
      // Erika 档：改由引擎原生 GPU 弹幕合成，喂已解析列表。
      _applyErikaDanmaku();
      LogService().log('Danmaku',
          'loaded ${found.comments.length} (ep=${found.id}, $fileName)');
    } on DanmakuApiException catch (e) {
      if (!mounted || seq != _danmakuLoadSeq) return;
      LogService().log('Danmaku',
          'load failed: ${e.kind.name} ${e.message}${e.statusCode == null ? '' : ' (${e.statusCode})'}');
      _handleDanmakuFailure(_danmakuErrorText(e));
    } catch (e) {
      if (!mounted || seq != _danmakuLoadSeq) return;
      LogService().log('Danmaku', 'load failed: $e');
      _handleDanmakuFailure('弹幕加载失败');
    }
  }

  /// 失败统一处理：保留当前集已有弹幕（不闪断），按退避序列静默重试；
  /// 仅当当前集无任何弹幕且重试耗尽时才提示一次。
  void _handleDanmakuFailure(String message) {
    final hadComments = _danmakuComments.isNotEmpty &&
        _danmakuLoadedIndex == _currentEpisodeIndex;
    setState(() {
      _danmakuLoading = false;
      // 有旧弹幕则保留展示；无则保持空
      if (!hadComments) _danmakuComments = const [];
    });
    final canRetry = _danmakuRetryAttempt < _danmakuRetryDelaysSec.length;
    if (canRetry) {
      _scheduleDanmakuRetry();
    } else if (!hadComments) {
      _danmakuSnack(message);
    }
  }

  /// 按 [_danmakuRetryDelaysSec] 序列调度一次静默重试（force 重载）。
  void _scheduleDanmakuRetry() {
    if (_danmakuRetryAttempt >= _danmakuRetryDelaysSec.length) return;
    final delay = _danmakuRetryDelaysSec[_danmakuRetryAttempt];
    _danmakuRetryAttempt++;
    _danmakuRetryTimer?.cancel();
    _danmakuRetryTimer = Timer(Duration(seconds: delay), () {
      if (!mounted || !_danmakuOn) return;
      _loadDanmaku(force: true);
    });
  }

  /// 取消静默重试并复位计数（成功 / 换集 / 关弹幕 / 销毁）。
  void _cancelDanmakuRetry() {
    _danmakuRetryTimer?.cancel();
    _danmakuRetryTimer = null;
    _danmakuRetryAttempt = 0;
  }

  String _danmakuErrorText(DanmakuApiException e) {
    switch (e.kind) {
      case DanmakuApiError.notConfigured:
        return '请先在 设置 → 弹幕配置 填写弹幕 API 地址';
      case DanmakuApiError.network:
        return '弹幕服务连接失败';
      case DanmakuApiError.business:
        return e.message;
      case DanmakuApiError.http:
        final status = e.statusCode;
        if (status != null && status >= 500) {
          return '弹幕服务暂时不可用，请稍后重试';
        }
        return '弹幕加载失败：${e.message}';
      case DanmakuApiError.invalidResponse:
        return '弹幕加载失败：${e.message}';
    }
  }

  void _danmakuSnack(String message) {
    if (!mounted) return;
    showAppToast(context, message, duration: const Duration(seconds: 3));
  }

  void _onLockStateChanged() {
    if (mounted) setState(() {});
  }

  /// 应用倍速：立即生效 + 关闭面板 + 持久化入设置（换集/重启保持）。
  void _applySpeed(double speed) {
    setState(() {
      _speed = speed;
      _showSpeedMenu = false;
    });
    _player.playbackRate = speed;
    ref.read(settingsProvider.notifier).update(playbackSpeed: speed);
  }

  /// 手机版长按视频区：临时切 [speedBoostMultiplier]（不改设置）。
  void _onSpeedBoostStart() {
    if (_speedBoostActive || !_canControlPlayback) return;
    _speedBoostActive = true;
    _player.playbackRate = PlayerScreen.speedBoostMultiplier;
    setState(() {});
  }

  /// 松手/取消：恢复长按前的倍速 [_speed]。
  void _onSpeedBoostEnd() {
    if (!_speedBoostActive) return;
    _speedBoostActive = false;
    _player.playbackRate = _speed;
    setState(() {});
  }

  /// 启动真实下载速度计：平台不支持（counter 为 null）或连续读取失败时
  /// 保持 `_networkSpeedBps = null`，顶栏不渲染网速。
  /// 首个有效值/首次不可用各记一条日志，便于诊断设备兼容问题。
  void _startSpeedMeter() {
    final counter = createDefaultRxCounter();
    if (counter == null) {
      LogService().log('Speed', '数据源不支持，网速显示关闭');
      return;
    }
    var loggedFirst = false;
    var loggedNull = false;
    _speedMeter = NetworkSpeedMeter(
      counter: counter,
      onSpeed: (bps) {
        if (bps != null && !loggedFirst) {
          loggedFirst = true;
          LogService()
              .log('Speed', '首个网速采样: ${NetworkSpeedMeter.formatMBs(bps)}');
        } else if (bps == null && !loggedNull) {
          loggedNull = true;
          LogService().log('Speed', '连续读取失败，网速显示停止');
        }
        if (!mounted) return;
        setState(() => _networkSpeedBps = bps);
      },
    )..start();
  }

  /// 左缘锁按钮：上锁（收起控制栏/菜单，屏蔽手势与热键）。
  void _lockScreen() {
    _lockController.lock();
    _autoHide.cancel();
    _releaseFocusFromControls();
    setState(() {
      _showControls = false;
      _showSubtitleMenu = false;
      _showKernelMenu = false;
      _showAudioMenu = false;
      _showDecodeModeMenu = false;
      _showSpeedMenu = false;
      _showSubtitleStyleMenu = false;
      _showEpisodeMenu = false;
      _showVersionMenu = false;
      _showSegmentMarkPanel = false;
      _skipPromptSegment = null;
    });
    _skipPromptTimer?.cancel();
  }

  /// 解锁并恢复控制栏。
  void _unlockScreen() {
    _lockController.unlock();
    setState(() => _showControls = true);
    _resetHideTimer();
  }

  void _toggleScreenLock() {
    if (_lockController.locked) {
      _unlockScreen();
    } else {
      _lockScreen();
    }
  }

  /// 视频区单击：锁定中仅浮现左缘解锁钮（顶栏/控制条被 locked 门禁），
  /// 否则收菜单/切换控制栏。
  void _onVideoAreaTap() {
    if (_lockController.locked) {
      setState(() => _showControls = true);
      _logControlsVisibility('锁定态点屏');
      _resetHideTimer();
      return;
    }
    if (_showSubtitleMenu ||
        _showAudioMenu ||
        _showKernelMenu ||
        _showDecodeModeMenu ||
        _showSpeedMenu ||
        _showSubtitleStyleMenu ||
        _showEpisodeMenu ||
        _showVersionMenu ||
        _showSegmentMarkPanel ||
        _showBrightnessBarNotifier.value ||
        _showVolumeBarNotifier.value) {
      _closeAllMenus();
    } else {
      _toggleControls();
    }
  }

  Future<void> _switchDecodeMode(String mode) async {
    if (_isSwitchingDecode) return;
    _isSwitchingDecode = true;

    try {
      final wasPlaying = _player.state == AdapterPlaybackState.playing;

      // 获取当前位置
      final currentPos = _player.position;

      if (_currentEngine == PlayerEngine.mpv) {
        _player.videoDecoders = DecodeModeService.resolveDecoders(mode);
        await ref.read(settingsProvider.notifier).update(decodeMode: mode);
        setState(() => _showDecodeModeMenu = false);
        await _reloadSameLine();
        return;
      }

      // Step1: 暂停（防止切换期间解码器输出帧导致撕裂）
      if (wasPlaying) {
        _player.state = AdapterPlaybackState.paused;
        _syncPlayState();
      }

      // Step2: 切换解码器
      final decoders = DecodeModeService.resolveDecoders(mode);
      _player.videoDecoders = decoders;
      final audioDecoders = DecodeModeService.resolveAudioDecoders(mode);
      _player.audioDecoders = audioDecoders;
      LogService().log(
          'Player', '切换解码配置: $mode → video=$decoders audio=$audioDecoders');

      // Step3: seek 触发帧刷新（强制新解码器解码当前帧）
      if (currentPos > 0) {
        try {
          await _player.seek(positionMs: currentPos);
        } catch (_) {}
      }

      // Step4: 恢复播放
      if (wasPlaying) {
        _player.state = AdapterPlaybackState.playing;
        _syncPlayState();
      }

      // Step5: 持久化设置
      await ref.read(settingsProvider.notifier).update(decodeMode: mode);
      setState(() => _showDecodeModeMenu = false);
    } finally {
      _isSwitchingDecode = false;
    }
  }

  // ========== 手势控制 ==========
  double _horizontalDragAccumulator = 0;

  void _onDoubleTap() {
    if (!_canControlPlayback) return;
    _togglePlayPause();
    // 指示器显示切换后的「当前可执行动作」，与底部控制栏按钮语义一致
    _showGestureIcon(
        playPauseHintIcon(_player.state == AdapterPlaybackState.playing));
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_canControlPlayback) return;
    _horizontalDragAccumulator += details.primaryDelta ?? 0;
    // 每累计 100 像素显示一次预览
    if (_horizontalDragAccumulator.abs() > 100) {
      final deltaMs = (_horizontalDragAccumulator / 100 * 5000)
          .round()
          .clamp(-60000, 60000);
      final currentMs = _position.inMilliseconds;
      final previewMs =
          (currentMs + deltaMs).clamp(0, _duration.inMilliseconds);
      final previewDuration = Duration(milliseconds: previewMs);
      final minutes = previewDuration.inMinutes;
      final seconds =
          (previewDuration.inSeconds % 60).toString().padLeft(2, '0');
      _showGestureHint('$minutes:$seconds');
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_canControlPlayback) return;
    // 使用与预览相同的累加器计算，确保预览与实际 seek 位置一致
    final deltaMs =
        (_horizontalDragAccumulator / 100 * 5000).round().clamp(-60000, 60000);
    _horizontalDragAccumulator = 0;
    if (deltaMs != 0) {
      _seekRelative(deltaMs);
    } else {
      // 没有足够拖动距离时使用速度回退
      final delta = details.primaryVelocity ?? 0;
      final seekDelta = (delta / 100 * 5000).round();
      if (seekDelta != 0) _seekRelative(seekDelta);
    }
  }

  void _seekRelative(int deltaMs) {
    if (_lockController.locked) return;
    _resetHideTimer();
    // 限制最大跳转 ±60 秒
    final clampedDelta = deltaMs.clamp(-60000, 60000);
    final currentMs = _position.inMilliseconds;
    final targetMs =
        (currentMs + clampedDelta).clamp(0, _duration.inMilliseconds);

    // 立即更新 UI
    _position = Duration(milliseconds: targetMs);
    _positionNotifier.value = _position;

    unawaited(_seekGuarded(targetMs));

    final seconds = (clampedDelta / 1000).round();
    _showGestureHint(seconds > 0 ? '+${seconds}s' : '${seconds}s');

    if (widget.roomCode != null) {
      _sendCommand(AppConstants.actionSeek, position: targetMs / 1000);
    }
  }

  void _showGestureIcon(IconData icon) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureOverlayIcon = icon;
      _showGestureOverlay = true;
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
  }

  void _showGestureHint(String text) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureHintText = text;
      _gestureOverlayIcon = null;
      _showGestureOverlay = true;
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showGestureOverlay = false);
    });
  }

  /// 长按临时倍速指示（画面中央玻璃小胶囊）。
  Widget _buildSpeedBoostChip() {
    return GlassContainer(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fast_forward, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            '${PlayerScreen.speedBoostMultiplier.toStringAsFixed(1)}× 播放中',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestureHint() {
    if (_gestureOverlayIcon != null) {
      return Center(
        child: Icon(_gestureOverlayIcon!, color: Colors.white70, size: 48),
      );
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _gestureHintText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ========== 垂直手势：亮度/音量 ==========
  void _onVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isLeftSide = details.globalPosition.dx < screenWidth / 2;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (_isLeftSide) {
      // 左侧：调节亮度
      _brightness = (_brightness - delta / 600).clamp(0.0, 1.0);
      _setBrightness(_brightness);
      _brightnessNotifier.value = _brightness;
      _showBrightnessBarNotifier.value = true;
      _showVolumeBarNotifier.value = false;
    } else {
      // 右侧：调节音量
      final newVol = (_volume - delta / 600 * 100).clamp(0.0, 100.0);
      _volume = newVol;
      _player.volume = newVol / 100.0; // fvp 使用 0.0-1.0 范围
      _volumeNotifier.value = _volume;
      _showVolumeBarNotifier.value = true;
      _showBrightnessBarNotifier.value = false;
    }
    _startGestureBarTimer();
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _startGestureBarTimer();
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {}
  }

  void _startGestureBarTimer() {
    _gestureBarTimer?.cancel();
    _gestureBarTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _showBrightnessBarNotifier.value = false;
        _showVolumeBarNotifier.value = false;
      }
    });
  }

  Widget _buildBrightnessBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      right: 20,
      child: ValueListenableBuilder<double>(
        valueListenable: _brightnessNotifier,
        builder: (context, brightness, _) {
          return _buildVerticalBar(
            value: brightness,
            icon: Icons.brightness_6,
            color: const Color(0xFFFFD54F),
          );
        },
      ),
    );
  }

  Widget _buildVolumeBar() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.15,
      bottom: MediaQuery.of(context).size.height * 0.15,
      left: 20,
      child: ValueListenableBuilder<double>(
        valueListenable: _volumeNotifier,
        builder: (context, volume, _) {
          return _buildVerticalBar(
            value: volume / 100,
            icon: volume == 0
                ? Icons.volume_off
                : volume < 50
                    ? Icons.volume_down
                    : Icons.volume_up,
            color: const Color(0xFF6366F1),
          );
        },
      ),
    );
  }

  Widget _buildVerticalBar({
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 36,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 8),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: glassSliderTheme(
                  accent: color,
                  trackHeight: 4,
                  thumbRadius: 6,
                  overlayRadius: 10,
                  glassEnabled: _glassUiOn,
                ),
                child: Slider(
                  value: value,
                  onChanged: null,
                ),
              ),
            ),
          ),
          Text(
            '${(value * 100).round()}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 手机锁定态底栏：只留锁钮（与进度条左数显同列），供解锁。
  Widget _buildLockOnlyControls() {
    return Focus(
      focusNode: _controlsRootFocusNode,
      skipTraversal: true,
      onKeyEvent: _autoHide.onKeyEvent,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: SeekTimeLabels.cellWidth(_durationNotifier.value),
              child: Align(
                alignment: Alignment.center,
                child: PlayerLockButton(
                  locked: _lockController.locked,
                  onToggle: _toggleScreenLock,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final mobilePlatform = PlayerPlatform.isMobile;
    final phoneControls = PlayerScreen.isMobilePhoneControls(
      tvMode: tvMode,
      mobilePlatform: mobilePlatform,
    );
    final showPhoneLock =
        phoneControls && PlayerScreen.showLockButton(tvMode: tvMode);
    final segmentTvMark = _segmentFeatureEnabled && tvMode;
    // 手机锁定态：底栏只保留锁钮（与进度条左数显同列），供解锁。
    if (showPhoneLock && _lockController.locked) {
      return _buildLockOnlyControls();
    }
    // 控制条根焦点：仅作"焦点是否停留在控制条内"的判定锚点
    // （自动隐藏顺延），skipTraversal 不参与方向遍历
    return Focus(
      focusNode: _controlsRootFocusNode,
      skipTraversal: true,
      onKeyEvent: _autoHide.onKeyEvent,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题艺术字（Logo 图）：进度条上方左对齐，随控制条显隐；
              // 房间模式不显示，404/加载失败静默隐藏
              if (PlayerScreen.showLogoInControls(
                logoUrl: widget.logoUrl,
                isRoom: widget.roomCode != null,
              )) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 240,
                    height: 44,
                    child: EmbyImage(
                      url: widget.logoUrl,
                      fit: BoxFit.contain,
                      placeholder: const SizedBox.shrink(),
                      errorWidget: const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              // 焦点承载在滑杆外层：TV 描边环显示在进度条上，且 Slider 自带
              // Shortcuts（_AdjustSliderIntent）脱离焦点冒泡链——左右键改由
              // PlayerHotkey 接管（单击 ±5 秒 / 长按每步 ±10 秒）；
              // ExcludeFocus 屏蔽 Slider 内部焦点节点（防同 rect 双候选，
              // 触摸拖动不受影响）。数显拆分至进度条左右两侧（同水平中线），
              // 焦点环仍只框滑杆本体
              ValueListenableBuilder2<Duration, Duration>(
                first: _positionNotifier,
                second: _durationNotifier,
                builder: (context, pos, dur, _) {
                  return SeekTimeLabels(
                    position: pos,
                    duration: dur,
                    child: TvFocusable(
                      focusNode: _controlsFocusNode,
                      // 进度条不承担播放/暂停：短按 OK 不触发任何动作，
                      // 长按 OK 打开片头/片尾标记面板；播放/暂停只走
                      // 底部播放按钮，避免长按标记时误切播放状态。
                      onTap: null,
                      onLongPress: segmentTvMark ? _openSegmentMarkPanel : null,
                      scale: 1.0,
                      child: ExcludeFocus(
                        child: SliderTheme(
                          data: glassSliderTheme(glassEnabled: _glassUiOn),
                          child: Slider(
                            value: dur.inMilliseconds > 0
                                ? pos.inMilliseconds
                                    .toDouble()
                                    .clamp(0, dur.inMilliseconds.toDouble())
                                : 0,
                            max: dur.inMilliseconds > 0
                                ? dur.inMilliseconds.toDouble()
                                : 1,
                            onChangeStart:
                                _canControlPlayback ? _onSeekStart : null,
                            onChanged: (v) {
                              _resetHideTimer();
                              _positionNotifier.value =
                                  Duration(milliseconds: v.toInt());
                            },
                            onChangeEnd:
                                _canControlPlayback ? _onSeekEnd : null,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // 字幕/音轨/倍速选择器已移至右侧玻璃浮层（SelectorSidePanel）
              // 手机版：传输组居中、右组贴右；TV/桌面：传输组置左、右组贴右。
              PlayerBottomRow(
                centered: phoneControls,
                transport: [
                  // 传输控制组：上一集 / 播放暂停 / 下一集。无剧集导航（电影/
                  // 单集）时仍保留上一集/下一集占位宽度，保证播放/暂停按钮
                  // 位置与剧集播放时完全一致（不漂移）。
                  if (_canControlPlayback) ...[
                    if (_hasEpisodeList && _totalEpisodeCount > 1)
                      TvFocusable(
                        onTap: _currentEpisodeIndex > 0
                            ? () => _switchToEpisode(_currentEpisodeIndex - 1)
                            : null,
                        child: Icon(
                          Icons.skip_previous,
                          color: _currentEpisodeIndex > 0
                              ? Colors.white
                              : Colors.white24,
                          size: 28,
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                    const SizedBox(width: 8),

                    // 播放/暂停（位置固定，焦点落点统一由 _showControlsForTv
                    // 决定，不再 autofocus；滑杆按落键由 PlayerHotkey 定向落到此节点）
                    TvFocusable(
                      focusNode: _playPauseFocusNode,
                      onTap: _togglePlayPause,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isPlayingNotifier,
                        builder: (context, isPlaying, child) => Icon(
                          isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (_hasEpisodeList && _totalEpisodeCount > 1)
                      TvFocusable(
                        focusNode: _nextEpisodeFocusNode,
                        onTap: _currentEpisodeIndex < _totalEpisodeCount - 1
                            ? () => _switchToEpisode(_currentEpisodeIndex + 1)
                            : null,
                        child: Icon(
                          Icons.skip_next,
                          color: _currentEpisodeIndex < _totalEpisodeCount - 1
                              ? Colors.white
                              : Colors.white24,
                          size: 28,
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                    const SizedBox(width: 8),
                  ],
                ],

                // 左槽：手机版锁钮（与进度条左数显同列）；Windows 音量/亮度滑杆
                leading: [
                  if (showPhoneLock)
                    SizedBox(
                      width: SeekTimeLabels.cellWidth(_durationNotifier.value),
                      child: Align(
                        alignment: Alignment.center,
                        child: PlayerLockButton(
                          locked: _lockController.locked,
                          onToggle: _toggleScreenLock,
                        ),
                      ),
                    ),
                  if (_skipPromptSegment != null && _segmentFeatureEnabled) ...[
                    if (showPhoneLock) const SizedBox(width: 8),
                    _buildSkipPromptButton(),
                    const SizedBox(width: 12),
                  ],
                  if (PlayerPlatform.volumeBrightnessSliders) ...[
                    const SizedBox(width: 16),
                    _buildVolumeSlider(),
                    const SizedBox(width: 16),
                    _buildBrightnessSlider(),
                  ],
                ],

                trailing: [
                  // 弹幕开关（右组头；房间联播也显示——弹幕本地渲染）
                  _buildControlButton(
                    icon: _danmakuOn ? Icons.comment : Icons.comments_disabled,
                    focusNode: _danmakuButtonFocusNode,
                    onTap: _toggleDanmaku,
                  ),
                  const SizedBox(width: 20),

                  // 多版本切换（弹幕之后；仅非房间模式且有多版本时显示）
                  if (widget.roomCode == null &&
                      _currentMediaSources.length > 1) ...[
                    _buildControlButton(
                      icon: Icons.high_quality,
                      focusNode: _versionButtonFocusNode,
                      onTap: _toggleVersionMenu,
                      badge: '${_currentMediaSources.length}',
                    ),
                    const SizedBox(width: 20),
                  ],

                  // 显示调节（TV：从顶栏移入底栏，位于弹幕与字幕之间）
                  if (PlayerScreen.showBottomDisplayAdjustButton(
                      tvMode: tvMode)) ...[
                    _buildControlButton(
                      icon: Icons.tune,
                      focusNode: _subtitleStyleButtonFocusNode,
                      onTap: _toggleSubtitleStyleMenu,
                    ),
                    const SizedBox(width: 20),
                  ],

                  // 字幕
                  _buildControlButton(
                    icon: Icons.subtitles,
                    focusNode: _subtitleButtonFocusNode,
                    onTap: () {
                      setState(() {
                        _showSubtitleMenu = !_showSubtitleMenu;
                        _showAudioMenu = false;
                        _showSpeedMenu = false;
                        _showSubtitleStyleMenu = false;
                        _showEpisodeMenu = false;
                        _showVersionMenu = false;
                      });
                      if (_showSubtitleMenu) {
                        _openSelectorPanel(_subtitleButtonFocusNode);
                      }
                    },
                    badge: _embySubtitleStreams.isNotEmpty
                        ? '${_embySubtitleStreams.length}'
                        : null,
                  ),
                  const SizedBox(width: 20),

                  // 音轨
                  _buildControlButton(
                    icon: Icons.audiotrack,
                    focusNode: _audioButtonFocusNode,
                    onTap: () {
                      setState(() {
                        _showAudioMenu = !_showAudioMenu;
                        _showSubtitleMenu = false;
                        _showKernelMenu = false;
                        _showSpeedMenu = false;
                        _showSubtitleStyleMenu = false;
                        _showEpisodeMenu = false;
                        _showVersionMenu = false;
                      });
                      if (_showAudioMenu) {
                        _openSelectorPanel(_audioButtonFocusNode);
                      }
                    },
                    badge: _embyAudioStreams.isNotEmpty
                        ? '${_embyAudioStreams.length}'
                        : null,
                  ),

                  // 选集（音轨右侧；仅单人模式多集时显示，房间模式不加）
                  if (widget.roomCode == null &&
                      _hasEpisodeList &&
                      _totalEpisodeCount > 1) ...[
                    const SizedBox(width: 20),
                    _buildControlButton(
                      icon: Icons.playlist_play,
                      focusNode: _episodeButtonFocusNode,
                      onTap: _toggleEpisodeMenu,
                      badge: '$_totalEpisodeCount',
                    ),
                  ],

                  // 倍速（TV/桌面本地单人；手机版已移至顶栏网速右侧）
                  if (PlayerScreen.showBottomSpeedButton(
                    tvMode: tvMode,
                    mobilePlatform: mobilePlatform,
                    isRoom: widget.roomCode != null,
                  )) ...[
                    const SizedBox(width: 20),
                    TvFocusable(
                      focusNode: _speedButtonFocusNode,
                      onTap: _toggleSpeedMenu,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.speed,
                                color: Colors.white, size: 24),
                            const SizedBox(width: 4),
                            Text(
                              SpeedMenuPanel.formatSpeedLabel(_speed),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 面板切换（仅房间模式）
                  if (widget.roomCode != null) ...[
                    const SizedBox(width: 20),
                    _buildControlButton(
                      icon: _showPanel
                          ? Icons.close_fullscreen
                          : Icons.open_in_full,
                      onTap: () => setState(() => _showPanel = !_showPanel),
                    ),
                  ],

                  // 横竖屏已移至顶栏（画面比例右侧，仅手机）

                  // 窗口全屏（桌面三端）
                  if (PlayerPlatform.windowFullscreenButton) ...[
                    const SizedBox(width: 20),
                    _buildControlButton(
                      icon: _isWindowFullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      onTap: _toggleWindowFullscreen,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 玻璃滑杆主题（设置页"液态玻璃"关闭时回退纯色旧观）
  bool get _glassUiOn => ref.watch(settingsProvider.select((s) => s.glassUi));

  /// 控制条小滑杆主题（与进度条统一玻璃观）；须在 build 期间求值，
  /// 调用方在方法顶部取值，勿放进 ValueListenableBuilder 回调。
  SliderThemeData _miniSliderTheme() => glassSliderTheme(
        thumbRadius: 7,
        overlayRadius: 12,
        glassEnabled: _glassUiOn,
      );

  /// 控制条音量滑杆（0-100，实时写入播放器）
  Widget _buildVolumeSlider() {
    final theme = _miniSliderTheme();
    return TvFocusable(
      onTap: null,
      radius: 6,
      child: ValueListenableBuilder<double>(
        valueListenable: _volumeNotifier,
        builder: (context, volume, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                volume <= 0
                    ? Icons.volume_off
                    : volume < 50
                        ? Icons.volume_down
                        : Icons.volume_up,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 96,
                height: 24,
                child: SliderTheme(
                  data: theme,
                  child: Slider(
                    value: volume.clamp(0.0, 100.0),
                    max: 100,
                    onChanged: (v) {
                      _resetHideTimer();
                      _volume = v;
                      _player.volume = v / 100.0;
                      _volumeNotifier.value = v;
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '${volume.round()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 控制条亮度滑杆（0-1，拖动才写入应用亮度）
  Widget _buildBrightnessSlider() {
    final theme = _miniSliderTheme();
    return TvFocusable(
      onTap: null,
      radius: 6,
      child: ValueListenableBuilder<double>(
        valueListenable: _brightnessNotifier,
        builder: (context, brightness, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.brightness_6,
                  color: Color(0xFFFFD54F), size: 18),
              const SizedBox(width: 4),
              SizedBox(
                width: 96,
                height: 24,
                child: SliderTheme(
                  data: theme,
                  child: Slider(
                    value: brightness.clamp(0.0, 1.0),
                    onChanged: (v) {
                      _resetHideTimer();
                      _brightness = v;
                      _brightnessNotifier.value = v;
                      _setBrightness(v);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${(brightness * 100).round()}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
    FocusNode? focusNode,
  }) {
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      child: Padding(
        // 内边距扩大焦点热区：24px 图标贴边框时描边环几乎不可见
        padding: const EdgeInsets.all(4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            if (badge != null)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========== 资源面板 ==========
  Widget _buildResourcePanel() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          // 面板头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '资源',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_roomData != null &&
                    _isHost &&
                    _player.state != AdapterPlaybackState.playing) ...[
                  TvFocusable(
                    onTap: () async {
                      // 房间模式聚合搜索（竖屏窗口见 pushRoomResourceSearch）：
                      // 选片进 roomMode 详情挑资源，数据经搜索页带回。
                      final resourceData = await pushRoomResourceSearch(
                        context,
                        roomCode: widget.roomCode!,
                      );
                      // 同步播放页横屏状态（方向已在函数内恢复，幂等重申）
                      _switchToLandscape(_OrientationMode.landscapeLeft);
                      if (resourceData != null && mounted) {
                        _addResourceLocally(resourceData);
                        _sendAddResourceRTM(resourceData);
                      }
                    },
                    child: const Icon(Icons.search,
                        color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                if (_roomData != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people,
                            color: Colors.white70, size: 12),
                        const SizedBox(width: 3),
                        Text('$_onlineUserCount',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (_roomData != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _isHost ? const Color(0xFF6366F1) : Colors.red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isHost ? '房主' : (_audienceName ?? '观众'),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),

          // 资源分组列表
          Expanded(
            child: _resourceGroups.isEmpty
                ? const Center(
                    child: Text('暂无资源',
                        style: TextStyle(color: Colors.white24, fontSize: 13)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _resourceGroups.length,
                    itemBuilder: (ctx, i) =>
                        _buildGroupWidget(_resourceGroups[i]),
                  ),
          ),

          // 播报板（底部）
          if (_roomData != null) _buildBroadcastBoardInPanel(),
        ],
      ),
    );
  }

  Widget _buildGroupWidget(_ResourceGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 组标题（电影 / 剧名）
        InkWell(
          onTap: () => setState(() => group.collapsed = !group.collapsed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213E),
            child: Row(
              children: [
                Icon(
                  group.collapsed ? Icons.chevron_right : Icons.expand_more,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  group.isMovie
                      ? '(${group.totalCount})'
                      : '(${group.totalCount}集)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),

        // 展开内容
        if (!group.collapsed)
          if (group.isMovie)
            // 电影组：直接列出
            if (group.seasons.isNotEmpty)
              ...group.seasons.first.episodes.map((item) {
                final flatIndex = _findFlatIndex(item.id);
                return _buildEpisodeListItem(flatIndex, item);
              })
            else
              const SizedBox.shrink()
          else
            // 电视剧组：按季分组
            ...group.seasons.map((season) => _buildSeasonWidget(group, season)),
      ],
    );
  }

  Widget _buildSeasonWidget(_ResourceGroup group, _SeasonGroup season) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 季标题
        InkWell(
          onTap: () => setState(() => season.collapsed = !season.collapsed),
          child: Container(
            padding:
                const EdgeInsets.only(left: 24, right: 12, top: 6, bottom: 6),
            color: const Color(0xFF1A1A2E),
            child: Row(
              children: [
                Icon(
                  season.collapsed ? Icons.chevron_right : Icons.expand_more,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '第${season.seasonNumber}季',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '(${season.episodes.length}集)',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // 展开时显示集列表
        if (!season.collapsed)
          ...season.episodes.map((item) {
            final flatIndex = _findFlatIndex(item.id);
            return _buildEpisodeListItem(flatIndex, item);
          }),
      ],
    );
  }

  int _findFlatIndex(String itemId) {
    return _episodes.indexWhere((e) => e.id == itemId);
  }

  Widget _buildEpisodeListItem(int flatIndex, _ResourceItem item) {
    final isPlaying = flatIndex == _currentEpisodeIndex;
    final isMovie = item.isMovie;

    return InkWell(
      onTap: () {
        if (!_isHost) return;
        if (isPlaying) {
          _togglePlayPause();
        } else {
          _switchToEpisode(flatIndex);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color:
              isPlaying ? const Color(0xFF6366F1).withValues(alpha: 0.3) : null,
          border: Border(
            left: BorderSide(
              color: isPlaying ? const Color(0xFF6366F1) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // 播放/暂停按钮（仅房主）
            if (_isHost)
              TvFocusable(
                onTap: () {
                  if (isPlaying) {
                    _togglePlayPause();
                  } else {
                    _switchToEpisode(flatIndex);
                  }
                },
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isPlayingNotifier,
                  builder: (context, isPlayingNow, child) {
                    return Icon(
                      isPlaying && isPlayingNow
                          ? Icons.pause_circle
                          : Icons.play_circle,
                      color:
                          isPlaying ? const Color(0xFF6366F1) : Colors.white54,
                      size: 22,
                    );
                  },
                ),
              ),
            if (_isHost) const SizedBox(width: 8),

            // 缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 56,
                height: 36,
                child: item.poster.isNotEmpty
                    ? EmbyImage(url: item.poster, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.movie,
                            size: 16, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 8),

            // 集信息
            Expanded(
              child: isMovie
                  ? Text(
                      item.name,
                      style: TextStyle(
                        color: isPlaying ? Colors.white : Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PlayerScreen.episodeCode(item.season, item.number),
                          style: TextStyle(
                            color: isPlaying
                                ? const Color(0xFF6366F1)
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isPlaying ? Colors.white : Colors.white54,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),

            // 删除按钮（仅房主）
            if (_isHost)
              TvFocusable(
                onTap: () => _removeEpisode(flatIndex),
                child: const Icon(Icons.close, color: Colors.white24, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBroadcastBoardInPanel() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _broadcastVersion,
        builder: (context, version, _) {
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text('播报 (${_broadcastMessages.length})',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Expanded(
                child: _broadcastMessages.isEmpty
                    ? const Center(
                        child: Text('暂无消息',
                            style:
                                TextStyle(color: Colors.white24, fontSize: 11)),
                      )
                    : ListView.builder(
                        controller: _broadcastScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _broadcastMessages.length,
                        itemBuilder: (ctx, i) => Text(
                          _broadcastMessages[i],
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 当前播放内容的 (itemId, serverId)：剧集用选中集，否则用入参
  ///（serverId 为 null 时调用方回退 widget.serverId）。
  (String, String?) get _currentSubtitleContent {
    final hasEp = _episodes.isNotEmpty &&
        _currentEpisodeIndex >= 0 &&
        _currentEpisodeIndex < _episodes.length;
    return hasEp
        ? (
            _episodes[_currentEpisodeIndex].id,
            _episodes[_currentEpisodeIndex].serverId
          )
        : (widget.itemId, null);
  }

  /// 解析字幕请求使用的媒体源 id。
  ///
  /// 多版本切换/切集后 [_activeMediaSourceId] 是当前播放源；播放会话值
  /// 与 widget 入参仅作兜底。都缺失时向 Emby 查询首个媒体源。
  Future<String?> _resolveSubtitleMediaSourceId() async {
    final direct =
        _activeMediaSourceId ?? _reportMediaSourceId ?? widget.mediaSourceId;
    if (direct != null && direct.isNotEmpty) return direct;

    final (itemId, serverId) = _currentSubtitleContent;
    try {
      final service =
          ref.read(embyServiceForProvider(serverId ?? widget.serverId));
      final info = await service.getPlaybackInfo(itemId: itemId);
      if (!mounted) return null;
      for (final source in info.sources) {
        if (source.id.isNotEmpty) return source.id;
      }
    } catch (e) {
      LogService().log('Player', '解析字幕媒体源失败: $e');
    }
    return null;
  }

  /// 字幕样式落盘键：当前播放内容 id（剧集 = 选中集）；多服务器时带
  /// serverId 前缀防碰撞。
  String get _subtitleStyleKey {
    final (id, serverId) = _currentSubtitleContent;
    final sid = serverId ?? widget.serverId;
    return sid != null ? '$sid:$id' : id;
  }

  Future<void> _selectEmbySubtitle(int embyIndex) async {
    final stream = _embySubtitleStreams[embyIndex];
    final isExternal =
        stream.isExternal || stream.subtitleLocationType == 'ExternalStream';
    LogService().log(
        'Player',
        '切字幕: engine=${_currentEngine.id} idx=$embyIndex codec=${stream.codec} '
            'external=$isExternal bitmap=${PlayerScreen.isBitmapSubtitleCodec(stream.codec)}');

    if (isExternal) {
      // 外挂字幕：用 fvp setMedia 加载外部文件，不重载流
      final (itemId, serverId) = _currentSubtitleContent;
      final embyService =
          ref.read(embyServiceForProvider(serverId ?? widget.serverId));
      final config =
          ref.read(embyConfigForProvider(serverId ?? widget.serverId));
      final mediaSourceId = await _resolveSubtitleMediaSourceId();
      if (mediaSourceId == null) {
        LogService().log('Player', '加载外挂字幕失败: 无法确定 MediaSourceId');
        if (mounted) showAppToast(context, '无法确定媒体版本，无法加载字幕');
        return;
      }
      final subtitleUrl = embyService.getSubtitleUrl(
        itemId,
        subtitleIndex: stream.index,
        mediaSourceId: mediaSourceId,
      );
      final token = config?.accessToken ?? '';
      if (token.isNotEmpty) {
        _player.setHttpHeaders({'X-Emby-Token': token});
      }
      try {
        await _player.setMedia(subtitleUrl, type: AdapterMediaType.subtitle);
      } catch (e) {
        LogService().log('Player', '加载外挂字幕失败: $e');
      }
      _player.activeSubtitleTracks = [embyIndex];
    } else {
      // 内嵌字幕：用 fvp 原生轨道切换，瞬间完成
      _player.activeSubtitleTracks = [embyIndex];
    }

    _useServerSubtitleBurnIn = false;
    _activeSubtitleIndex = stream.index;
    _activeLocalSubtitlePath = null;
    _applySubtitleStyle();
    // 延迟 ≠0：立即用偏移后的 SRT 替换刚激活的轨
    _maybeApplySubtitleDelay();
  }

  void _selectEmbyAudio(int embyIndex) {
    // fvp: 通过 activeAudioTracks 选择音轨
    _player.activeAudioTracks = [embyIndex];
    // iOS TrueHD 无声规避：按新音轨编码刷新 audio.avfilter
    _applyAudioFilterPolicy(
      codec: embyIndex >= 0 && embyIndex < _embyAudioStreams.length
          ? _embyAudioStreams[embyIndex].codec
          : null,
    );
  }

  // ========== 字幕样式（大小/位置/延迟） ==========

  /// 应用字幕大小/位置（mdk 属性，暂停也立即生效）。
  ///
  /// 引擎热切换/内容路由重建期间（[_switchingEngine]）跳过：此刻 [_player]
  /// 可能仍指向已释放的旧引擎，写入会命中悬垂原生对象（Windows 闪退根因）。
  /// 重建完成后 [._recreateEngineForLoad] 会再次调用本方法补写。
  void _applySubtitleStyle() {
    if (!PlayerScreen.canWriteSubtitleStyle(
      mounted: mounted,
      switchingEngine: _switchingEngine,
    )) {
      return;
    }
    if (_currentEngine == PlayerEngine.mpv) {
      _player.setProperty('sub-scale', _subtitleScale.toStringAsFixed(2));
      final pos = (100 - _subtitleMarginY / 4).clamp(0, 150).round();
      _player.setProperty('sub-pos', '$pos');
      return;
    }
    final forceBitmapBottom =
        _currentEngine == PlayerEngine.mdk && _activeSubtitleIsBitmap;
    for (final write in PlayerScreen.subtitleStyleWrites(
      forceBitmapBottom: forceBitmapBottom,
      scale: _subtitleScale,
      marginY: _subtitleMarginY,
    )) {
      _player.setProperty(write.name, write.value);
    }
  }

  /// 滑杆拖动期间的去抖写入（100ms）；最终值由 [_applySubtitleStyle] 落定。
  void _scheduleSubtitleStyleApply() {
    _subtitleStyleApplyTimer?.cancel();
    _subtitleStyleApplyTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      _applySubtitleStyle();
    });
  }

  /// 按内容 id 恢复落盘样式（无记录沿用当前内存值）并套用到当前轨。
  Future<void> _restoreSubtitleStyleForContent() async {
    final prefs = await _subtitleStyleStore.get(_subtitleStyleKey);
    if (!mounted) return;
    if (prefs != null) {
      setState(() {
        _subtitleScale = prefs.scale;
        _subtitleMarginY = prefs.marginY;
        _subtitleDelayMs = prefs.delayMs;
      });
    }
    _applySubtitleStyle();
    _maybeApplySubtitleDelay(immediate: true);
  }

  void _onSubtitleScaleChanged(double v) {
    setState(() => _subtitleScale = v);
    _scheduleSubtitleStyleApply();
    _resetHideTimer();
    _scheduleSubtitleStyleSave();
  }

  void _onSubtitleMarginYChanged(int v) {
    setState(() => _subtitleMarginY = v);
    _scheduleSubtitleStyleApply();
    _resetHideTimer();
    _scheduleSubtitleStyleSave();
  }

  void _onSubtitleDelayChanged(int v) {
    setState(() => _subtitleDelayMs = v);
    _resetHideTimer();
    _scheduleSubtitleStyleSave();
    _subtitleDelayReloadTimer?.cancel();
    if (v == 0) {
      // 归零：立即恢复原素材轨
      _restoreActiveSubtitleSource();
    } else {
      _maybeApplySubtitleDelay();
    }
  }

  void _onSubtitleStyleReset() {
    final hadDelay = _subtitleDelayMs != SubtitleStylePanel.defaultDelayMs;
    setState(() {
      _subtitleScale = SubtitleStylePanel.defaultScale;
      _subtitleMarginY = SubtitleStylePanel.defaultMarginY;
      _subtitleDelayMs = SubtitleStylePanel.defaultDelayMs;
    });
    _applySubtitleStyle();
    _resetHideTimer();
    _scheduleSubtitleStyleSave();
    _subtitleDelayReloadTimer?.cancel();
    if (hadDelay) _restoreActiveSubtitleSource();
  }

  /// 样式落盘去抖（500ms）：滑杆连续拖动只写最后一次。
  void _scheduleSubtitleStyleSave() {
    _subtitleStyleSaveTimer?.cancel();
    _subtitleStyleSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      unawaited(_subtitleStyleStore.put(
        _subtitleStyleKey,
        SubtitleStylePrefs(
          scale: _subtitleScale,
          marginY: _subtitleMarginY,
          delayMs: _subtitleDelayMs,
        ),
      ));
    });
  }

  /// 延迟 ≠0 且有激活字幕轨时重载偏移字幕
  ///（轨刚定型时立即，滑杆拖动时 300ms 去抖）。
  void _maybeApplySubtitleDelay({bool immediate = false}) {
    _subtitleDelayReloadTimer?.cancel();
    if (_activeSubtitleIndex == null || _subtitleDelayMs == 0) return;
    if (immediate) {
      unawaited(_reloadSubtitleForDelay());
    } else {
      _subtitleDelayReloadTimer = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_reloadSubtitleForDelay()),
      );
    }
  }

  /// 恢复当前字幕轨原素材（延迟归零/重置时）。
  void _restoreActiveSubtitleSource() {
    final idx = _activeSubtitleIndex;
    if (idx == null) return;
    if (idx == -1) {
      final path = _activeLocalSubtitlePath;
      if (path == null) return;
      unawaited(_loadSubtitleFileIntoPlayer(path));
    } else {
      final pos = _embySubtitleStreams.indexWhere((s) => s.index == idx);
      if (pos >= 0) _selectEmbySubtitle(pos);
    }
  }

  /// 按 [_subtitleDelayMs] 偏移后重载当前字幕轨：
  /// Emby 轨下载 SRT（服务端转出）/ 本地文件直读 → 偏移 → 临时文件 →
  /// setMedia 外挂并激活。
  Future<void> _reloadSubtitleForDelay() async {
    if (!mounted) return;
    final idx = _activeSubtitleIndex;
    if (idx == null || _subtitleDelayMs == 0) return;
    try {
      String? text;
      if (idx == -1) {
        final path = _activeLocalSubtitlePath;
        if (path == null) return;
        text = await File(path).readAsString();
      } else {
        final (itemId, serverId) = _currentSubtitleContent;
        final service =
            ref.read(embyServiceForProvider(serverId ?? widget.serverId));
        final mediaSourceId = await _resolveSubtitleMediaSourceId();
        if (mediaSourceId == null) {
          LogService().log('Player', '字幕延迟重载失败: 无法确定 MediaSourceId');
          return;
        }
        text = await service.fetchSubtitleText(
          itemId,
          subtitleIndex: idx,
          mediaSourceId: mediaSourceId,
        );
      }
      if (text.isEmpty || !mounted) return;
      final dir = await getTemporaryDirectory();
      final path = await SubtitleDelayFile.write(
        text: text,
        delayMs: _subtitleDelayMs,
        dir: dir,
      );
      if (!mounted) return;
      await _loadSubtitleFileIntoPlayer(path);
    } catch (e) {
      LogService().log('Player', '字幕延迟重载失败: $e');
    }
  }

  /// setMedia 外挂字幕文件并激活末轨（新轨追加在末尾）；返回激活位置。
  ///
  /// media_kit 的 `sub-add ... select` 会自动选中新轨，无需手动 count-1；
  /// mdk 的 setMedia 是同步追加，count-1 语义成立。
  Future<int> _loadSubtitleFileIntoPlayer(String path) async {
    await _player.setMedia(path, type: AdapterMediaType.subtitle);
    if (_player is MediaKitPlayerProvider) {
      // sub-add select 已自动激活新轨
      return _player.activeSubtitleTracks.isNotEmpty
          ? _player.activeSubtitleTracks.first
          : -1;
    }
    final count = _player.mediaInfo.subtitleCount;
    if (count > 0) {
      _player.activeSubtitleTracks = [count - 1];
      return count - 1;
    }
    return -1;
  }

  Future<void> _loadLocalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'idx'],
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) return;

      // 加载本地字幕文件
      await _loadSubtitleFileIntoPlayer(filePath);

      setState(() {
        _activeSubtitleIndex = -1;
        _activeLocalSubtitlePath = filePath;
        _useServerSubtitleBurnIn = false;
      });
      _applySubtitleStyle();
      // 延迟 ≠0：用偏移后的副本替换本地原文件
      _maybeApplySubtitleDelay();

      if (mounted) {
        showAppToast(context, '已加载字幕: ${file.name}');
      }
    } catch (e) {
      LogService().log('Player', '加载本地字幕失败: $e');
      if (mounted) {
        showAppToast(context, '加载字幕失败: $e');
      }
    }
  }
}

/// 同时监听两个 ValueNotifier 的 Builder
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;
  final Widget? child;

  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, child) {
            return builder(context, a, b, child);
          },
          child: child,
        );
      },
    );
  }
}

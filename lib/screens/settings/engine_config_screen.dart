import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/settings/device_capability_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';

/// 「播放器配置」：顶部 TabBar 按引擎分页（MDK / media_kit / Erika），
/// 每个 tab 是**该引擎专属设置**。
///
/// 内核选择在播放器顶栏切换；本页按当前平台可用内核展示各自设置。
/// tab 列表 = 当前平台可用内核（Android/Windows: MDK/MediaKit/Erika；
/// iOS: Erika）；MDK / Erika tab 顶部展示设备能力评估卡片。
class EngineConfigScreen extends ConsumerStatefulWidget {
  const EngineConfigScreen({super.key});

  @override
  ConsumerState<EngineConfigScreen> createState() => _EngineConfigScreenState();
}

class _EngineConfigScreenState extends ConsumerState<EngineConfigScreen>
    with SingleTickerProviderStateMixin {
  late final List<PlayerEngine> _engines;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    // 681：单引擎平台（安卓手机/鸿蒙/Windows/iOS）只出一个 tab
    _engines = PlayerEngineFactory.supportedEngines(
      tvMode: ref.read(settingsProvider).tvMode,
    );
    _tab = TabController(length: _engines.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    // 697：板块焦点节点随页面销毁释放（否则反复进出会泄漏 FocusNode）
    for (final node in _boardFocusNodes.values) {
      node.dispose();
    }
    _boardFocusNodes.clear();
    super.dispose();
  }

  /// 697：TV 点引擎板块 → 进该引擎独立子页。
  ///
  /// 返回时焦点回到进入时那个板块（`SettingsCategoryCard` 的 `autofocus`
  /// 只在首次构建生效，故返回后主动请求一次焦点）。
  Future<void> _openEngineDetail(
    BuildContext context,
    PlayerEngine engine,
  ) async {
    await context.push('/settings/player/engine-config/${engine.id}');
    if (!mounted) return;
    // 回到列表后把焦点还给刚才那个板块（用户明确要求）。
    //
    // 【为什么要等一帧】`push` 返回时子页的路由退出动画可能还没结束，
    // 此刻板块的 `Focus` 尚未重新挂上——立即 `requestFocus()` 会被
    // 焦点系统丢弃（真机表现为「返回后焦点回到第一个板块」）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _boardFocusNodes[engine];
      if (node != null && node.context != null) {
        node.requestFocus();
      }
    });
  }

  /// 每个引擎板块的焦点节点（用于返回时恢复焦点）。
  final Map<PlayerEngine, FocusNode> _boardFocusNodes = {};

  FocusNode _boardFocusNode(PlayerEngine engine) => _boardFocusNodes.putIfAbsent(
        engine,
        () => FocusNode(debugLabel: 'engineBoard_${engine.id}'),
      );

  static IconData _engineIcon(PlayerEngine engine) => switch (engine) {
        PlayerEngine.mdk => Icons.memory,
        PlayerEngine.mediaKit => Icons.play_circle_outline,
        PlayerEngine.erika => Icons.auto_awesome,
        PlayerEngine.mpv => Icons.movie_filter_outlined,
      };

  static String _engineBoardSubtitle(PlayerEngine engine) => switch (engine) {
        PlayerEngine.mdk => 'MDK / FVP，兼容性与 HDR 直通',
        PlayerEngine.mediaKit => 'libmpv，格式覆盖广，适合桌面',
        PlayerEngine.erika => 'Erika，Rust 内核，原生位图字幕',
        PlayerEngine.mpv => 'MPV / libmpv，Surface/纹理可配',
      };

  @override
  Widget build(BuildContext context) {
    // 690：TV 多引擎用分段胶囊（遥控器友好），非 TV 保留 TabBar。
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    return SettingsPageBackground(
      child: Scaffold(
        key: const ValueKey('engineConfigPage'),
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('播放器配置'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: const GlassBackdrop(),
          leading: const TvBackButton(),
          // 681：单引擎平台不渲染 TabBar（只有一个 tab 时纯占位）。
          // 690：**TV 多引擎用分段胶囊**（遥控器左右键切换），不用 TabBar。
          bottom: _engines.length <= 1 || tvMode
              ? null
              : TabBar(
                  controller: _tab,
                  isScrollable: _engines.length > 2,
                  tabs: [for (final e in _engines) Tab(text: e.label)],
                ),
        ),
        body: tvMode && _engines.length > 1
            // 697：TV 改为**纵向引擎板块**。
            //
            // 【为什么换掉分段胶囊】690 的 `_EngineSegmentedSelector` 用了
            // `Focus(canRequestFocus: false)`——节点永远拿不到焦点，
            // `onKeyEvent` 里的左右键处理是死代码，遥控器切不到别的引擎
            //（真机反馈「焦点切换不到别的引擎上」）。
            //
            // 现在每引擎一张 `SettingsCategoryCard`（TV 下自带焦点环，
            // 上下键天然可遍历），点击进独立子页；返回时焦点回到本板块。
            ? ListView(
                key: const ValueKey('engineBoardList'),
                padding: EdgeInsets.only(
                  top: GlassConfig.topInsetOf(context) + 8,
                  bottom: GlassConfig.bottomReserveOf(context),
                ),
                children: [
                  for (final e in _engines)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SettingsCategoryCard(
                        key: ValueKey('engineBoard_${e.id}'),
                        icon: _engineIcon(e),
                        title: e.label,
                        subtitle: _engineBoardSubtitle(e),
                        tvMode: tvMode,
                        autofocus: e == _engines.first,
                        focusNode: _boardFocusNode(e),
                        onTap: () => _openEngineDetail(context, e),
                      ),
                    ),
                ],
              )
            : TabBarView(
                controller: _tab,
                children: [
                  for (final e in _engines) EngineTabBody(engine: e),
                ],
              ),
      ),
    );
  }
}

/// 单个引擎的设置项列表（697：抽为公开组件，供 [EngineDetailScreen] 复用）。
///
/// 非 TV 平台由「播放器配置」的 TabBar 直接内嵌；TV 平台由引擎板块
/// 跳转到独立子页后复用同一份内容（单一事实源，避免两处漂移）。
class EngineTabBody extends ConsumerWidget {
  const EngineTabBody({
    super.key,
    required this.engine,
    this.topPadding,
  });

  final PlayerEngine engine;

  /// 顶部内边距。null = 按 TabBar 场景计算（默认）。
  ///
  /// TV 子页没有 TabBar，传 `GlassConfig.topInsetOf(context)` 即可。
  final double? topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      key: ValueKey('engineTab_${engine.id}'),
      padding: EdgeInsets.only(
        top: topPadding ??
            (GlassConfig.topInsetOf(context) + kTextTabBarHeight),
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      children: engineSettingChildren(context, ref, engine),
    );
  }
}

/// 697：按引擎取设置项列表（**单一事实源**）。
///
/// 非 TV 平台的 TabBar 与 TV 的引擎子页都走这里，避免两处设置项漂移。
List<Widget> engineSettingChildren(
  BuildContext context,
  WidgetRef ref,
  PlayerEngine engine,
) {
  final settings = ref.watch(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
  return switch (engine) {
    PlayerEngine.mdk => _mdkChildren(context, settings, notifier),
    PlayerEngine.mediaKit => _mediaKitChildren(context, settings, notifier),
    PlayerEngine.erika => _erikaChildren(context, settings, notifier),
    PlayerEngine.mpv => _mpvChildren(context, settings, notifier),
  };
}

List<Widget> _mpvChildren(
  BuildContext context,
  AppSettings settings,
  SettingsNotifier notifier,
) {
  return [
    const ListTile(
      leading: Icon(Icons.play_circle_outline),
      // 640：原文案写死「HarmonyOS MPV」+「ohcodec 硬件解码」——Android /
      // Windows 也用 MPV（默认内核），且硬解器按平台不同
      // （Android=MediaCodec、Windows=D3D11/DXVA、鸿蒙=ohcodec）。
      // 685：Windows 已统一为 MPV（Qt 独立播放窗 + vo=gpu-next 直出），
      // 原先「641：Windows 已移除 MPV」的说明已过时。
      title: Text('MPV'),
      subtitle: Text(
        'libmpv 内核（Android / Windows / 鸿蒙默认），'
        '支持平台硬件解码、ASS/PGS 字幕与网络缓存。'
        'Windows 走原生顶层窗口 + vo=gpu-next，支持 HDR 直出',
      ),
    ),
    const Divider(height: 1),
    settingOptionTile(
      context: context,
      tvMode: settings.tvMode,
      title: '解码方式',
      subtitle: decodeModeDescription(settings.decodeMode),
      labels: AppSettings.decodeModeLabels,
      value: settings.decodeMode,
      onSelected: (v) => notifier.update(decodeMode: v),
    ),
    const Divider(height: 1),
    // 685：Windows **不再展示**「视频路径」——
    // Windows 只有 Surface 可用（texture 会 0xc0000005 闪退），
    // 给一个点了就崩的下拉框没有意义。运行时由
    // `AppSettings.effectiveMpvVideoOutput` 恒返回 'surface' 兜底。
    //
    // Android/鸿蒙保留可切换（Surface / 纹理都能跑）。
    if (defaultTargetPlatform != TargetPlatform.windows) ...[
      settingOptionTile(
        context: context,
        tvMode: settings.tvMode,
        title: '视频路径',
        subtitle: '默认 Surface 直出（HDR 需显示端支持）；'
            '若出现有声音无画面，请手动切到「纹理」',
        labels: AppSettings.mpvVideoOutputLabels,
        value: AppSettings.effectiveMpvVideoOutput(
          settings.mpvVideoOutput,
          userSet: settings.mpvVideoOutputUserSet,
        ),
        onSelected: (v) => notifier.update(mpvVideoOutput: v),
      ),
    ],
    // 655：渲染器手动选择（仅 Android Surface 路径有意义）。
    //
    // 取代 639 的「GLES 版本自动探测」——版本号无法预测 gpu-next 能否
    // 真正跑起来（驱动可能虚报，Mali-450 就是典型）。现在由用户决定，
    // 遇到黑屏/花屏时手动切 gpu。
    if (defaultTargetPlatform == TargetPlatform.android) ...[
      const Divider(height: 1),
      settingOptionTile(
        context: context,
        tvMode: settings.tvMode,
        title: '渲染器',
        subtitle: '默认 gpu-next（支持 HDR 直出）。'
            '若出现黑屏或花屏，切到「gpu（兼容）」',
        labels: AppSettings.mpvRendererLabels,
        value: settings.mpvRenderer,
        onSelected: (v) => notifier.update(mpvRenderer: v),
      ),
    ],
    // 685：Windows **不再展示**「使用 Qt 播放器窗口」开关——
    // Qt 窗口是 Windows 上唯一完整的播放器（进度条/播放控制/音量/
    // 选集/音轨/字幕）。关掉只剩「有视频没控件」的裸窗口，没有合理
    // 场景。运行时由 `MpvSessionPlatform.qtPlayerEnabled` 恒 true 兜底。
  ];
  }

  // ── MDK ───────────────────────────────────────────────────
List<Widget> _mdkChildren(
  BuildContext context,
  AppSettings settings,
  SettingsNotifier notifier,
) {
  return [
    // 启动设备能力评估结果（HDR/GL/Vulkan/硬解/DV）+ 路由策略预览
    const DeviceCapabilityCard(),
    const SizedBox(height: 4),
    settingOptionTile(
      context: context,
      tvMode: settings.tvMode,
      title: '解码方式',
      subtitle: decodeModeDescription(settings.decodeMode),
      labels: AppSettings.decodeModeLabels,
      value: settings.decodeMode,
      onSelected: (v) => notifier.update(decodeMode: v),
    ),
    const Divider(height: 1),
    settingsTvWrapRow(
      tvMode: settings.tvMode,
      onTap: () => notifier.update(stereoDownmix: !settings.stereoDownmix),
      child: SwitchListTile(
        title: const Text('立体声降混'),
        subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
        value: settings.stereoDownmix,
        onChanged: (v) => notifier.update(stereoDownmix: v),
      ),
    ),
    const Divider(height: 1),
    // ── 网络流缓冲（v1.2.29，setBufferRange / demux.buffer.ranges）──
    // 弱网/高码率（如 4K remux）"一顿一顿"时调大；修改后下次起播生效。
    settingsTvSliderRow(
      context: context,
      tvMode: settings.tvMode,
      title: '最小缓冲',
      subtitle: '${settings.mdkBufferMinMs} ms：起播/欠载恢复前需攒够的缓冲。'
          '越大越不易"一顿一顿"，起播越慢',
      sliderKey: 'mdkBufferMinSlider',
      value: settings.mdkBufferMinMs.toDouble(),
      min: AppSettings.mdkBufferMinMsLower.toDouble(),
      max: AppSettings.mdkBufferMinMsUpper.toDouble(),
      divisions: (AppSettings.mdkBufferMinMsUpper -
              AppSettings.mdkBufferMinMsLower) ~/
          100,
      label: '${settings.mdkBufferMinMs} ms',
      step: 100,
      onChanged: (v) => notifier.update(mdkBufferMinMs: v.round()),
    ),
    const Divider(height: 1),
    settingsTvSliderRow(
      context: context,
      tvMode: settings.tvMode,
      title: '最大缓冲',
      subtitle: settings.mdkBufferMaxMs == 0
          ? '无限：最大程度扛网络抖动（占内存最多）'
          : '${settings.mdkBufferMaxMs} ms：缓冲上限，越大越扛网络抖动、'
              '不影响延迟（占内存）',
      sliderKey: 'mdkBufferMaxSlider',
      value: settings.mdkBufferMaxMs.toDouble(),
      min: AppSettings.mdkBufferMaxMsLower.toDouble(),
      max: AppSettings.mdkBufferMaxMsUpper.toDouble(),
      divisions: AppSettings.mdkBufferMaxMsUpper ~/ 1000,
      label: settings.mdkBufferMaxMs == 0
          ? '无限'
          : '${settings.mdkBufferMaxMs} ms',
      step: 1000,
      onChanged: (v) => notifier.update(mdkBufferMaxMs: v.round()),
    ),
    const Divider(height: 1),
    settingOptionTile(
      context: context,
      tvMode: settings.tvMode,
      title: '段缓存',
      subtitle: settings.mdkDemuxCacheRanges == 0
          ? '关闭：不保留已下载数据（后退 seek 需重下）'
          : '${settings.mdkDemuxCacheRanges} 段：网络流只下一次、加速后退 '
              'seek（纯内存，占内存）',
      labels: const {
        '0': '关闭',
        '2': '2 段',
        '4': '4 段',
        '8': '8 段',
        '16': '16 段',
        '32': '32 段',
      },
      value: '${settings.mdkDemuxCacheRanges}',
      onSelected: (v) => notifier.update(mdkDemuxCacheRanges: int.parse(v)),
    ),
    const Divider(height: 1),
    if (defaultTargetPlatform == TargetPlatform.android) ...[
      settingOptionTile(
        context: context,
        tvMode: settings.tvMode,
        title: '音频后端',
        subtitle: audioRendererDescription(settings.audioRenderer),
        labels: AppSettings.audioRendererLabels,
        value: settings.audioRenderer,
        onSelected: (v) => notifier.update(audioRenderer: v),
      ),
      const Divider(height: 1),
      settingOptionTile(
        context: context,
        tvMode: settings.tvMode,
        title: '视频输出',
        subtitle: videoOutputDescription(settings.videoOutput),
        labels: AppSettings.videoOutputLabels,
        value: settings.videoOutput,
        onSelected: (v) => notifier.update(videoOutput: v),
      ),
      const Divider(height: 1),
    ],
  ];
  }

  // ── media_kit ─────────────────────────────────────────────
List<Widget> _mediaKitChildren(
  BuildContext context,
  AppSettings settings,
  SettingsNotifier notifier,
) {
  const hwdecLabels = {
    'auto-safe': '安全硬解',
    'auto': '全部硬解',
    'no': '软解',
  };
  const toneMappingLabels = {
    'auto': '自动',
    'no': '关闭',
    'bt.2446a': 'BT.2446A',
    'spline': 'Spline',
  };
  return [
    settingOptionTile(
      context: context,
      tvMode: settings.tvMode,
      title: '硬件解码',
      subtitle: 'libmpv vo-gpu 硬解路径（Dolby Vision P5 不支持）',
      labels: hwdecLabels,
      value: settings.mkHwdec,
      onSelected: (v) => notifier.update(mkHwdec: v),
    ),
    const Divider(height: 1),
    settingOptionTile(
      context: context,
      tvMode: settings.tvMode,
      title: '色调映射',
      subtitle: 'HDR → SDR 色调映射算法',
      labels: toneMappingLabels,
      value: settings.mkToneMapping,
      onSelected: (v) => notifier.update(mkToneMapping: v),
    ),
    const Divider(height: 1),
    settingsTvSliderRow(
      context: context,
      tvMode: settings.tvMode,
      title: '缓存大小',
      subtitle: '${settings.mkCacheSize.toInt()} MB（0 = 关闭）',
      sliderKey: 'mkCacheSizeSlider',
      value: settings.mkCacheSize,
      min: 0,
      max: 500,
      divisions: 10,
      label: '${settings.mkCacheSize.toInt()} MB',
      step: 50,
      onChanged: (v) => notifier.update(mkCacheSize: v),
    ),
    const Divider(height: 1),
    const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'media_kit（libmpv）：Android 等平台的 Flutter 纹理路径。'
        '646.1 起 Windows 已移除该选项（Windows 纹理路径会崩在 '
        'flutter_windows.dll 0x1551f），Windows 请用 MPV（原生 HDR 直出）'
        '或 MDK。',
        style: TextStyle(fontSize: 12, color: Colors.white54),
      ),
    ),
  ];
  }

  // ── Erika ─────────────────────────────────────────────────
List<Widget> _erikaChildren(
  BuildContext context,
  AppSettings settings,
  SettingsNotifier notifier,
) {
  return [
    // 启动设备能力评估结果（HDR/GL/Vulkan/硬解/DV）+ 路由策略预览
    const DeviceCapabilityCard(),
    const SizedBox(height: 4),
    const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Erika：原生位图字幕（PGS/VobSub）、原生 GPU 弹幕、'
        '真 HDR10/EDR 输出。\n'
        '输出模式由 Erika 按显示能力协商（HDR/EDR 或 SDR），不再按片源自动切内核。'
        'Android HDR 需可渲染（Vulkan/GLES3，能力卡片可查）：'
        '真 HDR10 另需 Vulkan + HDR 显示，无 HDR 显示时自动回退 SDR。',
        style: TextStyle(fontSize: 12, color: Colors.white54),
      ),
    ),
    const Divider(height: 1),
  ];
}

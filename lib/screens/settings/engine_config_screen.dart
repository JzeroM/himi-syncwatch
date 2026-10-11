import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/player_engine.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 「播放器配置」：顶部 TabBar 按引擎分页（MDK / media_kit / Erika），
/// 每个 tab 是**该引擎专属设置**。
///
/// 本页**不提供引擎切换**——切换只在播放器内（engine_menu_panel）。
/// tab 列表 = 当前平台可用引擎（TV 仅 MDK；media_kit 仅 Windows）。
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
    final tvMode = ref.read(settingsProvider).tvMode;
    _engines = PlayerEngineFactory.supportedEngines(tvMode: tvMode);
    _tab = TabController(length: _engines.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          bottom: TabBar(
            controller: _tab,
            isScrollable: _engines.length > 2,
            tabs: [for (final e in _engines) Tab(text: e.label)],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            for (final e in _engines) _EngineTabBody(engine: e),
          ],
        ),
      ),
    );
  }
}

class _EngineTabBody extends ConsumerWidget {
  const _EngineTabBody({required this.engine});

  final PlayerEngine engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    final children = switch (engine) {
      PlayerEngine.mdk => _mdkChildren(context, settings, notifier),
      PlayerEngine.mediaKit => _mediaKitChildren(context, settings, notifier),
      PlayerEngine.erika => _erikaChildren(context, settings, notifier),
    };

    return ListView(
      key: ValueKey('engineTab_${engine.id}'),
      padding: EdgeInsets.only(
        top: GlassConfig.topInsetOf(context) + kTextTabBarHeight,
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      children: children,
    );
  }

  // ── MDK ───────────────────────────────────────────────────
  List<Widget> _mdkChildren(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    return [
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
      if (defaultTargetPlatform == TargetPlatform.android) ...[
        const Divider(height: 1),
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
      ],
      const Divider(height: 1),
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
      settingsTvWrapRow(
        tvMode: settings.tvMode,
        onTap: () {},
        child: ListTile(
          title: const Text('缓存大小'),
          subtitle: Text('${settings.mkCacheSize.toInt()} MB（0 = 关闭）'),
          trailing: SizedBox(
            width: 200,
            child: Slider(
              value: settings.mkCacheSize,
              min: 0,
              max: 500,
              divisions: 10,
              label: '${settings.mkCacheSize.toInt()} MB',
              onChanged: (v) => notifier.update(mkCacheSize: v),
            ),
          ),
        ),
      ),
      const Divider(height: 1),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'media_kit（libmpv）：Windows 专用引擎。Release 会替换为完整 libmpv。'
          '遇到兼容性问题可切换到 MDK / Erika。',
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
    const outputLabels = {
      'auto': '自动',
      'sdr': 'SDR',
      'extendedLinear': 'Extended Linear（HDR 直通）',
    };
    return [
      settingOptionTile(
        context: context,
        tvMode: settings.tvMode,
        title: '输出模式',
        subtitle: '视频输出色彩空间；HDR 片源选 Extended Linear',
        labels: outputLabels,
        value: settings.erikaOutputMode,
        onSelected: (v) => notifier.update(erikaOutputMode: v),
      ),
      const Divider(height: 1),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Erika（自研内核）：原生位图字幕（PGS/VobSub）、真 HDR10/EDR 输出。'
          '切换引擎后生效。',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ),
    ];
  }
}

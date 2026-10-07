import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/appearance_settings_screen.dart';
import 'package:himi_syncwatch/screens/settings/experimental_settings_screen.dart';
import 'package:himi_syncwatch/screens/settings/general_settings_screen.dart';
import 'package:himi_syncwatch/screens/settings/player_settings_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 设置主页（方案 C）：四个分类入口 → 各分类子页。
/// - 外观：主题色 / 分类页海报数 / 液态玻璃
/// - 播放器：解码 / 音频 / 视频输出 / 网速 / 弹幕配置
/// - 通用：TV 模式 / 运行日志
/// - 实验性：渲染兼容 / 播放调试 / 深度诊断
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return Scaffold(
      key: const ValueKey('settingsPage'),
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: GlassConfig.topInsetOf(context),
          bottom: GlassConfig.bottomReserveOf(context),
        ),
        children: [
          _category(
            context,
            tvMode: tvMode,
            key: const ValueKey('settingsCategoryAppearance'),
            icon: Icons.palette_outlined,
            title: '外观',
            subtitle: '主题色、分类页每行海报数、液态玻璃',
            builder: (_) => const AppearanceSettingsScreen(),
          ),
          const Divider(height: 1),
          _category(
            context,
            tvMode: tvMode,
            key: const ValueKey('settingsCategoryPlayer'),
            icon: Icons.play_circle_outline,
            title: '播放器',
            subtitle: '解码方式、音频、视频输出、网速、弹幕配置',
            builder: (_) => const PlayerSettingsScreen(),
          ),
          const Divider(height: 1),
          _category(
            context,
            tvMode: tvMode,
            key: const ValueKey('settingsCategoryGeneral'),
            icon: Icons.tune,
            title: '通用',
            subtitle: 'TV 模式、导出运行日志',
            builder: (_) => const GeneralSettingsScreen(),
          ),
          const Divider(height: 1),
          _category(
            context,
            tvMode: tvMode,
            key: const ValueKey('settingsCategoryExperimental'),
            icon: Icons.science_outlined,
            title: '实验性',
            subtitle: '渲染兼容模式、播放调试面板、深度诊断',
            builder: (_) => const ExperimentalSettingsScreen(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _category(
    BuildContext context, {
    required bool tvMode,
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required WidgetBuilder builder,
  }) {
    void open() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: builder),
        );
    return settingsTvWrapRow(
      tvMode: tvMode,
      onTap: open,
      child: ListTile(
        key: key,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(
          Icons.chevron_right,
          size: 18,
          color: Colors.white54,
        ),
        onTap: open,
      ),
    );
  }
}

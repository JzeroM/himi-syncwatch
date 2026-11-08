import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/top_bar_clock_format.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/log_service.dart';

/// 通用设置子页：TV 模式 / 导出运行日志。
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  /// 测试用平台覆盖（642）。
  ///
  /// 真实判定是 `Platform.isAndroid`，但 `flutter test` 跑在 Linux 主机上，
  /// 无法用 `debugDefaultTargetPlatformOverride` 影响 `dart:io` 的
  /// `Platform.isAndroid` → 需要这个显式开关验证「TV 模式开关仅安卓可见」。
  @visibleForTesting
  static bool? debugPlatformIsAndroidOverride;

  /// TV 模式开关是否显示：**仅安卓**（642）。
  ///
  /// TV 模式是「遥控器 D-pad 适配」，只有安卓 TV/盒子有遥控。Windows /
  /// 鸿蒙 / iOS 显示它只会把布局切成 TV 观感却无法用遥控操作。
  @visibleForTesting
  static bool showTvModeSwitch() =>
      debugPlatformIsAndroidOverride ?? Platform.isAndroid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('generalSettingsPage'),
      title: '通用',
      children: [
        // TV 模式：**仅安卓显示**（642）。
        //
        // 原条件 `!Platform.isWindows` 只挡了 Windows，鸿蒙/iOS 仍会看到
        // 这个开关——但 TV 模式是「遥控器 D-pad 适配」，只有安卓 TV/盒子
        // 有遥控。鸿蒙/iOS 打开它只会把布局切成 TV 观感却无法用遥控操作。
        // 加载时非安卓已由 `applyTvAutoDetection` 强制关闭并清存档。
        if (showTvModeSwitch()) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(tvMode: !settings.tvMode),
            child: SwitchListTile(
              title: const Text('TV 模式'),
              subtitle: const Text('适配遥控器：方向键导航，OK 键选择'),
              value: settings.tvMode,
              onChanged: (v) => notifier.update(tvMode: v),
            ),
          ),
          const Divider(height: 1),
        ],
        // 同步到 TV：TV 模式下隐藏（TV 是被推送方，无需此开关）
        if (!settings.tvMode) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () =>
                notifier.update(tvSyncEnabled: !settings.tvSyncEnabled),
            child: SwitchListTile(
              title: const Text('同步到 TV'),
              subtitle: const Text('服务器页显示电视机控件，可发现局域网 TV 并推送配置'),
              value: settings.tvSyncEnabled,
              onChanged: (v) => notifier.update(tvSyncEnabled: v),
            ),
          ),
          const Divider(height: 1),
        ],
        if (settings.tvMode) ...[
          KeyedSubtree(
            key: const ValueKey('topBarClockSetting'),
            child: settingOptionTile(
              context: context,
              tvMode: settings.tvMode,
              title: '顶栏时间',
              subtitle: '播放器顶栏最右侧显示系统时间，控制栏隐藏后仍显示',
              labels: const {
                'off': '关闭',
                '12h': '12 小时制',
                '24h': '24 小时制',
              },
              value: settings.topBarClockFormat.storageValue,
              onSelected: (value) => notifier.update(
                topBarClockFormat: TopBarClockFormat.fromStorage(value),
              ),
            ),
          ),
          const Divider(height: 1),
        ],
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/general/trakt'),
          child: ListTile(
            key: const ValueKey('traktSettingsEntry'),
            leading: const Icon(Icons.sync_alt),
            title: const Text('Trakt 同步'),
            subtitle: const Text('跨服务器同步已看状态与播放进度'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/general/trakt'),
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => context.push('/settings/general/cache'),
          child: ListTile(
            key: const ValueKey('cacheSettingsEntry'),
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('缓存管理'),
            subtitle: const Text('清理图片、弹幕、临时文件与诊断日志'),
            trailing: const Icon(
              Icons.chevron_right,
              size: 18,
              color: Colors.white54,
            ),
            onTap: () => context.push('/settings/general/cache'),
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => LogService().shareLogs(),
          child: ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('导出运行日志'),
            subtitle: const Text('保存最近 1000 条日志并分享'),
            onTap: () => LogService().shareLogs(),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

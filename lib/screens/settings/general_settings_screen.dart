import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/log_service.dart';

/// 通用设置子页：TV 模式 / 导出运行日志。
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('generalSettingsPage'),
      title: '通用',
      children: [
        // TV 模式：Windows 桌面隐藏（无遥控；加载时已强制关闭）
        if (!Platform.isWindows) ...[
          settingsTvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => notifier.update(tvMode: !settings.tvMode),
            child: SwitchListTile(
              title: const Text('TV 模式'),
              subtitle: const Text('适配遥控器：方向键导航，OK 键选择，中键暂停/播放'),
              value: settings.tvMode,
              onChanged: (v) => notifier.update(tvMode: v),
            ),
          ),
          const Divider(height: 1),
        ],
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => notifier.update(tvSyncEnabled: !settings.tvSyncEnabled),
          child: SwitchListTile(
            title: const Text('同步到 TV'),
            subtitle: const Text('服务器页显示电视机控件，可发现局域网 TV 并推送配置'),
            value: settings.tvSyncEnabled,
            onChanged: (v) => notifier.update(tvSyncEnabled: v),
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

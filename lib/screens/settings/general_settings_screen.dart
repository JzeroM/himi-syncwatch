import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
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
        // TV 模式仅 Android（含 Android TV）：其他平台无遥控器/无 SurfaceView
        // 能力，隐藏开关（非 Android 启动时也会复位为 false）。
        if (defaultTargetPlatform == TargetPlatform.android) ...[
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

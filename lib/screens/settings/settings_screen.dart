import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';

String _decodeModeDescription(String mode) {
  switch (mode) {
    case 'auto':
      return '智能选择：自动匹配最佳解码方式';
    case 'hw':
      return '硬解：强制纯硬解码，失败不回退';
    case 'sw':
      return '软解：纯软解码，CPU 占用高';
    default:
      return '建议默认使用智能选择';
  }
}

String _audioRendererDescription(String renderer) {
  switch (renderer) {
    case 'auto':
      return '使用系统默认音频后端';
    case 'AAudio':
      return 'AAudio：现代低延迟后端（默认）';
    case 'OpenSL':
      return 'OpenSL：时钟精度更高，改善 TrueHD 等音频流畅度';
    case 'AudioTrack':
      return 'AudioTrack：兼容性最好的传统后端';
    default:
      return '建议默认使用自动';
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('解码方式'),
            subtitle: Text(_decodeModeDescription(settings.decodeMode)),
            trailing: DropdownButton<String>(
              value: settings.decodeMode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).update(decodeMode: value);
                }
              },
              items: AppSettings.decodeModeLabels.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('立体声降混'),
            subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
            value: settings.stereoDownmix,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(stereoDownmix: v),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('音频后端'),
            subtitle: Text(_audioRendererDescription(settings.audioRenderer)),
            trailing: DropdownButton<String>(
              value: settings.audioRenderer,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).update(audioRenderer: value);
                }
              },
              items: AppSettings.audioRendererLabels.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('同步调试面板'),
            subtitle: const Text('仅在房间内显示，可拖拽移动'),
            value: settings.showSyncDebug,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(showSyncDebug: v),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('导出运行日志'),
            subtitle: const Text('保存最近 1000 条日志并分享'),
            onTap: () => LogService().shareLogs(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

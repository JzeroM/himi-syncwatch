import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';

String _decodeModeDescription(String mode) {
  switch (mode) {
    case 'auto':
      return '智能选择：自动匹配最佳解码方式';
    case 'hw+':
      return 'HW+：强制硬解码+回拷，兼容性最好';
    case 'hw':
      return 'HW：强制纯硬解码，失败不回退';
    case 'sw':
      return 'SW：纯软解码，CPU 占用高';
    default:
      return '建议默认使用智能选择';
  }
}

const _bufferStops = [32, 64, 128, 256, 512, 1024];

double _bufferToSlider(int mb) {
  final idx = _bufferStops.indexOf(mb);
  return idx >= 0 ? idx.toDouble() : 0.0;
}

int _sliderToBuffer(int index) => _bufferStops[index.clamp(0, 5)];

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '视频缓存大小 (MB)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _bufferToSlider(settings.bufferSizeMB),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: '${settings.bufferSizeMB}',
                  onChanged: (v) {
                    final mb = _sliderToBuffer(v.round());
                    ref.read(settingsProvider.notifier).update(bufferSizeMB: mb);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 48,
                  child: Text(
                    '${settings.bufferSizeMB}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
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
          SwitchListTile(
            title: const Text('杜比视界硬件解码'),
            subtitle: const Text('默认关闭(安全)。开启后DV内容尝试硬件解码，需设备支持'),
            value: settings.dvHwDecode,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(dvHwDecode: v),
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

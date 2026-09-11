import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';

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
          SwitchListTile(
            title: const Text('硬解码'),
            subtitle: const Text('启用硬件加速解码，降低 CPU 占用'),
            value: settings.hardwareDecoding,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).update(hardwareDecoding: value);
            },
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
        ],
      ),
    );
  }
}

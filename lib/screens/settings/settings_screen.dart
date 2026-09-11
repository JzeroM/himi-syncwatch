import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';

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
        ],
      ),
    );
  }
}

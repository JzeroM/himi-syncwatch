import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';

/// 片头片尾配置子页：总开关、自动跳过与操作说明。
class IntroOutroSettingsScreen extends ConsumerWidget {
  const IntroOutroSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('introOutroSettingsPage'),
      title: '片头片尾配置',
      children: [
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => notifier.update(
            skipIntroOutroEnabled: !settings.skipIntroOutroEnabled,
          ),
          child: SwitchListTile(
            key: const ValueKey('skipIntroOutroSwitch'),
            title: const Text('跳过片头片尾'),
            subtitle: const Text('显示片头/片尾跳过提示，支持长按手动标记'),
            value: settings.skipIntroOutroEnabled,
            onChanged: (v) => notifier.update(skipIntroOutroEnabled: v),
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => notifier.update(
            autoSkipIntroOutroEnabled: !settings.autoSkipIntroOutroEnabled,
          ),
          child: SwitchListTile(
            key: const ValueKey('autoSkipIntroOutroSwitch'),
            title: const Text('自动跳过'),
            subtitle: const Text('检测到片头/片尾后直接跳过；需同时开启跳过片头片尾'),
            value: settings.autoSkipIntroOutroEnabled,
            onChanged: (v) => notifier.update(autoSkipIntroOutroEnabled: v),
          ),
        ),
        const Divider(height: 1),
        const Padding(
          key: ValueKey('introOutroUsageSection'),
          padding: EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '使用说明',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '手动设置片头片尾：手机长按视频左侧 1/3 设置片头结束点，'
                '长按右侧 1/3 设置片尾开始点；TV 长按进度条打开标记面板来设置。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.white60,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '自动跳过开启后，检测到片头/片尾直接执行跳过，'
                '不再等待手动确认。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

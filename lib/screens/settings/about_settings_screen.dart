import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/update/update_prompt.dart';

/// 关于子页：版本信息 / 检查更新 / 新版本提醒开关。
class AboutSettingsScreen extends ConsumerStatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  ConsumerState<AboutSettingsScreen> createState() =>
      _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends ConsumerState<AboutSettingsScreen> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = '未知');
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await checkAndPromptUpdate(context, ref, manual: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _lastCheckText(int ms) {
    if (ms <= 0) return '尚未检查过';
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('aboutSettingsPage'),
      title: '关于',
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('HIMI 私密同步观影'),
          subtitle: Text(_version.isEmpty ? '版本读取中…' : '版本 $_version'),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: _check,
          child: ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: Text(_checking
                ? '正在检查…'
                : '当前 ${_version.isEmpty ? '未知' : 'v$_version'}'),
            trailing: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, size: 18),
            onTap: _check,
          ),
        ),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () =>
              notifier.update(updatePromptEnabled: !settings.updatePromptEnabled),
          child: SwitchListTile(
            title: const Text('新版本提醒'),
            subtitle: const Text('启动时自动检查，发现新版本时提示（可在提示里选「永不提醒」关闭）'),
            value: settings.updatePromptEnabled,
            onChanged: (v) => notifier.update(updatePromptEnabled: v),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: const Text('上次检查'),
          subtitle: Text(_lastCheckText(settings.lastUpdateCheckAt)),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

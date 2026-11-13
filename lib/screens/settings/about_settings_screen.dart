import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/update/update_prompt.dart';

/// 关于子页：版本信息 / 检查更新 / 新版本提醒 / 联系方式 / 开源。
class AboutSettingsScreen extends ConsumerStatefulWidget {
  const AboutSettingsScreen({super.key});

  /// 项目仓库地址。
  static const githubUrl = 'https://github.com/JzeroM/himi-syncwatch';

  /// 项目 QQ 群。
  static const qqGroup = '1041283071';

  /// 联系邮箱。
  static const email = '2640256446jm@gmail.com';

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

  /// 用系统浏览器/邮件客户端打开链接。
  ///
  /// 失败时给 Toast 提示——部分设备没装邮件客户端或浏览器，
  /// `launchUrl` 会返回 false（不抛异常），静默失败会让用户以为点击无效。
  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) showAppToast(context, '无法打开：$url');
    } catch (e) {
      LogService().log('About', '打开链接失败: $url ($e)');
      if (mounted) showAppToast(context, '无法打开：$url');
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
        // 690：分组玻璃卡片——版本 / 更新
        SettingsGroupCard(
          title: '版本',
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('HIMI 私密同步观影'),
              subtitle:
                  Text(_version.isEmpty ? '版本读取中…' : '版本 $_version'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('上次检查'),
              subtitle: Text(_lastCheckText(settings.lastUpdateCheckAt)),
            ),
          ],
        ),
        SettingsGroupCard(
          title: '更新',
          children: [
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
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => notifier.update(
                  updatePromptEnabled: !settings.updatePromptEnabled),
              child: SwitchListTile(
                title: const Text('新版本提醒'),
                subtitle: const Text('启动时自动检查，发现新版本时提示（可在提示里选「永不提醒」关闭）'),
                value: settings.updatePromptEnabled,
                onChanged: (v) => notifier.update(updatePromptEnabled: v),
              ),
            ),
          ],
        ),
        // 697：联系方式（用户反馈渠道）
        SettingsGroupCard(
          title: '联系方式',
          children: [
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => _open(AboutSettingsScreen.githubUrl),
              child: ListTile(
                key: const ValueKey('aboutGithub'),
                leading: const Icon(Icons.code),
                title: const Text('项目主页'),
                subtitle: Text(AboutSettingsScreen.githubUrl),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _open(AboutSettingsScreen.githubUrl),
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => _open(
                'mqqapi://card/show_pslcard?src_type=internal&version=1'
                '&uin=${AboutSettingsScreen.qqGroup}&card_type=group&source=qrcode',
              ),
              child: ListTile(
                key: const ValueKey('aboutQqGroup'),
                leading: const Icon(Icons.groups_outlined),
                title: const Text('QQ 群'),
                subtitle: Text(AboutSettingsScreen.qqGroup),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _open(
                  'mqqapi://card/show_pslcard?src_type=internal&version=1'
                  '&uin=${AboutSettingsScreen.qqGroup}&card_type=group&source=qrcode',
                ),
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => _open('mailto:${AboutSettingsScreen.email}'),
              child: ListTile(
                key: const ValueKey('aboutEmail'),
                leading: const Icon(Icons.mail_outline),
                title: const Text('邮箱'),
                subtitle: Text(AboutSettingsScreen.email),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _open('mailto:${AboutSettingsScreen.email}'),
              ),
            ),
          ],
        ),
        // 697：开源声明
        SettingsGroupCard(
          title: '开源',
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('开源软件'),
              subtitle: const Text(
                '本项目开源，欢迎提交 Issue 与 Pull Request。'
                '基于 Flutter / libmpv / 液态玻璃等开源项目构建',
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'HIMI 私密同步观影',
                applicationVersion: _version.isEmpty ? null : _version,
              ),
              child: ListTile(
                key: const ValueKey('aboutThirdPartyLicenses'),
                leading: const Icon(Icons.article_outlined),
                title: const Text('开源许可'),
                subtitle: const Text('Flutter 及所有依赖库的许可声明'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'HIMI 私密同步观影',
                  applicationVersion: _version.isEmpty ? null : _version,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

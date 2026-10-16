import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/server_route_service.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';
import 'package:himi_syncwatch/widgets/sheet_bottom_safe_area.dart';
import 'package:image_picker/image_picker.dart';

/// 打开「服务设置」底部面板（重新登录 / 修改密码 / 上传头像 / STRM 直链播放）。
Future<void> showServiceSettingsSheet(
  BuildContext context,
  EmbyServerConfig server,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E1E2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ServiceSettingsSheet(server: server),
  );
}

class _ServiceSettingsSheet extends ConsumerStatefulWidget {
  const _ServiceSettingsSheet({required this.server});

  final EmbyServerConfig server;

  @override
  ConsumerState<_ServiceSettingsSheet> createState() =>
      _ServiceSettingsSheetState();
}

class _ServiceSettingsSheetState extends ConsumerState<_ServiceSettingsSheet> {
  late bool _strmDirectPlay = widget.server.strmDirectPlay;

  /// 头像缓存破值：上传成功后追加为查询参数强制刷新。
  String? _avatarTag;

  EmbyServerConfig get _server => widget.server;

  EmbyService get _service => ref.read(embyServiceForProvider(_server.id));

  Future<void> _relogin() async {
    final input = await _promptRelogin();
    if (input == null || !mounted) return;
    try {
      final authResult = await ref
          .read(embyAuthClientProvider)
          .authenticate(
            serverUrl: _server.effectiveUrl,
            username: input.username,
            password: input.password,
            deviceId: _server.id,
          );
      final user = authResult['User'] as Map?;
      final userId = user?['Id'] as String? ?? '';
      final accessToken = authResult['AccessToken'] as String? ?? '';
      if (userId.isEmpty || accessToken.isEmpty) {
        throw Exception('服务端返回数据异常');
      }
      final updated = _server.copyWith(
        username: input.username,
        accessToken: accessToken,
        userId: userId,
        serverId: authResult['ServerId'] as String? ?? _server.serverId,
      );
      ref.read(embyServerListProvider.notifier).updateServer(updated);
      if (ref.read(embyConfigProvider)?.id == updated.id) {
        ref.read(embyConfigProvider.notifier).setConfig(updated);
      }
      await ref.read(embyAuthServiceProvider).saveSession(
            serverId: updated.serverId,
            serverUrl: updated.serverUrl,
            serverName: updated.serverName,
            userId: updated.userId ?? '',
            username: updated.username,
            accessToken: updated.accessToken ?? '',
            id: updated.id,
            routes: updated.routes.map((r) => r.toJson()).toList(),
            activeRouteUrl: updated.activeRouteUrl,
            autoFailover: updated.autoFailover,
            strmDirectPlay: updated.strmDirectPlay,
          );
      if (!mounted) return;
      setState(() => _avatarTag = null);
      showAppToast(context, '重新登录成功');
    } catch (e) {
      if (mounted) showAppToast(context, '重新登录失败：$e');
    }
  }

  Future<void> _changePassword() async {
    final input = await _promptPassword();
    if (input == null || !mounted) return;
    try {
      await _service.changePassword(
        currentPassword: input.current,
        newPassword: input.newPassword,
      );
      if (mounted) showAppToast(context, '密码修改成功');
    } catch (e) {
      if (mounted) showAppToast(context, '修改密码失败：$e');
    }
  }

  Future<void> _uploadAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null || !mounted) return;
    try {
      final bytes = await picked.readAsBytes();
      final isPng = picked.path.toLowerCase().endsWith('.png');
      await _service.uploadUserImage(
        bytes,
        contentType: isPng ? 'image/png' : 'image/jpeg',
      );
      if (!mounted) return;
      setState(() =>
          _avatarTag = DateTime.now().millisecondsSinceEpoch.toString());
      showAppToast(context, '头像已更新');
    } catch (e) {
      if (mounted) showAppToast(context, '上传头像失败：$e');
    }
  }

  Future<void> _toggleStrm(bool value) async {
    setState(() => _strmDirectPlay = value);
    try {
      await ref
          .read(serverRouteServiceProvider)
          .setStrmDirectPlay(_server, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _strmDirectPlay = !value);
      showAppToast(context, '设置失败：$e');
    }
  }

  Future<_ReloginInput?> _promptRelogin() async {
    final userCtrl = TextEditingController(text: _server.username);
    final pwCtrl = TextEditingController();
    return showDialog<_ReloginInput>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              _ReloginInput(userCtrl.text.trim(), pwCtrl.text),
            ),
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<_PasswordInput?> _promptPassword() async {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    return showDialog<_PasswordInput>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('修改密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: curCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密码'),
              ),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '确认新密码'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (newCtrl.text.isEmpty) {
                  setDialogState(() => error = '新密码不能为空');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  setDialogState(() => error = '两次输入的新密码不一致');
                  return;
                }
                Navigator.of(ctx)
                    .pop(_PasswordInput(curCtrl.text, newCtrl.text));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetBottomSafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _Avatar(server: _server, tag: _avatarTag),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _server.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _server.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('serviceSettingsClose'),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _ActionTile(
                  key: const ValueKey('serviceRelogin'),
                  icon: Icons.login,
                  label: '重新登录',
                  onTap: _relogin,
                ),
                _ActionTile(
                  key: const ValueKey('serviceChangePassword'),
                  icon: Icons.lock_outline,
                  label: '修改密码',
                  onTap: _changePassword,
                ),
                _ActionTile(
                  key: const ValueKey('serviceUploadAvatar'),
                  icon: Icons.image_outlined,
                  label: '上传头像',
                  onTap: _uploadAvatar,
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassContainer(
              borderRadius: BorderRadius.circular(14),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: SwitchListTile(
                key: const ValueKey('serviceStrmDirectPlay'),
                value: _strmDirectPlay,
                onChanged: _toggleStrm,
                title: const Text(
                  'STRM 直链播放',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: const Text(
                  '开启后使用服务器返回的直链地址作为播放地址，服务器不兼容时可能导致无法播放。',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ReloginInput {
  const _ReloginInput(this.username, this.password);
  final String username;
  final String password;
}

class _PasswordInput {
  const _PasswordInput(this.current, this.newPassword);
  final String current;
  final String newPassword;
}

/// 用户头像：优先加载服务器头像，失败/未登录回退渐变字标。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.server, this.tag});

  final EmbyServerConfig server;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final token = server.accessToken;
    final url = tag == null || tag!.isEmpty
        ? '${server.mediaUrl}/Users/${server.userId}/Images/Primary'
        : '${server.mediaUrl}/Users/${server.userId}/Images/Primary?tag=$tag';
    if (token == null || token.isEmpty || server.userId == null) {
      return ServerAvatar(label: server.label);
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        headers: {'X-Emby-Token': token},
        errorBuilder: (_, __, ___) => ServerAvatar(label: server.label),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white70, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

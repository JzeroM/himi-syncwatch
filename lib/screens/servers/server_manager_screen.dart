import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// Emby 服务器管理页（原侧边栏服务器区域，现为独立标签页）。
class ServerManagerScreen extends ConsumerStatefulWidget {
  const ServerManagerScreen({super.key});

  @override
  ConsumerState<ServerManagerScreen> createState() =>
      _ServerManagerScreenState();
}

class _ServerManagerScreenState extends ConsumerState<ServerManagerScreen> {
  bool _showAddServerForm = false;

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(embyServerListProvider);
    final currentConfig = ref.watch(embyConfigProvider);

    final seenServerIds = <String>{};
    final dedupedServers = <EmbyServerConfig>[];
    for (final s in servers) {
      if (seenServerIds.add(s.serverId)) {
        dedupedServers.add(s);
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Emby 服务器'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: '手机扫码配置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const QrConfigScreen(mode: 'emby'),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_showAddServerForm ? Icons.close : Icons.add),
            tooltip: _showAddServerForm ? '取消添加' : '添加服务器',
            onPressed: () =>
                setState(() => _showAddServerForm = !_showAddServerForm),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: GlassConfig.topInsetOf(context)),
          if (_showAddServerForm)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: GlassConfig.bottomReserveOf(context)),
                child: _AddServerForm(
                  onSuccess: () {
                    if (!mounted) return;
                    setState(() => _showAddServerForm = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('服务器已添加')),
                    );
                  },
                ),
              ),
            )
          else
            Expanded(
              child: dedupedServers.isEmpty
                  ? const _EmptyServerHint()
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: GlassConfig.bottomReserveOf(context),
                      ),
                      itemCount: dedupedServers.length,
                      itemBuilder: (context, index) {
                        final server = dedupedServers[index];
                        final isActive = currentConfig?.id == server.id;
                        return _ServerTile(
                          server: server,
                          isActive: isActive,
                          onTap: isActive ? null : () => _switchServer(server),
                          onEdit: isActive
                              ? () => _showEditServerDialog(server)
                              : null,
                          onDelete: () => _deleteServer(server, isActive),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _switchServer(EmbyServerConfig server) async {
    ref.read(embyConfigProvider.notifier).setConfig(server);
    await ref.read(embyAuthServiceProvider).saveSelectedServerId(server.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到「${server.label}」')),
    );
  }

  Future<void> _deleteServer(EmbyServerConfig server, bool isActive) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除 "${server.label}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final authService = ref.read(embyAuthServiceProvider);
    await authService.deleteSession(server.serverId);
    ref.read(embyServerListProvider.notifier).removeServer(server.id);

    if (isActive) {
      final remaining = ref.read(embyServerListProvider);
      if (remaining.isNotEmpty) {
        ref.read(embyConfigProvider.notifier).setConfig(remaining.first);
        await authService.saveSelectedServerId(remaining.first.id);
      } else {
        ref.read(embyConfigProvider.notifier).clear();
        await authService.saveSelectedServerId('');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除「${server.label}」')),
    );
  }

  void _showEditServerDialog(EmbyServerConfig server) {
    final nameController = TextEditingController(text: server.serverName);
    final urlController = TextEditingController(text: server.serverUrl);
    final usernameController = TextEditingController(text: server.username);
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '服务器名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://emby.example.com:8920',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码（留空保持不变）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => _saveEdit(
              ctx,
              server,
              name: nameController.text.trim(),
              url: urlController.text.trim(),
              username: usernameController.text.trim(),
              password: passwordController.text,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEdit(
    BuildContext ctx,
    EmbyServerConfig server, {
    required String name,
    required String url,
    required String username,
    required String password,
  }) async {
    if (url.isEmpty || username.isEmpty) return;

    final authService = ref.read(embyAuthServiceProvider);

    try {
      if (password.isNotEmpty) {
        final authResult = await EmbyService().authenticate(
          serverUrl: url,
          username: username,
          password: password,
          deviceId: server.id,
        );
        final newServerId = authResult['ServerId'] ?? server.serverId;
        final newConfig = server.copyWith(
          serverUrl: url,
          serverName: name,
          username: username,
          accessToken: authResult['AccessToken'],
          userId: authResult['User']['Id'],
          serverId: newServerId,
        );

        final existingServers = ref.read(embyServerListProvider);
        for (final other in existingServers) {
          if (other.id != server.id && other.serverId == newServerId) {
            await authService.deleteSession(other.serverId);
            ref.read(embyServerListProvider.notifier).removeServer(other.id);
          }
        }

        ref.read(embyServerListProvider.notifier).updateServer(newConfig);
        ref.read(embyConfigProvider.notifier).setConfig(newConfig);
        await authService.saveSelectedServerId(newConfig.id);
        await authService.deleteSession(server.serverId);
        await authService.saveSession(
          serverId: newConfig.serverId,
          serverUrl: url,
          serverName: name,
          userId: newConfig.userId!,
          username: username,
          accessToken: newConfig.accessToken!,
          id: newConfig.id,
        );
      } else {
        final newConfig = server.copyWith(
          serverUrl: url,
          serverName: name,
          username: username,
        );
        ref.read(embyServerListProvider.notifier).updateServer(newConfig);
        if (ref.read(embyConfigProvider)?.id == server.id) {
          ref.read(embyConfigProvider.notifier).setConfig(newConfig);
          await authService.saveSelectedServerId(newConfig.id);
        }
        await authService.deleteSession(server.serverId);
        await authService.saveSession(
          serverId: newConfig.serverId,
          serverUrl: url,
          serverName: name,
          userId: newConfig.userId ?? '',
          username: username,
          accessToken: newConfig.accessToken ?? '',
          id: newConfig.id,
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('编辑失败: $e')),
        );
      }
      return;
    }

    if (ctx.mounted) Navigator.pop(ctx);
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.dns,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        server.label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        '${server.username} · ${server.serverUrl}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              if (onEdit != null)
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('删除', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (value) {
              if (value == 'edit') {
                onEdit?.call();
              } else if (value == 'delete') {
                onDelete();
              }
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyServerHint extends StatelessWidget {
  const _EmptyServerHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '暂无服务器\n点击右上角 + 添加',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}

class _AddServerForm extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;
  const _AddServerForm({required this.onSuccess});

  @override
  ConsumerState<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends ConsumerState<_AddServerForm> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _serverName;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pingAndLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref.read(embySetupServiceProvider).addAndActivate(
            serverUrl: _urlController.text,
            username: _usernameController.text,
            password: _passwordController.text,
            serverName: _nameController.text,
            onServerInfo: (name) {
              if (mounted) setState(() => _serverName = name);
            },
          );

      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serverName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已连接: $_serverName',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://emby.example.com:8096',
              prefixIcon: Icon(Icons.dns),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '备注名称（可选）',
              hintText: '如：家里NAS',
              prefixIcon: Icon(Icons.label),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _pingAndLogin,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('连接并登录'),
            ),
          ),
        ],
      ),
    );
  }
}

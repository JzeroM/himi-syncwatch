import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _CategoryData {
  final LibraryFolder folder;
  final List<MediaItem> items;
  _CategoryData({required this.folder, required this.items});
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<_CategoryData> _categories = [];
  bool _isLoading = true;
  String? _error;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final authService = ref.read(embyAuthServiceProvider);
    final serverIds = await authService.listServerIds();

    if (serverIds.isNotEmpty) {
      final configs = <EmbyServerConfig>[];
      EmbyServerConfig? activeConfig;

      for (final sid in serverIds) {
        final session = await authService.loadSession(sid);
        if (session != null) {
          final config = EmbyServerConfig.fromJson(session);
          configs.add(config);
          if (activeConfig == null) activeConfig = config;
        }
      }

      ref.read(embyServerListProvider.notifier).setList(configs);

      if (activeConfig != null) {
        ref.read(embyConfigProvider.notifier).setConfig(activeConfig);
        await _loadMedia();
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }

    setState(() => _initialized = true);
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final libraries = await embyService.getLibraries();

      final futures = libraries.map((lib) async {
        final items = await embyService.getItems(
          parentId: lib.id,
          limit: 20,
          includeItemTypes: 'Movie,Series',
          fields: 'ImageTags,PrimaryImageAspectRatio,ProductionYear',
        );
        return _CategoryData(folder: lib, items: items);
      }).toList();

      final results = await Future.wait(futures);
      final categories = results.where((c) => c.items.isNotEmpty).toList();

      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated == true;

    return Scaffold(
      drawer: _ServerDrawer(onRefresh: _loadMedia),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('HimiSync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '加入房间',
            onPressed: () => _showJoinRoomDialog(context),
          ),
          if (hasServer)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _showSearch(context),
            ),
        ],
      ),
      body: !hasServer
          ? const _EmptyState()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadMedia,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMedia,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          return _CategorySection(
                            category: cat,
                            onViewAll: () => context.push(
                              '/category/${cat.folder.id}?name=${Uri.encodeComponent(cat.folder.name)}&type=${cat.folder.collectionType}',
                            ),
                            onItemTap: (item) =>
                                context.push('/detail/${item.id}'),
                          );
                        },
                      ),
                    ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _MediaSearchDelegate(ref));
  }

  void _showJoinRoomDialog(BuildContext context) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('加入房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                hintText: '粘贴房间码',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: '你的昵称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              if (code.isNotEmpty && name.isNotEmpty) {
                Navigator.pop(context);
                context.push(
                  '/room?code=${Uri.encodeComponent(code)}&name=${Uri.encodeComponent(name)}',
                );
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            '暂无服务器',
            style: TextStyle(fontSize: 18, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            '点击左上角 ☰ 添加 Emby 服务器',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final _CategoryData category;
  final VoidCallback onViewAll;
  final void Function(MediaItem item) onItemTap;

  const _CategorySection({
    required this.category,
    required this.onViewAll,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: GestureDetector(
            onTap: onViewAll,
            child: Row(
              children: [
                Text(
                  category.folder.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: category.items.length,
            itemBuilder: (context, index) {
              final item = category.items[index];
              return SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _PosterCard(
                    item: item,
                    onTap: () => onItemTap(item),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  const _PosterCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.year != null)
                    Text(
                      item.year!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerDrawer extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const _ServerDrawer({required this.onRefresh});

  @override
  ConsumerState<_ServerDrawer> createState() => _ServerDrawerState();
}

class _ServerDrawerState extends ConsumerState<_ServerDrawer> {
  bool _showAddServerForm = false;
  bool _showAgoraForm = false;

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(embyServerListProvider);
    final currentConfig = ref.watch(embyConfigProvider);
    final agoraConfig = ref.watch(agoraConfigProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 服务器区域 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '服务器',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(_showAddServerForm ? Icons.close : Icons.add),
                    tooltip: _showAddServerForm ? '取消添加' : '添加服务器',
                    onPressed: () =>
                        setState(() => _showAddServerForm = !_showAddServerForm),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_showAddServerForm)
              _AddServerForm(
                onSuccess: () {
                  setState(() => _showAddServerForm = false);
                  widget.onRefresh();
                },
              )
            else
              Expanded(
                child: servers.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '暂无服务器\n点击右上角 + 添加',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: servers.length,
                        itemBuilder: (context, index) {
                          final server = servers[index];
                          final isActive = currentConfig?.id == server.id;
                          return ListTile(
                            leading: Icon(
                              Icons.dns,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              server.label,
                              style: TextStyle(
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${server.username} · ${server.serverUrl}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: isActive
                                ? null
                                : () {
                                    ref
                                        .read(embyConfigProvider.notifier)
                                        .setConfig(server);
                                    widget.onRefresh();
                                    Navigator.pop(context);
                                  },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActive)
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 20),
                                PopupMenuButton<String>(
                                  itemBuilder: (context) => [
                                    if (isActive)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('编辑'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      _showEditServerDialog(context, server);
                                    } else if (value == 'delete') {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除服务器'),
                                          content: Text(
                                              '确定删除 "${server.label}" 吗？'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('取消'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('删除',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        final authService = ref.read(
                                            embyAuthServiceProvider);
                                        await authService.deleteSession(
                                            server.serverId);
                                        ref
                                            .read(embyServerListProvider
                                                .notifier)
                                            .removeServer(server.id);
                                        if (isActive) {
                                          final remaining = ref.read(
                                              embyServerListProvider);
                                          if (remaining.isNotEmpty) {
                                            ref
                                                .read(embyConfigProvider
                                                    .notifier)
                                                .setConfig(remaining.first);
                                          } else {
                                            ref
                                                .read(embyConfigProvider
                                                    .notifier)
                                                .clear();
                                          }
                                          widget.onRefresh();
                                        }
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

            // ── Agora 配置区域 ──
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('声网配置'),
              subtitle: Text(
                agoraConfig?.isConfigured == true
                    ? 'App ID: ${agoraConfig!.appId.substring(0, 8)}...'
                    : '未配置',
                style: TextStyle(
                  fontSize: 12,
                  color: agoraConfig?.isConfigured == true
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              trailing: Icon(
                _showAgoraForm ? Icons.expand_less : Icons.expand_more,
              ),
              onTap: () =>
                  setState(() => _showAgoraForm = !_showAgoraForm),
            ),
            if (_showAgoraForm)
              _AgoraConfigForm(
                currentConfig: agoraConfig,
                onSaved: () => setState(() => _showAgoraForm = false),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditServerDialog(BuildContext context, EmbyServerConfig server) {
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
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final username = usernameController.text.trim();
              final password = passwordController.text;

              if (url.isEmpty || username.isEmpty) return;

              final authService = ref.read(embyAuthServiceProvider);

              if (password.isNotEmpty) {
                try {
                  final embyService = EmbyService();
                  final authResult = await embyService.authenticate(
                    serverUrl: url,
                    username: username,
                    password: password,
                    deviceId: server.id,
                  );
                  final newConfig = server.copyWith(
                    serverUrl: url,
                    serverName: name,
                    username: username,
                    accessToken: authResult['AccessToken'],
                    userId: authResult['User']['Id'],
                    serverId: authResult['ServerId'] ?? server.serverId,
                  );
                  ref.read(embyServerListProvider.notifier).updateServer(newConfig);
                  ref.read(embyConfigProvider.notifier).setConfig(newConfig);
                  await authService.deleteSession(server.serverId);
                  await authService.saveSession(
                    serverId: newConfig.serverId,
                    serverUrl: url,
                    serverName: name,
                    userId: newConfig.userId!,
                    username: username,
                    accessToken: newConfig.accessToken!,
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('编辑失败: $e')),
                    );
                  }
                  return;
                }
              } else {
                final newConfig = server.copyWith(
                  serverUrl: url,
                  serverName: name,
                  username: username,
                );
                ref.read(embyServerListProvider.notifier).updateServer(newConfig);
                if (ref.read(embyConfigProvider)?.id == server.id) {
                  ref.read(embyConfigProvider.notifier).setConfig(newConfig);
                }
                await authService.deleteSession(server.serverId);
                await authService.saveSession(
                  serverId: newConfig.serverId,
                  serverUrl: url,
                  serverName: name,
                  userId: newConfig.userId ?? '',
                  username: username,
                  accessToken: newConfig.accessToken ?? '',
                );
              }

              if (ctx.mounted) Navigator.pop(ctx);
              widget.onRefresh();
            },
            child: const Text('保存'),
          ),
        ],
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
      final authService = ref.read(embyAuthServiceProvider);
      final url = _urlController.text.trim();

      final info = await EmbyService().pingServer(url);
      final serverName = info['ServerName'] ?? url;
      final serverId = info['Id'] ?? '';

      setState(() => _serverName = serverName);

      final authResult = await EmbyService().authenticate(
        serverUrl: url,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        deviceId: authService.deviceId,
      );

      final userId = authResult['User']['Id'] as String;
      final accessToken = authResult['AccessToken'] as String;
      final returnedServerId = authResult['ServerId'] as String? ?? serverId;

      final configId = 'srv_${const Uuid().v4().substring(0, 8)}';
      final config = EmbyServerConfig(
        id: configId,
        serverUrl: url,
        serverName: serverName,
        serverId: returnedServerId,
        username: _usernameController.text.trim(),
        accessToken: accessToken,
        userId: userId,
      );

      await authService.saveSession(
        serverId: returnedServerId,
        serverUrl: url,
        serverName: serverName,
        userId: userId,
        username: _usernameController.text.trim(),
        accessToken: accessToken,
      );

      ref.read(embyServerListProvider.notifier).addServer(config);
      ref.read(embyConfigProvider.notifier).setConfig(config);

      widget.onSuccess();
    } catch (e) {
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
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
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

class _AgoraConfigForm extends ConsumerStatefulWidget {
  final AgoraConfigModel? currentConfig;
  final VoidCallback onSaved;
  const _AgoraConfigForm({required this.currentConfig, required this.onSaved});

  @override
  ConsumerState<_AgoraConfigForm> createState() => _AgoraConfigFormState();
}

class _AgoraConfigFormState extends ConsumerState<_AgoraConfigForm> {
  late final TextEditingController _appIdController;
  late final TextEditingController _certController;

  @override
  void initState() {
    super.initState();
    _appIdController = TextEditingController(
        text: widget.currentConfig?.appId ?? '');
    _certController = TextEditingController(
        text: widget.currentConfig?.appCertificate ?? '');
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _certController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _appIdController,
            decoration: const InputDecoration(
              labelText: 'App ID',
              hintText: '声网 App ID',
              prefixIcon: Icon(Icons.vpn_key),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _certController,
            decoration: const InputDecoration(
              labelText: 'App Certificate',
              hintText: '声网 App Certificate',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () async {
                final appId = _appIdController.text.trim();
                final cert = _certController.text.trim();
                if (appId.isEmpty) return;

                final config = AgoraConfigModel(
                  appId: appId,
                  appCertificate: cert,
                );
                await ref.read(agoraConfigProvider.notifier).save(config);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('声网配置已保存')),
                  );
                  widget.onSaved();
                }
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;
  _MediaSearchDelegate(this.ref);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.length < 1) {
      return const Center(child: Text('输入关键词进行搜索'));
    }
    return FutureBuilder<List<MediaItem>>(
      future: ref.read(embyServiceProvider).searchItems(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('未找到结果'));
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: SizedBox(
                width: 50,
                height: 70,
                child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
              ),
              title: Text(item.name),
              subtitle: Text(item.year ?? ''),
              onTap: () {
                close(context, '');
                context.push('/detail/${item.id}');
              },
            );
          },
        );
      },
    );
  }
}

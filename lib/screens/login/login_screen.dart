import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:uuid/uuid.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = ref.read(embyConfigProvider);
    if (config != null) {
      _serverUrlController.text = config.serverUrl;
      _usernameController.text = config.username;
      _displayNameController.text = config.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final userId = await embyService.authenticate(
        serverUrl: _serverUrlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
      );

      if (userId != null) {
        final serverId = 'server_${const Uuid().v4().substring(0, 8)}';
        final config = EmbyServerConfig(
          id: serverId,
          serverUrl: _serverUrlController.text,
          username: _usernameController.text,
          accessToken: embyService.accessToken,
          userId: userId,
          displayName: _displayNameController.text.isNotEmpty
              ? _displayNameController.text
              : null,
        );

        await ref.read(embyConfigProvider.notifier).saveConfig(config);
        await ref.read(embyServerListProvider.notifier).addServer(config);

        if (mounted) {
          context.go('/');
        }
      } else {
        setState(() {
          _error = '登录失败，请检查服务器地址和账号密码';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '连接失败: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.movie_filter,
                size: 80,
                color: Color(0xFF6366F1),
              ),
              const SizedBox(height: 16),
              const Text(
                'HimiSync',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '连接你的 Emby 媒体服务器',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: '服务器名称（可选）',
                  hintText: '如：家里NAS',
                  prefixIcon: Icon(Icons.label),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.100:8096',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('登录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

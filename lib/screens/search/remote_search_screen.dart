import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:himi_syncwatch/providers/remote_search_provider.dart';
import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 扫码远程搜索页（TV）：展示二维码，手机扫码后在手机上搜索，
/// 点选卡片电视自动打开对应详情。
///
/// - 进入自动启动服务，返回（本页被 pop）才停止——详情压栈期间服务持续，
///   手机可继续选片/搜下一部
/// - 连续选片：栈顶已是详情时先返回再打开新的（栈恒为 首页→扫码→详情）
/// - 角落保留「电视本机搜索」次要入口（push 本地搜索页）
class RemoteSearchScreen extends ConsumerStatefulWidget {
  const RemoteSearchScreen({super.key});

  @override
  ConsumerState<RemoteSearchScreen> createState() => _RemoteSearchScreenState();
}

class _RemoteSearchScreenState extends ConsumerState<RemoteSearchScreen> {
  StreamSubscription<RemoteSelection>? _selectionSub;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(remoteSearchProvider.notifier).start());
    _selectionSub =
        ref.read(remoteSearchProvider.notifier).selections.listen(_openDetail);
  }

  @override
  void dispose() {
    _selectionSub?.cancel();
    super.dispose();
  }

  void _openDetail(RemoteSelection sel) {
    if (!mounted) return;
    final router = GoRouter.of(context);
    if (router.state.uri.path.startsWith('/detail/')) {
      // 连续选片：先弹掉栈顶旧详情，保持 首页→扫码→详情 单层
      router.pop();
    }
    context.push<dynamic>(
      '/detail/${sel.itemId}?server=${Uri.encodeComponent(sel.serverId)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(remoteSearchProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(remoteSearchProvider.notifier).stop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('手机扫码搜索')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildBody(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(RemoteSearchState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.error != null)
          _buildFailure(state.error!)
        else if (!state.running || state.url == null)
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 16),
              Text('正在启动远程搜索服务…'),
            ],
          )
        else
          _buildRunning(state),
        const SizedBox(height: 24),
        _buildLocalSearchEntry(),
      ],
    );
  }

  Widget _buildRunning(RemoteSearchState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '用手机扫描二维码\n在手机上搜索，点选结果电视即打开',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: state.url!,
            size: 240,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          state.url!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF9AA0B8),
            fontFamily: 'monospace',
          ),
        ),
        if (state.ips.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            '本机局域网地址：${state.ips.join(' / ')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6F7590)),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          '请确保手机与本机连接同一 WiFi',
          style: TextStyle(fontSize: 12, color: Color(0xFF6F7590)),
        ),
        if (state.lastSelectedName != null) ...[
          const SizedBox(height: 16),
          _SelectedCard(name: state.lastSelectedName!),
        ],
      ],
    );
  }

  /// 三态共用的角落备选入口：电视本机搜索。
  Widget _buildLocalSearchEntry() {
    return TvFocusable(
      key: const ValueKey('localSearchEntry'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const GlobalSearchScreen(),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          '电视本机搜索',
          style: TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildFailure(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 20),
        TvFocusable(
          onTap: () => ref.read(remoteSearchProvider.notifier).start(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '重试',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

/// 手机已选片状态卡片。
class _SelectedCard extends StatelessWidget {
  const _SelectedCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF34D399);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '手机已选择：$name',
              style: const TextStyle(fontSize: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

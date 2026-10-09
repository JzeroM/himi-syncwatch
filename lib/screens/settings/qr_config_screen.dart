import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/lan_config_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 局域网扫码配置页：展示二维码与地址，手机浏览器打开后提交即落到本机。
///
/// [mode] 为 `emby` 时二维码打开 Emby 配置区块；`danmaku` 时打开弹幕
/// API 地址区块；其余默认 Emby。进入自动启动服务，离开（返回）自动停止。
class QrConfigScreen extends ConsumerStatefulWidget {
  const QrConfigScreen({super.key, this.mode = ''});

  final String mode;

  @override
  ConsumerState<QrConfigScreen> createState() => _QrConfigScreenState();
}

class _QrConfigScreenState extends ConsumerState<QrConfigScreen> {
  bool get _isDanmaku => widget.mode == 'danmaku';

  String get _title => _isDanmaku ? '扫码配置弹幕 API' : '扫码配置 Emby';

  String get _tip => _isDanmaku
      ? '用手机扫描二维码\n或在手机浏览器打开下方地址\n'
          '在手机上填写弹幕 API 地址并提交'
      : '用手机扫描二维码\n或在手机浏览器打开下方地址';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(lanConfigProvider.notifier).start());
  }

  String _urlWithMode(String url) =>
      widget.mode.isEmpty ? url : '$url&mode=${widget.mode}';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lanConfigProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(lanConfigProvider.notifier).stop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
        ),
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

  Widget _buildBody(LanConfigState state) {
    if (state.running && state.url != null) {
      return _buildQrView(state);
    }
    if (state.lastOk == false) {
      return _buildFailure(state.lastMessage ?? '服务启动失败');
    }
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(height: 16),
        Text('正在启动局域网配置服务…'),
      ],
    );
  }

  Widget _buildQrView(LanConfigState state) {
    final url = _urlWithMode(state.url!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _tip,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: url,
            size: 240,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          url,
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
        if (state.lastMessage != null) ...[
          const SizedBox(height: 16),
          _ResultCard(ok: state.lastOk == true, message: state.lastMessage!),
        ],
      ],
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
          onTap: () => ref.read(lanConfigProvider.notifier).start(),
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF34D399) : Colors.redAccent;
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
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 14, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

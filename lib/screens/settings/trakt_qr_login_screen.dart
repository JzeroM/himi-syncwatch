import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TraktQrLoginScreen extends ConsumerStatefulWidget {
  const TraktQrLoginScreen({super.key});

  @override
  ConsumerState<TraktQrLoginScreen> createState() => _TraktQrLoginScreenState();
}

class _TraktQrLoginScreenState extends ConsumerState<TraktQrLoginScreen> {
  Timer? _timer;
  bool _started = false;
  bool _completed = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _started) return;
    _started = true;
    setState(() => _startError = null);
    final notifier = ref.read(traktProvider.notifier);
    await notifier.cancelDeviceFlow();
    final code = await notifier.startDeviceFlow();
    if (!mounted) {
      unawaited(notifier.cancelDeviceFlow());
      return;
    }
    if (code == null) {
      setState(() {
        _started = false;
        _startError = ref.read(traktProvider).error ?? '无法启动 Trakt 授权';
      });
      return;
    }
    _timer?.cancel();
    final interval = Duration(seconds: code.interval <= 0 ? 5 : code.interval);
    _timer = Timer.periodic(interval, (_) {
      if (!mounted || _completed) return;
      if (ref.read(traktProvider).deviceCode == null) {
        _timer?.cancel();
        return;
      }
      unawaited(notifier.pollDeviceFlow());
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showAppToast(context, '设备码已复制');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || ok) return;
    showAppToast(context, '无法打开浏览器');
  }

  @override
  void dispose() {
    _stopTimer();
    unawaited(ref.read(traktProvider.notifier).cancelDeviceFlow());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TraktAppState>(traktProvider, (previous, next) {
      if (next.connected && !_completed) {
        _completed = true;
        _stopTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
      if (previous?.deviceCode != null &&
          next.deviceCode == null &&
          !next.connected &&
          !_completed) {
        _stopTimer();
        setState(() {
          _startError = next.error ?? '授权未完成';
          _started = false;
        });
      }
    });

    final state = ref.watch(traktProvider);
    final code = state.deviceCode;

    return SettingsSubPage(
      pageKey: const ValueKey('traktQrLoginPage'),
      title: '扫码配置 Trakt',
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Text(
            '用手机扫描二维码，打开 Trakt 授权页并输入下方设备码。'
            '授权成功后电视端会自动完成登录。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white60,
              height: 1.5,
            ),
          ),
        ),
        if (_startError != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 44, color: Colors.red.shade300),
                const SizedBox(height: 12),
                Text(
                  _startError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _start,
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else if (code == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 16),
                Text('正在获取设备码…'),
              ],
            ),
          )
        else ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: code.verificationUrl,
                size: 240,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              code.userCode,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () => _copyCode(code.userCode),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制设备码'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => _openUrl(code.verificationUrl),
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: Text(code.verificationUrl),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  '等待手机授权…',
                  style: TextStyle(fontSize: 13, color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

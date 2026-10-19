import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/update_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/update/apk_installer.dart';
import 'package:himi_syncwatch/services/update/update_platform.dart';
import 'package:himi_syncwatch/services/update/update_service.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_option_dialog.dart';

/// 自动检查节流间隔：同一设备 24h 内只静默检查一次。
const updateCheckInterval = Duration(hours: 24);

/// 读取当前应用版本（versionName；失败返回空串）。
Future<String> currentAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '';
  }
}

/// 当前设备支持的 ABI 列表（非 Android 返回空）。
Future<List<String>> currentSupportedAbis() async {
  if (!Platform.isAndroid) return const [];
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.supportedAbis;
  } catch (_) {
    return const [];
  }
}

/// 检查更新并按需弹层。
///
/// [manual] = true（关于页手动点击）：忽略「永不提醒 / 24h 节流 / 忽略此版本」，
/// 失败与已是最新都有明确反馈；auto 时全部静默。
/// 返回是否弹出了「发现新版本」层。
Future<bool> checkAndPromptUpdate(
  BuildContext context,
  WidgetRef ref, {
  required bool manual,
}) async {
  final settings = ref.read(settingsProvider);
  if (!manual) {
    if (!settings.updatePromptEnabled) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (settings.lastUpdateCheckAt > 0 &&
        now - settings.lastUpdateCheckAt <
            updateCheckInterval.inMilliseconds) {
      return false;
    }
  }

  final target = currentUpdateTarget();
  if (target == null) {
    if (manual) _toast(context, '当前平台暂不支持应用内更新');
    return false;
  }

  final version = await currentAppVersion();
  if (version.isEmpty) {
    if (manual) _toast(context, '无法读取当前版本号');
    return false;
  }

  final service = ref.read(updateServiceProvider);
  final result = await service.check(
    currentVersion: version,
    target: target,
    supportedAbis: await currentSupportedAbis(),
  );
  if (!context.mounted) return false;

  switch (result.status) {
    case UpdateStatus.failed:
      if (manual) _toast(context, '检查更新失败，请稍后重试');
      return false;
    case UpdateStatus.upToDate:
      _markChecked(ref);
      if (manual) _toast(context, '已是最新版本 v$version');
      return false;
    case UpdateStatus.available:
      _markChecked(ref);
      final asset = result.asset!;
      // 自动提醒尊重「忽略此版本」；手动检查始终提示
      if (!manual && asset.version == settings.skipUpdateVersion) {
        return false;
      }
      await _promptUpdate(context, ref, asset);
      return true;
  }
}

/// 记录本次检查时间（仅成功时；失败不写，避免网络抖动后 24h 才能重试）。
void _markChecked(WidgetRef ref) {
  ref.read(settingsProvider.notifier).update(
        lastUpdateCheckAt: DateTime.now().millisecondsSinceEpoch,
      );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _promptUpdate(
  BuildContext context,
  WidgetRef ref,
  RemoteAsset asset,
) async {
  final installable = UpdateInstaller.supportsInAppInstall;
  final choice = await showTvOptionDialog<String>(
    context: context,
    title: '发现新版本 v${asset.version}',
    currentValue: '',
    onSelected: (_) {},
    options: [
      TvOptionEntry(
        value: 'update',
        label: installable ? '去更新' : '去下载',
        subtitle: _assetSubtitle(asset),
      ),
      const TvOptionEntry(value: 'later', label: '以后再说', subtitle: '下次启动再提醒'),
      TvOptionEntry(
        value: 'skip',
        label: '忽略此版本',
        subtitle: '仅跳过 v${asset.version}',
      ),
      const TvOptionEntry(
        value: 'never',
        label: '永不提醒',
        subtitle: '不再自动提示，可在「关于」页重新打开',
      ),
    ],
  );
  if (!context.mounted) return;

  final notifier = ref.read(settingsProvider.notifier);
  switch (choice) {
    case 'update':
      if (installable) {
        await _downloadAndInstall(context, ref, asset);
      } else {
        // iOS：打开签名直链（Safari 落下 ipa），用户自行安装。
        // 必须现取 raw_url：静态 /d/ 在开启「直链签名」的实例上会 401。
        String url;
        try {
          url = await ref
              .read(updateServiceProvider)
              .resolveDownloadUrl(asset.name);
        } catch (e) {
          LogService().log('Update', '解析下载地址失败: $e');
          if (context.mounted) _toast(context, '无法获取下载链接，请稍后重试');
          return;
        }
        if (!context.mounted) return;
        final ok = await UpdateInstaller.openExternal(url);
        if (!ok && context.mounted) _toast(context, '无法打开下载链接');
      }
    case 'skip':
      await notifier.update(skipUpdateVersion: asset.version);
    case 'never':
      await notifier.update(updatePromptEnabled: false);
    default:
      break; // 以后再说
  }
}

String _assetSubtitle(RemoteAsset asset) {
  final parts = <String>['v${asset.version}'];
  if (asset.abi != null && asset.abi != 'universal') parts.add(asset.abi!);
  if (asset.size > 0) {
    parts.add('${(asset.size / 1024 / 1024).toStringAsFixed(1)} MB');
  }
  return parts.join(' · ');
}

/// 下载更新包（进度弹层）并调起安装。
Future<void> _downloadAndInstall(
  BuildContext context,
  WidgetRef ref,
  RemoteAsset asset,
) async {
  final service = ref.read(updateServiceProvider);
  final file = await showDialog<File>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDownloadDialog(service: service, asset: asset),
  );
  if (file == null || !context.mounted) return;
  await _installDownloaded(context, file, depth: 0);
}

/// 安装已下载的更新包；Android 缺「安装未知应用」授权时引导授权后重试。
Future<void> _installDownloaded(
  BuildContext context,
  File file, {
  required int depth,
}) async {
  final outcome = await UpdateInstaller.installFile(file);
  if (!context.mounted) return;

  switch (outcome) {
    case InstallOutcome.launched:
      if (Platform.isWindows) {
        // Inno（CloseApplications=yes）会关闭运行中的应用；主动退出更顺滑，
        // 装完由安装程序 postinstall 自动拉起新版
        _toast(context, '安装程序已启动，应用即将退出');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        exit(0);
      }
      _toast(context, '已调起安装器，请按提示完成更新');
    case InstallOutcome.needsPermission:
      if (depth >= 3) {
        _toast(context, '未获得「安装未知应用」权限，已取消');
        return;
      }
      final go = await showTvOptionDialog<String>(
        context: context,
        title: '需要「安装未知应用」权限',
        currentValue: '',
        onSelected: (_) {},
        options: const [
          TvOptionEntry(value: 'settings', label: '去授权', subtitle: '在系统设置里允许 HIMI 安装应用'),
          TvOptionEntry(value: 'cancel', label: '取消'),
        ],
      );
      if (go != 'settings' || !context.mounted) return;
      await ApkInstaller.openInstallSettings();
      if (!context.mounted) return;
      await _installDownloaded(context, file, depth: depth + 1);
    case InstallOutcome.unsupported:
      _toast(context, '当前平台不支持应用内安装');
    case InstallOutcome.failed:
      _toast(context, '安装器拉起失败，可在文件管理中手动安装');
  }
}

/// 下载进度弹层：进度/速度/取消/失败重试。
class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({required this.service, required this.asset});

  final UpdateService service;
  final RemoteAsset asset;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  CancelToken _cancelToken = CancelToken();
  final _stopwatch = Stopwatch();
  int _received = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _received = 0;
      _total = widget.asset.size;
      _cancelToken = CancelToken();
      _stopwatch
        ..reset()
        ..start();
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = await widget.service.download(
        widget.asset,
        dir: dir,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        Navigator.of(context).pop();
        return;
      }
      LogService().log('Update', '下载失败: $e');
      setState(() => _error = friendlyDownloadMessage(e));
    }
  }

  String get _statusLine {
    if (_error != null) return '下载失败';
    if (_stopwatch.elapsed.inMilliseconds > 500 && _received > 0) {
      final mbps = _received / 1024 / 1024 / (_stopwatch.elapsedMilliseconds / 1000);
      return '${mbps.toStringAsFixed(2)} MB/s';
    }
    return '正在下载…';
  }

  String get _sizeLine {
    final received = (_received / 1024 / 1024).toStringAsFixed(1);
    if (_total <= 0) return '$received MB';
    final total = (_total / 1024 / 1024).toStringAsFixed(1);
    final pct = (_received * 100 / _total).clamp(0, 100).toStringAsFixed(0);
    return '$received / $total MB（$pct%）';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return AlertDialog(
      title: Text('更新 v${widget.asset.version}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: _error != null ? 0 : progress),
            const SizedBox(height: 12),
            Text(_sizeLine),
            const SizedBox(height: 4),
            Text(
              _error ?? _statusLine,
              style: TextStyle(
                fontSize: 12,
                color: _error != null ? Colors.redAccent : Colors.white70,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_error != null)
          TvFocusable(
            scale: 1.0,
            onTap: () => unawaited(_start()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('重试'),
            ),
          ),
        TvFocusable(
          scale: 1.0,
          autofocus: _error != null,
          onTap: () {
            _cancelToken.cancel();
            Navigator.of(context).pop();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('取消'),
          ),
        ),
      ],
    );
  }
}

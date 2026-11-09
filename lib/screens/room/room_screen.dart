import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:himi_syncwatch/services/qr_export_service.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';
import 'package:himi_syncwatch/providers/native_player_provider.dart';
import 'package:himi_syncwatch/services/player/mpv_session_platform.dart';

class RoomScreen extends ConsumerStatefulWidget {
  final String roomCode;
  final String audienceName;

  const RoomScreen({super.key, required this.roomCode, this.audienceName = ''});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  Map<String, dynamic>? _roomData;
  String? _error;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _decodeRoom();
  }

  void _decodeRoom() {
    try {
      final data = RoomCode.decode(widget.roomCode);
      setState(() => _roomData = data);
    } catch (e) {
      setState(() => _error = '房间码无效');
    }
  }

  Future<void> _shareRoomCode() async {
    // 590：鸿蒙已支持系统分享（share_plus 有 OHOS 实现），不再拦截。
    await SharePlus.instance.share(
      ShareParams(
        text: '来一起看电影吧！\n\n房间码：\n${widget.roomCode}\n\n在 HIMI 中扫码或粘贴即可加入',
        subject: 'HIMI 观影邀请',
      ),
    );
  }

  Future<Uint8List?> _captureQrImage() async {
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// 保存二维码到相册（590）。
  ///
  /// 旧实现直写 `/storage/emulated/0/DCIM/Himi`：Android 10+ 抛
  /// `PathAccessException: errno = 13`；鸿蒙被显式拦成「暂不支持」；iOS 写到
  /// 应用私有 Documents（用户在相册里看不到）。现统一走 [QrExportService]。
  Future<void> _saveQrToGallery() async {
    final bytes = await _captureQrImage();
    if (bytes == null) {
      if (mounted) showAppToast(context, '二维码生成失败，请重试');
      return;
    }
    if (!mounted) return;
    final result = await QrExportService.save(
      bytes,
      fileName: 'himi_qr',
      subDir: 'Himi',
    );
    if (!mounted) return;
    switch (result) {
      case QrExportResult.ok:
        showAppToast(context, '已保存到相册');
      case QrExportResult.cancelled:
        break;
      case QrExportResult.unsupported:
        showAppToast(context, '当前平台暂不支持保存到相册');
      case QrExportResult.failed:
        showAppToast(context, '保存失败，请重试');
    }
  }

  /// 分享二维码（590）：统一走 [QrExportService]（Windows 走剪贴板）。
  Future<void> _shareQrImage() async {
    final bytes = await _captureQrImage();
    if (bytes == null) {
      if (mounted) showAppToast(context, '二维码生成失败，请重试');
      return;
    }
    if (!mounted) return;
    final result = await QrExportService.share(
      bytes,
      fileName: 'himi_qr',
      subject: 'HIMI 房间二维码',
      text: '来一起看电影吧！用 HIMI 扫描二维码加入房间',
    );
    if (!mounted) return;
    switch (result) {
      case QrExportResult.ok:
        if (Platform.isWindows) {
          showAppToast(context, '二维码图片已复制，可直接粘贴');
        }
      case QrExportResult.cancelled:
        break;
      case QrExportResult.unsupported:
        showAppToast(context, '当前平台暂不支持分享');
      case QrExportResult.failed:
        showAppToast(context, '分享失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间详情'),
        leading: const TvBackButton(),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            )
          : _roomData == null
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final appId = _roomData!['appId'] as String? ?? '';
    final channel = _roomData!['channel'] as String? ?? '';
    final mediaItemId = _roomData!['mediaItemId'] as String? ?? '';
    final tokens = _roomData!['tokens'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // QR Code 卡片
          Card(
            color: const Color(0xFF1E1E2E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    '扫码加入',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  RepaintBoundary(
                    key: _qrKey,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: widget.roomCode,
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '长按保存图片 · 在 HIMI 中扫码加入',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saveQrToGallery,
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: const Text('保存图片'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _shareQrImage,
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('分享图片'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: widget.roomCode));
                            showAppToast(context, '已复制房间码');
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('复制'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 房间码卡片
          Card(
            color: const Color(0xFF1E1E2E),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '房间码',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      widget.roomCode,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _shareRoomCode,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('分享房间码'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 房间信息
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '房间信息',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('频道', channel),
                  _buildInfoRow('App ID', '${appId.substring(0, 8)}...'),
                  _buildInfoRow('可用 Token 数', '${tokens.length}'),
                ],
              ),
            ),
          ),
          const Spacer(),

          // 进入按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () async {
                // 649：原生播放器已开着 → 只聚焦窗口，不重复 push。
                if (ref.read(nativePlayerActiveProvider)) {
                  await MpvSessionPlatform.focusHostWindow();
                  return;
                }
                final nameParam = widget.audienceName.isNotEmpty
                    ? '&name=${Uri.encodeComponent(widget.audienceName)}'
                    : '';
                context.push(
                  '/player/$mediaItemId?roomCode=${Uri.encodeComponent(widget.roomCode)}&isHost=false$nameParam',
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('进入播放', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
            ),
          ),
          SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

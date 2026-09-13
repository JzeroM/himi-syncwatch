import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:himi_syncwatch/utils/room_code.dart';

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
    await SharePlus.instance.share(
      ShareParams(
        text: '来一起看电影吧！\n\n房间码：\n${widget.roomCode}\n\n在 HIMI 中扫码或粘贴即可加入',
        subject: 'HIMI 观影邀请',
      ),
    );
  }

  Future<Uint8List?> _captureQrImage() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveQrToGallery() async {
    final bytes = await _captureQrImage();
    if (bytes == null || !mounted) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/himi_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);

      if (Platform.isAndroid) {
        // Android: 复制到 DCIM
        final dcimDir = Directory('/storage/emulated/0/DCIM/Himi');
        if (!dcimDir.existsSync()) dcimDir.createSync(recursive: true);
        final dest = File('${dcimDir.path}/himi_qr_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.copy(dest.path);
      } else if (Platform.isIOS) {
        // iOS: 复制到应用 Documents 目录供用户手动保存
        final docsDir = await getApplicationDocumentsDirectory();
        final dest = File('${docsDir.path}/himi_qr.png');
        await file.copy(dest.path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _shareQrImage() async {
    final bytes = await _captureQrImage();
    if (bytes == null || !mounted) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/himi_qr.png');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'HIMI 房间二维码',
          text: '来一起看电影吧！用 HIMI 扫描二维码加入房间',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间详情'),
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
                            Clipboard.setData(ClipboardData(text: widget.roomCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制房间码')),
                            );
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
              onPressed: () {
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

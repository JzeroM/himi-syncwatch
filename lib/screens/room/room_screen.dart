import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
        text: '来一起看电影吧！\n\n房间码：\n${widget.roomCode}\n\n在 HimiSync 中粘贴即可加入',
        subject: 'HimiSync 观影邀请',
      ),
    );
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: widget.roomCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制房间码')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('复制'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _shareRoomCode,
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('分享'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                  '/player/$mediaItemId?roomCode=${Uri.encodeComponent(widget.roomCode)}&isHost=true$nameParam',
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('进入播放', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
            ),
          ),
          const SizedBox(height: 16),
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

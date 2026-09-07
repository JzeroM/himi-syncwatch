import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/room.dart';
import 'package:himi_syncwatch/services/room_service.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

final roomServiceProvider = Provider<RoomService>((ref) => RoomService());

class RoomScreen extends ConsumerStatefulWidget {
  final String roomId;

  const RoomScreen({super.key, required this.roomId});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  Room? _room;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  Future<void> _loadRoom() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final roomService = ref.read(roomServiceProvider);
      final room = await roomService.getRoom(widget.roomId);

      setState(() {
        _room = room;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _joinRoom() async {
    if (_room == null) return;

    // 跳转到播放器，由播放器处理加入房间逻辑
    if (mounted) {
      context.push(
        '/player/${_room!.mediaItemId}?roomId=${widget.roomId}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('房间详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRoom,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRoom,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _room == null
                  ? const Center(child: Text('房间不存在'))
                  : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报
          if (_room!.mediaItemPosterUrl != null)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: EmbyImage(
                  url: _room!.mediaItemPosterUrl,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 片名
          Center(
            child: Text(
              _room!.mediaItemName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),

          // 房间信息卡片
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
                  _buildInfoRow('房间号', _room!.id),
                  _buildInfoRow('房主', _room!.hostName),
                  _buildInfoRow('成员数', '${_room!.members.length}'),
                  _buildInfoRow(
                    '创建时间',
                    '${_room!.createdAt.year}-'
                    '${_room!.createdAt.month.toString().padLeft(2, '0')}-'
                    '${_room!.createdAt.day.toString().padLeft(2, '0')} '
                    '${_room!.createdAt.hour.toString().padLeft(2, '0')}:'
                    '${_room!.createdAt.minute.toString().padLeft(2, '0')}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 成员列表
          if (_room!.members.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '成员列表',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._room!.members.map(
                      (member) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: member.isHost
                              ? const Color(0xFF6366F1)
                              : Colors.grey,
                          child: Text(
                            member.name[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                        title: Text(member.name),
                        trailing: member.isHost
                            ? const Chip(
                                label: Text('房主',
                                    style: TextStyle(fontSize: 10)),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const Spacer(),

          // 加入按钮
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _joinRoom,
              icon: const Icon(Icons.play_arrow),
              label: const Text('加入观看', style: TextStyle(fontSize: 16)),
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
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

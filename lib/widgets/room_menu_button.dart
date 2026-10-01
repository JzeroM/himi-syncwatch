import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 顶部「房间」入口按钮 + 房间卡片全套交互
/// （创建房间 / 加入房间 / 扫码 / 房间码）。
///
/// 从首页 AppBar 迁出为共享组件：TV 顶栏与首页顶栏（非 TV）复用。
/// TV 模式渲染为带焦点环的 [TvFocusable]，非 TV 保持原 IconButton 形态。
class RoomMenuButton extends ConsumerWidget {
  const RoomMenuButton({super.key, this.qrScan});

  /// 测试注入点：返回房间码模拟扫码结果；为 null 时走真实 `/scan` 路由。
  @visibleForTesting
  final Future<String?> Function()? qrScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated ?? false;
    final open = () => _showRoomCard(context, ref, hasServer: hasServer);

    if (tvMode) {
      return TvFocusable(
        radius: 12,
        onTap: open,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.meeting_room_outlined),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.meeting_room_outlined),
      tooltip: '房间',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: open,
    );
  }

  /// 房间入口玻璃卡片：创建房间 / 加入房间二选一。
  void _showRoomCard(
    BuildContext context,
    WidgetRef ref, {
    required bool hasServer,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Material(
          type: MaterialType.transparency,
          child: GlassContainer(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    '房间',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _roomOption(
                  dialogContext: dialogContext,
                  icon: Icons.add_circle_outline,
                  title: '创建房间',
                  subtitle: '开一局同步观影',
                  enabled: hasServer,
                  run: () => _createEmptyRoom(context, ref),
                ),
                _roomOption(
                  dialogContext: dialogContext,
                  icon: Icons.group_add,
                  title: '加入房间',
                  subtitle: '粘贴或扫码加入',
                  enabled: true,
                  run: () => _showJoinRoomDialog(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomOption({
    required BuildContext dialogContext,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback run,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled
            ? () {
                Navigator.pop(dialogContext);
                run();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.white70),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  void _showJoinRoomDialog(BuildContext context, WidgetRef ref) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result =
                      await (qrScan?.call() ?? context.push<String>('/scan'));
                  if (result == null || !context.mounted) return;
                  final roomData = RoomCode.decode(result);
                  if (roomData == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('扫码结果无效')),
                    );
                    return;
                  }
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    // 弹窗保持打开，把码写回输入框，等昵称填好后点「加入」
                    codeController.text = result;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已扫描到房间码，请填写昵称后加入')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext);
                  context.push(
                    '/player/_?roomCode=${Uri.encodeComponent(result)}&isHost=false&name=${Uri.encodeComponent(name)}',
                  );
                },
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('扫码加入'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              if (code.isNotEmpty && name.isNotEmpty) {
                Navigator.pop(dialogContext);
                final roomData = RoomCode.decode(code);
                if (roomData == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('房间码无效')),
                  );
                  return;
                }
                context.push(
                  '/player/_?roomCode=${Uri.encodeComponent(code)}&isHost=false&name=${Uri.encodeComponent(name)}',
                );
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  Future<void> _createEmptyRoom(BuildContext context, WidgetRef ref) async {
    final agoraConfig = ref.read(agoraConfigProvider);
    if (agoraConfig == null || !agoraConfig.isConfigured) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('请先在「声网配置」页填写 App ID 和 App Certificate')),
        );
      }
      return;
    }

    final tokenCount = await _showTokenCountDialog(context);
    if (tokenCount == null) return;

    final channel = RoomCode.generateChannelId();
    final roomCode = RoomCode.encode(
      appId: agoraConfig.appId,
      appCertificate: agoraConfig.appCertificate,
      channel: channel,
      tokenCount: tokenCount,
    );

    if (context.mounted) {
      context.push(
        '/player/_?roomCode=${Uri.encodeComponent(roomCode)}&isHost=true',
      );
    }
  }

  Future<int?> _showTokenCountDialog(BuildContext context) {
    final controller = TextEditingController(text: '2');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('房间最大人数', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null && n > 0 && n <= 100) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

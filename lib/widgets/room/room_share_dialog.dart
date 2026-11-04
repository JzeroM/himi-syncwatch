import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RoomShareDialog extends StatefulWidget {
  const RoomShareDialog({
    super.key,
    required this.roomCode,
    required this.onShareQr,
    required this.onSaveQr,
    required this.onCopyCode,
  });

  final String roomCode;

  /// 分享/保存回调，**由弹窗自己截图后把字节传出去**（590）。
  ///
  /// 旧实现把 `GlobalKey` 从播放页/房间页传进来、回调再自己去
  /// `currentContext` 找 RenderRepaintBoundary——但 RepaintBoundary 实际挂在
  /// 本弹窗内部，只有弹窗打开时 key 才有值，时序稍有偏差就截图失败
  /// （真机「二维码生成失败，请重试」）。现在 key 由弹窗自持、截图在弹窗内
  /// 完成，调用方不再依赖外部 key。
  final Future<void> Function(Uint8List? bytes) onShareQr;
  final Future<void> Function(Uint8List? bytes) onSaveQr;
  final Future<void> Function() onCopyCode;

  @override
  State<RoomShareDialog> createState() => _RoomShareDialogState();
}

class _RoomShareDialogState extends State<RoomShareDialog> {
  bool _busy = false;

  /// 二维码卡片截图边界（弹窗自持，不再由调用方传入）。
  final GlobalKey _qrKey = GlobalKey();

  /// 截取二维码卡片为 PNG 字节；失败返回 null。
  ///
  /// 加 [Duration] 超时：`RepaintBoundary.toImage` 在极端情况（引擎未完成
  /// 首帧、rasterizer 卡住、widget 测试环境无真实光栅化）可能永不返回，
  /// 会让按钮一直处于 busy 态（弹窗卡死）。超时后按「截图失败」处理，
  /// 由调用方提示重试。
  Future<Uint8List?> _captureBytes() async {
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary
          .toImage(pixelRatio: 3.0)
          .timeout(const Duration(seconds: 2));
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  ButtonStyle get _secondaryStyle => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '分享加入房间',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('roomShareClose'),
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  '扫描二维码加入房间，或复制房间码分享给好友',
                  style: TextStyle(fontSize: 13, color: Colors.white54),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 420;
                    final qrSize = wide ? 200.0 : 180.0;
                    final qrCard = RepaintBoundary(
                      key: _qrKey,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: widget.roomCode,
                          version: QrVersions.auto,
                          size: qrSize,
                          backgroundColor: Colors.white,
                          semanticsLabel: '房间二维码',
                        ),
                      ),
                    );
                    final actions = _buildActions();
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: qrCard),
                          const SizedBox(height: 20),
                          actions,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        qrCard,
                        const SizedBox(width: 24),
                        Expanded(child: actions),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            key: const ValueKey('roomSharePrimary'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.onShareQr(await _captureBytes());
                    }),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('分享二维码'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            key: const ValueKey('roomShareSave'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await widget.onSaveQr(await _captureBytes());
                    }),
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('保存二维码'),
            style: _secondaryStyle,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: OutlinedButton.icon(
            key: const ValueKey('roomShareCopy'),
            onPressed: _busy ? null : () => _run(widget.onCopyCode),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制房间码'),
            style: _secondaryStyle,
          ),
        ),
      ],
    );
  }
}

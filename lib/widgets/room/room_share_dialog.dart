import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RoomShareDialog extends StatefulWidget {
  const RoomShareDialog({
    super.key,
    required this.roomCode,
    required this.qrKey,
    required this.onShareQr,
    required this.onSaveQr,
    required this.onCopyCode,
  });

  final String roomCode;
  final GlobalKey qrKey;
  final Future<void> Function() onShareQr;
  final Future<void> Function() onSaveQr;
  final Future<void> Function() onCopyCode;

  @override
  State<RoomShareDialog> createState() => _RoomShareDialogState();
}

class _RoomShareDialogState extends State<RoomShareDialog> {
  bool _busy = false;

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
                      key: widget.qrKey,
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
            onPressed: _busy ? null : () => _run(widget.onShareQr),
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
            onPressed: _busy ? null : () => _run(widget.onSaveQr),
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

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_page.dart';
import 'package:himi_syncwatch/widgets/agora/agora_book_palette.dart';
import 'package:himi_syncwatch/widgets/tv/tv_exclude_editable.dart';

class AgoraBookConfigPage extends StatelessWidget {
  const AgoraBookConfigPage({
    super.key,
    required this.index,
    required this.total,
    required this.palette,
    required this.configured,
    required this.editing,
    required this.tvMode,
    required this.appId,
    required this.appIdController,
    required this.certController,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onClear,
  });

  final int index;
  final int total;
  final AgoraBookPalette palette;
  final bool configured;
  final bool editing;
  final bool tvMode;
  final String appId;
  final TextEditingController appIdController;
  final TextEditingController certController;
  final VoidCallback onEdit;
  final VoidCallback? onCancel;
  final VoidCallback onSave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AgoraBookPaperPage(
      index: index,
      total: total,
      palette: palette,
      kicker: '配置 / $total',
      title: '填写并保存声网凭证',
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(
              configured: configured,
              editing: editing,
              appId: appId,
              palette: palette,
              onEdit: onEdit,
            ),
            const SizedBox(height: 12),
            if (editing) ..._buildForm(context) else ..._buildSummary(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildForm(BuildContext context) {
    return [
      _FieldLabel('App ID', palette: palette),
      const SizedBox(height: 6),
      tvExcludeEditable(
        tvMode: tvMode,
        child: TextField(
          key: const ValueKey('agoraAppIdField'),
          controller: appIdController,
          style: TextStyle(color: palette.ink, fontSize: 13),
          cursorColor: palette.ink,
          textInputAction: TextInputAction.next,
          decoration: _decoration(
            hint: '声网 App ID',
            icon: Icons.vpn_key,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _FieldLabel('App Certificate', palette: palette),
      const SizedBox(height: 6),
      tvExcludeEditable(
        tvMode: tvMode,
        child: TextField(
          key: const ValueKey('agoraCertField'),
          controller: certController,
          style: TextStyle(color: palette.ink, fontSize: 13),
          cursorColor: palette.ink,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSave(),
          decoration: _decoration(
            hint: '声网 App Certificate',
            icon: Icons.lock_outline,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '开房 / 加入房间需要声网 RTM 凭证；保存后仅写入本机。',
        style: TextStyle(
          color: palette.mutedInk,
          fontSize: 10.5,
          height: 1.35,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 40,
        child: Row(
          children: [
            if (onCancel != null) ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('agoraCancelEdit'),
                  onPressed: onCancel,
                  style: _outlineStyle(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: onCancel == null ? 1 : 2,
              child: FilledButton.icon(
                key: const ValueKey('agoraSaveButton'),
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('保存'),
                style: FilledButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.paperLight,
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildSummary() {
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: palette.paperLight.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: palette.paperEdge.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App ID',
              style: TextStyle(
                color: palette.mutedInk,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              appId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '证书已一并保存',
              style: TextStyle(color: palette.mutedInk, fontSize: 10.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              '如需更换凭证，点上方「编辑」。',
              style: TextStyle(color: palette.mutedInk, fontSize: 10.5),
            ),
          ),
          TextButton(
            key: const ValueKey('agoraClearButton'),
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8E3F37),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    ];
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: palette.paperEdge.withValues(alpha: 0.8)),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: palette.mutedInk.withValues(alpha: 0.65),
        fontSize: 12,
      ),
      prefixIcon: Icon(icon, size: 17, color: palette.mutedInk),
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      isDense: true,
      filled: true,
      fillColor: Color.lerp(palette.paperLight, Colors.white, 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: palette.foil, width: 1.2),
      ),
    );
  }

  ButtonStyle _outlineStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: palette.mutedInk,
      side: BorderSide(color: palette.paperEdge.withValues(alpha: 0.8)),
      textStyle: const TextStyle(fontSize: 12),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.palette});

  final String text;
  final AgoraBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: palette.ink,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.configured,
    required this.editing,
    required this.appId,
    required this.palette,
    required this.onEdit,
  });

  final bool configured;
  final bool editing;
  final String appId;
  final AgoraBookPalette palette;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color =
        configured ? const Color(0xFF2E6B45) : const Color(0xFF8A5A12);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.check_circle_outline : Icons.info_outline,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? '已配置' : '未配置',
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  configured
                      ? 'App ID: ${_mask(appId)}'
                      : '填写 App ID 后即可开房与加入房间',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: configured ? palette.ink : palette.mutedInk,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (configured && !editing)
            TextButton(
              key: const ValueKey('agoraEditButton'),
              onPressed: onEdit,
              style: TextButton.styleFrom(
                foregroundColor: palette.mutedInk,
                textStyle: const TextStyle(fontSize: 11.5),
                minimumSize: const Size(44, 30),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('编辑'),
            ),
        ],
      ),
    );
  }

  String _mask(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 8)}...';
  }
}

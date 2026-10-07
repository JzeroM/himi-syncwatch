import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 设置页公共件：说明文案、选项下拉行、TV 描边包装、分类子页脚手架。
/// 各分类子页（外观/播放器/通用/实验性）共用，避免重复实现。

String decodeModeDescription(String mode) {
  switch (mode) {
    case 'auto':
      return '智能选择：自动匹配最佳解码方式';
    case 'hw':
      return '硬解：强制纯硬解码，失败不回退';
    case 'sw':
      return '软解：纯软解码，CPU 占用高';
    default:
      return '建议默认使用智能选择';
  }
}

String audioRendererDescription(String renderer) {
  switch (renderer) {
    case 'auto':
      return '使用系统默认音频后端（默认）';
    case 'AAudio':
      return 'AAudio：现代低延迟后端';
    case 'OpenSL':
      return 'OpenSL：时钟精度更高，改善 TrueHD 等音频流畅性';
    case 'AudioTrack':
      return 'AudioTrack：兼容性最好的传统后端';
    default:
      return '建议默认使用自动';
  }
}

String videoOutputDescription(String output) {
  switch (output) {
    case 'tunnel':
      return '解码器直写纹理，绕过 mdk GL 渲染（画面异常时尝试）';
    case 'surfaceView':
      return '独立显示层，绕过 Flutter 合成，TV 全分辨率输出（黑屏时尝试）';
    case 'texture':
      return 'Flutter 纹理通道（默认）';
    default:
      return '建议默认使用纹理通道';
  }
}

/// 设置项下拉选择（解码方式/音频后端/视频输出共用）。
///
/// - 非 TV 模式：[DropdownButton]（触摸交互）
/// - TV 模式：整行 [TvFocusable]（D-pad 聚焦 + OK 打开），选择层为
///   底部弹窗 RadioListTile。
Widget settingOptionTile({
  required BuildContext context,
  required bool tvMode,
  required String title,
  required String subtitle,
  required Map<String, String> labels,
  required String value,
  required ValueChanged<String> onSelected,
}) {
  if (!tvMode) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        onChanged: (v) {
          if (v != null) onSelected(v);
        },
        items: labels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
      ),
    );
  }
  return TvFocusable(
    scale: 1.0,
    onTap: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            RadioGroup<String>(
              groupValue: value,
              onChanged: (v) {
                if (v != null) onSelected(v);
                Navigator.of(ctx).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in labels.entries)
                    RadioListTile<String>(
                      key: Key('settingOption_${e.key}'),
                      title: Text(e.value),
                      value: e.key,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
    child: ExcludeFocus(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(labels[value] ?? value),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
          ],
        ),
      ),
    ),
  );
}

/// TV 模式把裸 Material 行统一为 TvFocusable 描边焦点。
Widget settingsTvWrapRow({
  required bool tvMode,
  required VoidCallback onTap,
  required Widget child,
  double scale = 1.0,
}) {
  if (!tvMode) return child;
  return TvFocusable(
    onTap: onTap,
    scale: scale,
    child: ExcludeFocus(child: child),
  );
}

/// 分类子页脚手架：与设置主页同款玻璃风格（透明 AppBar + 玻璃背板 + 列表）。
class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage({
    super.key,
    required this.title,
    required this.children,
    required this.pageKey,
  });

  final String title;
  final List<Widget> children;
  final Key pageKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: pageKey,
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
      ),
      body: ListView(
        key: const ValueKey('settingsSubPageList'),
        padding: EdgeInsets.only(
          top: GlassConfig.topInsetOf(context),
          bottom: GlassConfig.bottomReserveOf(context),
        ),
        children: children,
      ),
    );
  }
}

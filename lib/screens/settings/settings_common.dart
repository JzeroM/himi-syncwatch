import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_option_dialog.dart';

/// 设置页公共件：说明文案、选项下拉行、TV 描边包装、分类子页脚手架。
/// 各分类子页（外观/播放器/通用/实验性）共用，避免重复实现。

/// 设置子页统一背景：与壳层同源的主题色三段渐变（不透明）。
/// 过渡期间背景恒定，避免「两页堆叠 / 先默认色再主题色」。
class SettingsPageBackground extends ConsumerWidget {
  const SettingsPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: PosterPalette.pageGradient(accent, base),
      ),
      child: child,
    );
  }
}

/// 设置子页统一推入过渡：淡入淡出（两端一致，替代 iOS 滑动/Android 缩放）。
Route<T> settingsFadeRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, __) => builder(context),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

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
      return '使用系统默认音频后端';
    case 'AAudio':
      return 'AAudio：现代低延迟后端';
    case 'OpenSL':
      return 'OpenSL：时钟精度更高，改善 TrueHD 等音频流畅性';
    case 'AudioTrack':
      return 'AudioTrack：兼容性最好的传统后端（TV 默认）';
    default:
      return '建议默认使用自动';
  }
}

String videoOutputDescription(String output) {
  switch (output) {
    case 'tunnel':
      return '解码器直写纹理，绕过 mdk GL 渲染（画面异常时尝试）';
    case 'surfaceViewDirect':
      return '独立显示层 + 解码器直写，最省性能（4K HDR 卡顿时首选）；'
          'HDR 颜色交系统处理，不支持 mdk 截图';
    case 'surfaceView':
      return '独立显示层，绕过 Flutter 合成，TV 全分辨率输出（TV 默认）';
    case 'texture':
      return 'Flutter 纹理通道';
    default:
      return '建议默认使用纹理通道';
  }
}

/// 设置项下拉选择（解码方式/音频后端/视频输出共用）。
///
/// - 非 TV 模式：[DropdownButton]（触摸交互）
/// - TV 模式：整行 [TvFocusable]（D-pad 聚焦 + OK 打开），选择层为
///   居中弹层 [showTvOptionDialog]（TV 方向键上下切换 + OK 选择）。
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
    onTap: () => showTvOptionDialog<String>(
      context: context,
      title: title,
      currentValue: value,
      onSelected: onSelected,
      options: [
        for (final e in labels.entries)
          TvOptionEntry(
            value: e.key,
            label: e.value,
            key: Key('settingOption_${e.key}'),
          ),
      ],
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
    return SettingsPageBackground(
      child: Scaffold(
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
      ),
    );
  }
}

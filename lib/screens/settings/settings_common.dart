import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/pressable_scale.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';
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

/// 设置项滑杆行（缓冲/缓存等）。
///
/// TV 模式下整行可聚焦，左右键按 [step] 调值、上下键放行给焦点遍历；
/// 非 TV 模式保持普通 [Slider] 触摸拖动。
Widget settingsTvSliderRow({
  required BuildContext context,
  required bool tvMode,
  required String title,
  required String subtitle,
  required String sliderKey,
  required double value,
  required double min,
  required double max,
  required int? divisions,
  required String label,
  required double step,
  required ValueChanged<double> onChanged,
}) {
  final tile = ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: SizedBox(
      width: 200,
      child: Slider(
        key: ValueKey(sliderKey),
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    ),
  );
  if (!tvMode) return tile;
  return TvFocusable(
    scale: 1.0,
    onTap: () {},
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key != LogicalKeyboardKey.arrowLeft &&
          key != LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.ignored;
      }
      final delta = key == LogicalKeyboardKey.arrowLeft ? -step : step;
      final next = (value + delta).clamp(min, max).toDouble();
      if (next != value) onChanged(next);
      return KeyEventResult.handled;
    },
    child: ExcludeFocus(child: tile),
  );
}

/// TV 模式把裸 Material 行统一为 TvFocusable 描边焦点。
Widget settingsTvWrapRow({
  required bool tvMode,
  required VoidCallback onTap,
  required Widget child,
  double scale = 1.0,
  bool autofocus = false,
  FocusNode? focusNode,
}) {
  if (!tvMode) return child;
  return TvFocusable(
    onTap: onTap,
    scale: scale,
    autofocus: autofocus,
    focusNode: focusNode,
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
          leading: const TvBackButton(),
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

/// 690：设置**分组玻璃卡片**——一组设置项包在一张玻璃卡片里。
///
/// ## 为什么需要
///
/// 旧实现是「`ListTile` + `Divider`」平铺长列表（外观页 669 行、缓存页
/// 546 行），整页零玻璃、滚动到底很长、找不到「我在哪一组」。
///
/// 现在按语义切成 3~5 组，每组一张玻璃卡片：
/// - 组标题：12px 大写字母间距，半透明白
/// - 卡片：`GlassContainer` 圆角 16
/// - 组内行之间：极淡细线（比 `Divider` 淡）
/// - 组间间距 20
///
/// ## TV 焦点
///
/// 组标题 [ExcludeFocus]（不可聚焦），卡片本体也不聚焦——只有组内的行
/// 参与焦点遍历。[FocusTraversalGroup] 保证上下键在组内移动、到边界时
/// 跳到相邻组。
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// 组标题（为空则不显示）。
  final String? title;

  /// 组内行（通常是 `ListTile` / `SwitchListTile` / 自定义行）。
  final List<Widget> children;

  /// 组标题的左右内边距。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            ExcludeFocus(
              child: Padding(
                padding: padding.copyWith(bottom: 8),
                child: Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Colors.white60,
                  ),
                ),
              ),
            ),
          FocusTraversalGroup(
            child: GlassContainer(
              borderRadius: BorderRadius.circular(16),
              showShadow: false,
              padding: const EdgeInsets.symmetric(vertical: 2),
              // 690：`ListTile` 的墨水效果画在最近的 `Material` 祖先上，
              // 而 `GlassContainer` 用 `DecoratedBox` 提供背景——不套一层
              // 透明 `Material` 时 Flutter 会断言「墨水效果不可见」。
              child: Material(
                color: Colors.transparent,
                child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    // 组内细线（最后一项之后不加）
                    if (i < children.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 16, right: 16),
                        child: Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Color(0x0FFFFFFF),
                        ),
                      ),
                  ],
                ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 690：设置主页的**分类卡片**（玻璃 + 图标 + 标题 + 副标题）。
///
/// 用于「外观 / 播放器 / 通用 / 数据 / 实验性 / 关于」六个入口。
class SettingsCategoryCard extends StatelessWidget {
  const SettingsCategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.tvMode,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool tvMode;

  /// 690：TV 模式下是否自动落焦（首张卡片用）。
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final card = GlassContainer(
      borderRadius: BorderRadius.circular(18),
      showShadow: false,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 图标：圆形主色渐变底（与侧边栏品牌区同款语言）
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.35),
                  accent.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.40),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
        ],
      ),
    );

    // TV：整卡可聚焦（焦点环 + 轻微放大）；非 TV：按压缩放反馈。
    if (tvMode) {
      return TvFocusable(
        onTap: onTap,
        scale: 1.03,
        autofocus: autofocus,
        child: card,
      );
    }
    return PressableScale(onTap: onTap, child: card);
  }
}

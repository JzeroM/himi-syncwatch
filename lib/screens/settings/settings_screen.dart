import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

String _decodeModeDescription(String mode) {
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

String _audioRendererDescription(String renderer) {
  switch (renderer) {
    case 'auto':
      return '使用系统默认音频后端（默认）';
    case 'AAudio':
      return 'AAudio：现代低延迟后端';
    case 'OpenSL':
      return 'OpenSL：时钟精度更高，改善 TrueHD 等音频流畅度';
    case 'AudioTrack':
      return 'AudioTrack：兼容性最好的传统后端';
    default:
      return '建议默认使用自动';
  }
}

String _videoOutputDescription(String output) {
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

/// 设置项下拉选择（解码方式/音频后端共用）。
///
/// - 非 TV 模式：[DropdownButton]（触摸交互，与旧版一致）
/// - TV 模式：整行 [TvFocusable]（D-pad 聚焦 + OK 打开），选择层为
///   底部弹窗 RadioListTile——与轨道选择器同交互，TV 遥控经
///   MaterialApp.builder 层的 TvRemoteShortcuts 可正常操作。
Widget _settingOptionTile({
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
            for (final e in labels.entries)
              RadioListTile<String>(
                key: Key('settingOption_${e.key}'),
                title: Text(e.value),
                value: e.key,
                groupValue: value,
                onChanged: (v) {
                  if (v != null) onSelected(v);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
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
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      key: const ValueKey('settingsPage'),
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: GlassConfig.topInsetOf(context),
          bottom: GlassConfig.bottomReserveOf(context),
        ),
        children: [
          const _ThemeColorSection(),
          const Divider(height: 1),
          _settingOptionTile(
            context: context,
            tvMode: settings.tvMode,
            title: '解码方式',
            subtitle: _decodeModeDescription(settings.decodeMode),
            labels: AppSettings.decodeModeLabels,
            value: settings.decodeMode,
            onSelected: (v) =>
                ref.read(settingsProvider.notifier).update(decodeMode: v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('立体声降混'),
            subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
            value: settings.stereoDownmix,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(stereoDownmix: v),
          ),
          // AAudio/OpenSL/AudioTrack 为 Android 专属后端，其余平台固定
          // 自动（iOS 曾因默认 AudioTrack 无效导致无声），不提供设置项
          if (defaultTargetPlatform == TargetPlatform.android) ...[
            const Divider(height: 1),
            _settingOptionTile(
              context: context,
              tvMode: settings.tvMode,
              title: '音频后端',
              subtitle: _audioRendererDescription(settings.audioRenderer),
              labels: AppSettings.audioRendererLabels,
              value: settings.audioRenderer,
              onSelected: (v) =>
                  ref.read(settingsProvider.notifier).update(audioRenderer: v),
            ),
            const Divider(height: 1),
            // 视频输出通道（纹理/tunnel/SurfaceView）均为 Android 能力，
            // 其余平台固定纹理通道，不提供设置项
            _settingOptionTile(
              context: context,
              tvMode: settings.tvMode,
              title: '视频输出',
              subtitle: _videoOutputDescription(settings.videoOutput),
              labels: AppSettings.videoOutputLabels,
              value: settings.videoOutput,
              onSelected: (v) =>
                  ref.read(settingsProvider.notifier).update(videoOutput: v),
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('播放调试面板'),
            subtitle: const Text('实时显示播放诊断信息，可拖拽移动'),
            value: settings.showSyncDebug,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(showSyncDebug: v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('液态玻璃'),
            subtitle: const Text('毛玻璃模糊与高光效果，低端设备可关闭以提升流畅度'),
            value: settings.glassUi,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(glassUi: v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('TV 模式'),
            subtitle: const Text('适配遥控器：方向键导航，OK 键选择，中键暂停/播放'),
            value: settings.tvMode,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(tvMode: v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('深度诊断'),
            subtitle: const Text(
              '抓取 mdk 内部日志获取实测帧率。仅诊断卡顿时开启，可能增加少量开销',
            ),
            value: settings.deepDiagnostics,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(deepDiagnostics: v),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('导出运行日志'),
            subtitle: const Text('保存最近 1000 条日志并分享'),
            onTap: () => LogService().shareLogs(),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// 主题色分节：预设色板 +「默认」+ 色相/饱和/明度滑块 + 三段渐变预览。
///
/// 选中的颜色写入 [AppSettings.themeColor]，作用于首页与壳层背景。
class _ThemeColorSection extends ConsumerStatefulWidget {
  const _ThemeColorSection();

  @override
  ConsumerState<_ThemeColorSection> createState() => _ThemeColorSectionState();
}

class _ThemeColorSectionState extends ConsumerState<_ThemeColorSection> {
  static const List<int> _presets = [
    0xFF6366F1, // 靛紫
    0xFF8B5CF6, // 紫
    0xFFEC4899, // 粉
    0xFFF87171, // 红
    0xFFFB923C, // 橙
    0xFFFACC15, // 黄
    0xFF4ADE80, // 绿
    0xFF2DD4BF, // 青绿
    0xFF22D3EE, // 青
    0xFF38BDF8, // 天蓝
    0xFF60A5FA, // 蓝
    0xFF94A3B8, // 灰蓝
  ];

  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    final stored = ref.read(settingsProvider).themeColor;
    _hsv = HSVColor.fromColor(
      stored == null ? const Color(0xFF6366F1) : Color(stored),
    );
  }

  void _commit(Color color) {
    // Color.value 在 3.27 已废弃，手工打包 ARGB
    final a = (color.a * 255).round() & 0xff;
    final r = (color.r * 255).round() & 0xff;
    final g = (color.g * 255).round() & 0xff;
    final b = (color.b * 255).round() & 0xff;
    ref
        .read(settingsProvider.notifier)
        .update(themeColor: (a << 24) | (r << 16) | (g << 8) | b);
  }

  void _setHSV({double? hue, double? saturation, double? value}) {
    setState(() {
      _hsv = HSVColor.fromAHSV(
        1,
        hue ?? _hsv.hue,
        saturation ?? _hsv.saturation,
        value ?? _hsv.value,
      );
    });
    _commit(_hsv.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(settingsProvider.select((s) => s.themeColor));
    final base = Theme.of(context).scaffoldBackgroundColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
          child: Text(
            '主题色',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '自定义首页与底部导航的背景渐变，「默认」跟随应用底色',
            style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _block(
                key: const ValueKey('themeColorDefault'),
                color: null,
                selected: current == null,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .update(themeColor: null),
                child: const Text(
                  '默认',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              for (var i = 0; i < _presets.length; i++)
                _block(
                  key: ValueKey('themeColorBlock_$i'),
                  color: Color(_presets[i]),
                  selected: current == _presets[i],
                  onTap: () {
                    setState(
                        () => _hsv = HSVColor.fromColor(Color(_presets[i])));
                    _commit(Color(_presets[i]));
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: DecoratedBox(
                key: const ValueKey('themeColorPreview'),
                decoration: BoxDecoration(
                  gradient: PosterPalette.pageGradient(
                    current == null
                        ? null
                        : PosterPalette.darkenForPage(Color(current)),
                    base,
                  ),
                ),
                child: Center(
                  child: Text(
                    current == null ? '默认底色' : '预览',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _hsvSlider(
          label: '色相',
          sliderKey: const ValueKey('themeHueSlider'),
          min: 0,
          max: 360,
          value: _hsv.hue,
          onChanged: (v) => _setHSV(hue: v),
        ),
        _hsvSlider(
          label: '饱和',
          sliderKey: const ValueKey('themeSatSlider'),
          min: 0,
          max: 100,
          value: _hsv.saturation * 100,
          onChanged: (v) => _setHSV(saturation: v / 100),
        ),
        _hsvSlider(
          label: '明度',
          sliderKey: const ValueKey('themeValSlider'),
          min: 0,
          max: 100,
          value: _hsv.value * 100,
          onChanged: (v) => _setHSV(value: v / 100),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _block({
    required Key key,
    required Color? color,
    required bool selected,
    required VoidCallback onTap,
    Widget? child,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color ?? Colors.white12,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: child ??
            (selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null),
      ),
    );
  }

  Widget _hsvSlider({
    required String label,
    required Key sliderKey,
    required double min,
    required double max,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Slider(
              key: sliderKey,
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

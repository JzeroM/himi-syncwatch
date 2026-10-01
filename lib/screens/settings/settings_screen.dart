import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

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
      return '使用系统默认音频后端';
    case 'AAudio':
      return 'AAudio：现代低延迟后端';
    case 'OpenSL':
      return 'OpenSL：时钟精度更高，改善 TrueHD 等音频流畅度';
    case 'AudioTrack':
      return 'AudioTrack：兼容性最好的传统后端（默认）';
    default:
      return '建议默认使用自动';
  }
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
          ListTile(
            title: const Text('解码方式'),
            subtitle: Text(_decodeModeDescription(settings.decodeMode)),
            trailing: DropdownButton<String>(
              value: settings.decodeMode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).update(decodeMode: value);
                }
              },
              items: AppSettings.decodeModeLabels.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('立体声降混'),
            subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
            value: settings.stereoDownmix,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(stereoDownmix: v),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('音频后端'),
            subtitle: Text(_audioRendererDescription(settings.audioRenderer)),
            trailing: DropdownButton<String>(
              value: settings.audioRenderer,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).update(audioRenderer: value);
                }
              },
              items: AppSettings.audioRendererLabels.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
            ),
          ),
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
  ConsumerState<_ThemeColorSection> createState() =>
      _ThemeColorSectionState();
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
                onTap: () =>
                    ref.read(settingsProvider.notifier).update(themeColor: null),
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
                    setState(() => _hsv = HSVColor.fromColor(Color(_presets[i])));
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

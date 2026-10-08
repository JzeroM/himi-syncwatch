import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/app_icon_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';

/// 外观设置子页：主题色 / 分类页每行海报数 / 液态玻璃（开关 + 参数）。
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SettingsSubPage(
      pageKey: const ValueKey('appearanceSettingsPage'),
      title: '外观',
      children: [
        const _AppIconSection(),
        const Divider(height: 1),
        const _ThemeColorSection(),
        const Divider(height: 1),
        settingsTvWrapRow(
          tvMode: settings.tvMode,
          onTap: () => ref
              .read(settingsProvider.notifier)
              .update(glassUi: !settings.glassUi),
          child: SwitchListTile(
            title: const Text('液态玻璃'),
            subtitle: const Text('毛玻璃模糊与高光效果，低端设备可关闭以提升流畅度'),
            value: settings.glassUi,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).update(glassUi: v),
          ),
        ),
        const _GlassTuningSection(),
        const Divider(height: 1),
        const _CategoryColumnsSection(),
        const Divider(height: 1),
      ],
    );
  }
}

/// 分类页每行海报数分节：滑块 0 = 自动，1~14 = 指定列数。
class _CategoryColumnsSection extends ConsumerWidget {
  const _CategoryColumnsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns =
        ref.watch(settingsProvider.select((s) => s.categoryColumns));
    final sliderValue = (columns ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
          child: Text(
            '分类页每行海报数',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '0 = 自动跟随屏幕（TV 默认每行 8 个）；指定后屏幕放不下时'
            '自动压缩为可显示的最大列数',
            style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  columns == null ? '自动' : '每行 $columns 个',
                  key: const ValueKey('categoryColumnsValue'),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('categoryColumnsSlider'),
                  label: columns == null ? '自动' : '$columns',
                  min: 0,
                  max: 14,
                  divisions: 14,
                  value: sliderValue,
                  onChanged: (v) {
                    final n = v.round();
                    ref
                        .read(settingsProvider.notifier)
                        .update(categoryColumns: n == 0 ? null : n);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 液态玻璃参数滑杆分组：参数实时写入设置 → glassTuningProvider →
/// wrap(theme:) 重建，全 App 玻璃即时生效。
class _GlassTuningSection extends ConsumerWidget {
  const _GlassTuningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuning = ref.watch(glassTuningProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '玻璃参数',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                key: const ValueKey('glassResetDefaults'),
                onPressed: tuning.isDefault
                    ? null
                    : () => ref.read(settingsProvider.notifier).update(
                          glassBlur: null,
                          glassThickness: null,
                          glassEdgeZone: null,
                          glassSaturation: null,
                          glassChromatic: null,
                          glassLightIntensity: null,
                          glassRefractiveIndex: null,
                        ),
                child: const Text('恢复默认', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const Text(
            '实时调节磨砂与折射效果，拖动即生效',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 4),
          for (final spec in glassParamSpecs)
            if ((spec.key != 'glassEdgeZone' ||
                    glassEdgeZoneVisible(tvMode: tvMode)) &&
                (spec.key != 'glassRefractiveIndex' ||
                    glassRefractiveIndexVisible(tvMode: tvMode)))
              _glassSliderRow(ref, spec, spec.read(tuning)),
        ],
      ),
    );
  }

  Widget _glassSliderRow(
    WidgetRef ref,
    GlassParamSpec spec,
    double value,
  ) {
    return Row(
      key: ValueKey('glassParam_${spec.key}'),
      children: [
        SizedBox(
          width: 72,
          child: Text(
            spec.label,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        Expanded(
          child: Slider(
            key: ValueKey('${spec.key}Slider'),
            label: value.toStringAsFixed(spec.decimals),
            min: spec.min,
            max: spec.max,
            divisions: spec.divisions,
            value: value.clamp(spec.min, spec.max),
            onChanged: (v) => ref.read(settingsProvider.notifier).update(
                  glassBlur:
                      spec.key == 'glassBlur' ? v : AppSettings.unsetValue,
                  glassThickness:
                      spec.key == 'glassThickness' ? v : AppSettings.unsetValue,
                  glassEdgeZone:
                      spec.key == 'glassEdgeZone' ? v : AppSettings.unsetValue,
                  glassSaturation: spec.key == 'glassSaturation'
                      ? v
                      : AppSettings.unsetValue,
                  glassChromatic:
                      spec.key == 'glassChromatic' ? v : AppSettings.unsetValue,
                  glassLightIntensity: spec.key == 'glassLightIntensity'
                      ? v
                      : AppSettings.unsetValue,
                  glassRefractiveIndex: spec.key == 'glassRefractiveIndex'
                      ? v
                      : AppSettings.unsetValue,
                ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(spec.decimals),
            key: ValueKey('glassValue_${spec.key}'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

/// 主题色分节：预设色板 +「默认」+ 色相/饱和/明度滑块 + 三段渐变预览。
class _ThemeColorSection extends ConsumerStatefulWidget {
  const _ThemeColorSection();

  @override
  ConsumerState<_ThemeColorSection> createState() => _ThemeColorSectionState();
}

class _ThemeColorSectionState extends ConsumerState<_ThemeColorSection> {
  static const List<int> _presets = [
    0xFF6366F1,
    0xFF8B5CF6,
    0xFFEC4899,
    0xFFF87171,
    0xFFFB923C,
    0xFFFACC15,
    0xFF4ADE80,
    0xFF2DD4BF,
    0xFF22D3EE,
    0xFF38BDF8,
    0xFF60A5FA,
    0xFF94A3B8,
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

/// 应用图标切换分组：默认 + 备用图标（仅 Android 手机 / iOS 显示）。
class _AppIconSection extends ConsumerWidget {
  const _AppIconSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    // 仅手机端（Android/iOS）非 TV 显示；Windows/桌面/TV 无此功能。
    if (tvMode || !AppIconService.isSupported) {
      return const SizedBox.shrink();
    }
    final current = ref.watch(settingsProvider.select((s) => s.appIcon));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
          child: Text(
            '应用图标',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '选择桌面图标外观（Android 需划掉应用后桌面才刷新；iOS 会弹系统提示）',
            style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              for (final option in AppIconService.options)
                _AppIconTile(
                  option: option,
                  selected: current == option.id,
                  onTap: () => _apply(context, ref, option.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    String? id,
  ) async {
    if (ref.read(settingsProvider).appIcon == id) return;
    try {
      await AppIconService.apply(id);
      await ref.read(settingsProvider.notifier).update(appIcon: id);
    } catch (_) {
      if (context.mounted) showAppToast(context, '切换图标失败');
    }
  }
}

class _AppIconTile extends StatelessWidget {
  const _AppIconTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppIconOption option;
  final bool selected;
  final VoidCallback onTap;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      key: ValueKey('appIcon_${option.id ?? 'default'}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? accent : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.asset(
                      option.asset,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? accent : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

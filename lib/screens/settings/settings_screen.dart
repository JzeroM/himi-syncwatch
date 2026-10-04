import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_tuning.dart';
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
    // 满宽行：关闭聚焦微放大，避免超宽内容按中心放大后两端文字出屏裁切
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
    // ExcludeFocus：屏蔽 ListTile 内嵌 InkWell 自带焦点节点。同 rect 双
    // 候选下（FocusNode.descendants 为后序遍历，内层反而排在外层 wrapper
    // 之前），方向导航会选中内层而非描边 wrapper，焦点随即异常跳回原行、
    // 表现为"方向键走不动"；触摸与内层手势不受影响（与 _tvWrapRow 一致）。
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

/// TV 模式把裸 Material 行统一为 TvFocusable 描边焦点（全页单一焦点样式）。
/// - [ExcludeFocus] 屏蔽行内 InkWell/Switch 自带焦点节点，否则外层描边与
///   内层蓝色 focusColor 填充同屏双显（"两个焦点框"）；
/// - 触摸仍由行内控件响应（手势竞技内层优先，行为与包装前一致）；
/// - OK 键走外层 [TvFocusable.onTap]（调用方手动 toggle/触发）；
/// - 满宽行 [scale] 默认 1.0，关闭聚焦微放大防止两端文字出屏裁切。
Widget _tvWrapRow({
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
          // 分类页列数紧跟主题色（外观设置相邻）；后部行整体下移，
          // 相关视口/焦点测试已配套修复
          const _CategoryColumnsSection(),
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
          _tvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .update(stereoDownmix: !settings.stereoDownmix),
            child: SwitchListTile(
              title: const Text('立体声降混'),
              subtitle: const Text('将多声道音频降混为立体声（解决部分声道无声问题）'),
              value: settings.stereoDownmix,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).update(stereoDownmix: v),
            ),
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
            const Divider(height: 1),
            // 渲染兼容模式：mdk 全局 GL 选项（rockchip 硬解渲染 /
            // SurfaceTexture 上下文），仅启动时读取注入 → 重启生效
            _tvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .update(renderCompatMode: !settings.renderCompatMode),
              child: SwitchListTile(
                title: const Text('渲染兼容模式（实验）'),
                subtitle: const Text(
                  '启用 rockchip GL 渲染变体（yuv 采样 / SurfaceTexture 上下文）。'
                  '视频全黑时尝试，修改后需重启应用生效',
                ),
                value: settings.renderCompatMode,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update(renderCompatMode: v),
              ),
            ),
          ],
          const Divider(height: 1),
          _tvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .update(showSyncDebug: !settings.showSyncDebug),
            child: SwitchListTile(
              title: const Text('播放调试面板'),
              subtitle: const Text('实时显示播放诊断信息，可拖拽移动'),
              value: settings.showSyncDebug,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).update(showSyncDebug: v),
            ),
          ),
          const Divider(height: 1),
          _tvWrapRow(
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
          // 玻璃参数滑杆紧跟开关（关闭玻璃时滑杆仍在，便于重开前调好）
          const _GlassTuningSection(),
          const Divider(height: 1),
          _tvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .update(tvMode: !settings.tvMode),
            child: SwitchListTile(
              title: const Text('TV 模式'),
              subtitle: const Text('适配遥控器：方向键导航，OK 键选择，中键暂停/播放'),
              value: settings.tvMode,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).update(tvMode: v),
            ),
          ),
          const Divider(height: 1),
          _tvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => ref
                .read(settingsProvider.notifier)
                .update(deepDiagnostics: !settings.deepDiagnostics),
            child: SwitchListTile(
              title: const Text('深度诊断'),
              subtitle: const Text(
                '抓取 mdk 内部日志获取实测帧率。仅诊断卡顿时开启，可能增加少量开销',
              ),
              value: settings.deepDiagnostics,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update(deepDiagnostics: v),
            ),
          ),
          const Divider(height: 1),
          _tvWrapRow(
            tvMode: settings.tvMode,
            onTap: () => LogService().shareLogs(),
            child: ListTile(
              leading: const Icon(Icons.bug_report),
              title: const Text('导出运行日志'),
              subtitle: const Text('保存最近 1000 条日志并分享'),
              onTap: () => LogService().shareLogs(),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// 分类页每行海报数分节：滑块 0 = 自动，1~14 = 指定列数。
///
/// 写入 [AppSettings.categoryColumns]（null = 自动跟随屏幕）；手动指定
/// 后屏幕放不下时由 `CategoryScreen.gridColumns` 按最小列宽自动压回。
/// 液态玻璃参数滑杆分组（v1.1.84）：5 个参数实时写入设置 →
/// glassTuningProvider → wrap(theme:) 重建，全 App 玻璃即时生效。
class _GlassTuningSection extends ConsumerWidget {
  const _GlassTuningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tuning = ref.watch(glassTuningProvider);

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
                          glassSaturation: null,
                          glassChromatic: null,
                          glassLightIntensity: null,
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
                  glassBlur: spec.key == 'glassBlur' ? v : null,
                  glassThickness: spec.key == 'glassThickness' ? v : null,
                  glassSaturation: spec.key == 'glassSaturation' ? v : null,
                  glassChromatic: spec.key == 'glassChromatic' ? v : null,
                  glassLightIntensity:
                      spec.key == 'glassLightIntensity' ? v : null,
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

class _CategoryColumnsSection extends ConsumerWidget {
  const _CategoryColumnsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns =
        ref.watch(settingsProvider.select((s) => s.categoryColumns));
    // 滑块用 0 表示「自动」，1~14 直接为列数
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

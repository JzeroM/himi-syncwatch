import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 单个可调玻璃参数的规格：滑杆范围 + 默认值的单一事实源。
class GlassParamSpec {
  const GlassParamSpec({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.divisions = 20,
    this.decimals = 1,
  });

  /// 与 [AppSettings] 字段名对应的 key（'glassBlur' 等）。
  final String key;
  final String label;
  final double min;
  final double max;

  /// 包默认值（滑杆回显与「恢复默认」的目标值）。
  final double defaultValue;
  final int divisions;

  /// 值回显小数位（色散需要 3 位）。
  final int decimals;

  /// 读取 [GlassTuning] 中该参数的当前值。
  double read(GlassTuning tuning) => switch (key) {
        'glassBlur' => tuning.blur ?? defaultValue,
        'glassThickness' => tuning.thickness ?? defaultValue,
        'glassSaturation' => tuning.saturation ?? defaultValue,
        'glassChromatic' => tuning.chromatic ?? defaultValue,
        'glassLightIntensity' => tuning.lightIntensity ?? defaultValue,
        _ => defaultValue,
      };

  /// 把值写回 [AppSettings.copyWith]（保留未传字段）。
  AppSettings apply(AppSettings s, double value) => switch (key) {
        'glassBlur' => s.copyWith(glassBlur: value),
        'glassThickness' => s.copyWith(glassThickness: value),
        'glassSaturation' => s.copyWith(glassSaturation: value),
        'glassChromatic' => s.copyWith(glassChromatic: value),
        'glassLightIntensity' => s.copyWith(glassLightIntensity: value),
        _ => s,
      };
}

/// 液态玻璃可调参数规格（设置页滑杆的展示顺序即列表顺序）。
const List<GlassParamSpec> glassParamSpecs = [
  GlassParamSpec(
    key: 'glassBlur',
    label: '磨砂模糊',
    min: 0,
    max: 20,
    defaultValue: 5,
    divisions: 40,
  ),
  GlassParamSpec(
    key: 'glassThickness',
    label: '玻璃厚度',
    min: 0,
    max: 60,
    defaultValue: 20,
    divisions: 60,
  ),
  GlassParamSpec(
    key: 'glassSaturation',
    label: '饱和增强',
    min: 1.0,
    max: 2.5,
    defaultValue: 1.5,
    divisions: 30,
  ),
  GlassParamSpec(
    key: 'glassChromatic',
    label: '色散',
    min: 0,
    max: 0.1,
    defaultValue: 0.01,
    divisions: 20,
    decimals: 3,
  ),
  GlassParamSpec(
    key: 'glassLightIntensity',
    label: '高光强度',
    min: 0,
    max: 1,
    defaultValue: 0.5,
    divisions: 20,
  ),
];

/// 玻璃参数快照：settings 的 5 个可调字段 → 包主题的映射边界。
class GlassTuning {
  const GlassTuning({
    this.blur,
    this.thickness,
    this.saturation,
    this.chromatic,
    this.lightIntensity,
  });

  final double? blur;
  final double? thickness;
  final double? saturation;
  final double? chromatic;
  final double? lightIntensity;

  factory GlassTuning.fromSettings(AppSettings s) => GlassTuning(
        blur: s.glassBlur,
        thickness: s.glassThickness,
        saturation: s.glassSaturation,
        chromatic: s.glassChromatic,
        lightIntensity: s.glassLightIntensity,
      );

  /// 是否全部为包默认（决定「恢复默认」按钮的可用性）。
  bool get isDefault =>
      blur == null &&
      thickness == null &&
      saturation == null &&
      chromatic == null &&
      lightIntensity == null;

  /// 映射为包主题（null 字段 = 沿用包默认，GlassThemeSettings.copy 忽略 null）。
  GlassThemeData toThemeData() => GlassThemeData.simple(
        blur: blur,
        thickness: thickness,
        saturation: saturation,
        chromaticAberration: chromatic,
        lightIntensity: lightIntensity,
      );
}

/// 监听设置中的玻璃参数（仅 5 个相关字段，无关设置变化不触发重建），
/// 驱动 `LiquidGlassWidgets.wrap(theme:)` 实时生效。
final glassTuningProvider = Provider<GlassTuning>((ref) {
  final s = ref.watch(
    settingsProvider.select(
      (s) => (
        blur: s.glassBlur,
        thickness: s.glassThickness,
        saturation: s.glassSaturation,
        chromatic: s.glassChromatic,
        lightIntensity: s.glassLightIntensity,
      ),
    ),
  );
  return GlassTuning(
    blur: s.blur,
    thickness: s.thickness,
    saturation: s.saturation,
    chromatic: s.chromatic,
    lightIntensity: s.lightIntensity,
  );
});

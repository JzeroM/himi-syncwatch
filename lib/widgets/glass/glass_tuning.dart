import 'package:flutter/foundation.dart';
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

  /// 应用默认值（滑杆回显与「恢复默认」目标；null 字段的渲染兜底）。
  final double defaultValue;
  final int divisions;

  /// 值回显小数位（色散需要 3 位）。
  final int decimals;

  /// 读取 [GlassTuning] 中该参数的当前值（null 回退平台默认 [glassDefault]）。
  double read(GlassTuning tuning) => switch (key) {
        'glassBlur' => tuning.blur ?? glassDefault('glassBlur'),
        'glassThickness' => tuning.thickness ?? glassDefault('glassThickness'),
        'glassEdgeZone' => tuning.edgeZone ?? glassDefault('glassEdgeZone'),
        'glassSaturation' =>
          tuning.saturation ?? glassDefault('glassSaturation'),
        'glassChromatic' => tuning.chromatic ?? glassDefault('glassChromatic'),
        'glassLightIntensity' =>
          tuning.lightIntensity ?? glassDefault('glassLightIntensity'),
        'glassRefractiveIndex' =>
          tuning.refractiveIndex ?? glassDefault('glassRefractiveIndex'),
        _ => defaultValue,
      };

  /// 把值写回 [AppSettings.copyWith]（保留未传字段）。
  AppSettings apply(AppSettings s, double value) => switch (key) {
        'glassBlur' => s.copyWith(glassBlur: value),
        'glassThickness' => s.copyWith(glassThickness: value),
        'glassEdgeZone' => s.copyWith(glassEdgeZone: value),
        'glassSaturation' => s.copyWith(glassSaturation: value),
        'glassChromatic' => s.copyWith(glassChromatic: value),
        'glassLightIntensity' => s.copyWith(glassLightIntensity: value),
        'glassRefractiveIndex' => s.copyWith(glassRefractiveIndex: value),
        _ => s,
      };
}

/// 液态玻璃可调参数规格（设置页滑杆的展示顺序即列表顺序）。
///
/// [GlassParamSpec.defaultValue] 是「应用默认」的单一事实源：滑杆回显
/// （null 时）与 [GlassTuning.toThemeData] 对 null 字段的兜底都取这里，
/// 保证设置为 null（恢复默认）时渲染出的目标观感 = 滑杆显示的默认值。
/// 目标观感对齐 Kyant 液态玻璃 demo：强镜片折射 + 明显彩虹色散圈。
const List<GlassParamSpec> glassParamSpecs = [
  GlassParamSpec(
    key: 'glassBlur',
    label: '磨砂模糊',
    min: 0,
    max: 20,
    defaultValue: 4,
    divisions: 40,
  ),
  GlassParamSpec(
    key: 'glassThickness',
    label: '玻璃厚度',
    min: 0,
    max: 60,
    defaultValue: 28,
    divisions: 60,
  ),
  GlassParamSpec(
    key: 'glassEdgeZone',
    label: '折射范围',
    min: 20,
    max: 24,
    defaultValue: 20,
    divisions: 4,
    decimals: 0,
  ),
  GlassParamSpec(
    key: 'glassSaturation',
    label: '饱和增强',
    min: 1.0,
    max: 2.5,
    defaultValue: 1.7,
    divisions: 30,
  ),
  GlassParamSpec(
    key: 'glassChromatic',
    label: '色散',
    min: 0,
    max: 0.5,
    defaultValue: 0.15,
    divisions: 50,
    decimals: 3,
  ),
  GlassParamSpec(
    key: 'glassLightIntensity',
    label: '高光强度',
    min: 0,
    max: 2,
    defaultValue: 1.2,
    divisions: 40,
  ),
  GlassParamSpec(
    key: 'glassRefractiveIndex',
    label: '折射强度',
    min: 1.0,
    max: 2.0,
    defaultValue: 1.25,
    divisions: 20,
  ),
];

/// iOS premium（Impeller）逼真取向默认值。
///
/// 安卓 standard（Skia）路径的滑杆默认是给 `interactive_indicator.frag`
/// 归一化补偿用的；iOS 走 premium（`liquid_glass_render.frag` + Impeller
/// 原生折射），同一数值观感偏弱。这里给 iOS 一组更接近实体玻璃的默认值
/// （强折射 + 可见色散），并让滑杆回显/渲染兜底同源，尽量贴近安卓观感。
class GlassIosPremium {
  const GlassIosPremium._();

  static const double thickness = 36;
  static const double saturation = 1.85;
  static const double chromatic = 0.30;
  static const double refractiveIndex = 1.40;
  static const double lightIntensity = 1.3;
}

/// 取 [key] 对应参数的平台默认值（iOS premium 用 [GlassIosPremium]，
/// 其余平台用 [glassParamSpecs] 的应用默认）——滑杆回显、渲染兜底与调用方
/// （如导航水珠镜片的显式 settings）同源，避免字面量重复。
double glassDefault(String key) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    switch (key) {
      case 'glassThickness':
        return GlassIosPremium.thickness;
      case 'glassSaturation':
        return GlassIosPremium.saturation;
      case 'glassChromatic':
        return GlassIosPremium.chromatic;
      case 'glassRefractiveIndex':
        return GlassIosPremium.refractiveIndex;
      case 'glassLightIntensity':
        return GlassIosPremium.lightIntensity;
    }
  }
  return glassParamSpecs.firstWhere((s) => s.key == key).defaultValue;
}

/// 折射范围（glassEdgeZone）滑杆可见性：仅 Android 非 TV 模式显示。
///
/// - Android 是唯一目标消费端：standard（Skia）路径读
///   `interactive_indicator.frag` 的 `uEdgeZone` uniform；
///   iOS premium（Impeller 3D bevel）不读该 uniform，拖动无效；
/// - 其他平台（iOS / 桌面 / Web）一律隐藏；
/// - TV 模式：遥控器方向键导航会被滑杆吞键 → 隐藏。
bool glassEdgeZoneVisible({required bool tvMode}) =>
    defaultTargetPlatform == TargetPlatform.android && !tvMode;

/// 折射强度（glassRefractiveIndex）滑杆可见性：仅 iOS 非 TV 显示
/// （premium/Impeller 路径读 refractiveIndex；安卓 standard 不读）。
bool glassRefractiveIndexVisible({required bool tvMode}) =>
    defaultTargetPlatform == TargetPlatform.iOS && !tvMode;

/// 玻璃参数快照：settings 的可调字段 → 包主题的映射边界。
class GlassTuning {
  const GlassTuning({
    this.blur,
    this.thickness,
    this.edgeZone,
    this.saturation,
    this.chromatic,
    this.lightIntensity,
    this.refractiveIndex,
  });

  final double? blur;
  final double? thickness;

  /// 折射范围（shader edgeZone，20~24；null = 应用默认 20）。
  final double? edgeZone;
  final double? saturation;
  final double? chromatic;
  final double? lightIntensity;

  /// 折射率（premium/iOS 路径；null = 平台默认）。
  final double? refractiveIndex;

  factory GlassTuning.fromSettings(AppSettings s) => GlassTuning(
        blur: s.glassBlur,
        thickness: s.glassThickness,
        edgeZone: s.glassEdgeZone,
        saturation: s.glassSaturation,
        chromatic: s.glassChromatic,
        lightIntensity: s.glassLightIntensity,
        refractiveIndex: s.glassRefractiveIndex,
      );

  /// 是否全部为包默认（决定「恢复默认」按钮的可用性）。
  bool get isDefault =>
      blur == null &&
      thickness == null &&
      edgeZone == null &&
      saturation == null &&
      chromatic == null &&
      lightIntensity == null &&
      refractiveIndex == null;

  /// 映射为包主题：null 字段（恢复默认态）兜底到 [glassDefault]（iOS premium
  /// 取向），保证默认观感 = 目标效果而非包 variant 的保守默认。
  GlassThemeData toThemeData() {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    return GlassThemeData.simple(
      blur: blur ?? glassDefault('glassBlur'),
      thickness: thickness ?? glassDefault('glassThickness'),
      saturation: saturation ?? glassDefault('glassSaturation'),
      chromaticAberration: chromatic ?? glassDefault('glassChromatic'),
      lightIntensity: lightIntensity ?? glassDefault('glassLightIntensity'),
      refractiveIndex: refractiveIndex ?? glassDefault('glassRefractiveIndex'),
      // iOS premium 明确指定画质，保证全玻璃面走 Impeller 折射路径
      quality: isIOS ? GlassQuality.premium : null,
      // iOS premium 内壁环境光提亮，减少灰边
      ambientStrength: isIOS ? 0.5 : null,
    );
  }
}

/// 监听设置中的玻璃参数（仅相关字段，无关设置变化不触发重建），
/// 驱动 `LiquidGlassWidgets.wrap(theme:)` 与水珠镜片实时生效。
final glassTuningProvider = Provider<GlassTuning>((ref) {
  final s = ref.watch(
    settingsProvider.select(
      (s) => (
        blur: s.glassBlur,
        thickness: s.glassThickness,
        edgeZone: s.glassEdgeZone,
        saturation: s.glassSaturation,
        chromatic: s.glassChromatic,
        lightIntensity: s.glassLightIntensity,
        refractiveIndex: s.glassRefractiveIndex,
      ),
    ),
  );
  return GlassTuning(
    blur: s.blur,
    thickness: s.thickness,
    edgeZone: s.edgeZone,
    saturation: s.saturation,
    chromatic: s.chromatic,
    lightIntensity: s.lightIntensity,
    refractiveIndex: s.refractiveIndex,
  );
});

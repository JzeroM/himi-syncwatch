import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

/// 一个可选的应用图标（默认 + 备用）。
class AppIconOption {
  const AppIconOption({
    required this.id,
    required this.label,
    required this.asset,
  });

  /// 图标 id：null = 默认（default）；其余为备用图标键（artistic/glass/neon）。
  final String? id;

  /// 设置页展示名。
  final String label;

  /// 设置页预览图（assets/icons/<name>.png）。
  final String asset;
}

/// 运行时应用图标切换（仅 Android 手机 + iOS）。
///
/// 平台差异：
/// - iOS：`setAlternateIconName(name)` 的 name 即 `CFBundleAlternateIcons` 的键；
///   null 还原默认。
/// - Android：插件按 `activity-alias` 组件启停切换，name 必须是别名的
///   **全限定类名**（`<applicationId>.icon_<id>` / `<applicationId>.DEFAULT`）。
///
/// 注意：Android 的图标变更由插件 Service 在「任务移除/服务销毁」时落地，
/// 即用户划掉应用后（或系统回收）才在桌面刷新。
class AppIconService {
  AppIconService._();

  /// Android applicationId（与 build.gradle / namespace 一致）。
  static const String androidPackage = 'com.himi.syncwatch';

  /// 可选图标：默认 default + 备用 artistic/glass/neon（顺序即设置页顺序）。
  static const List<AppIconOption> options = [
    AppIconOption(id: null, label: '默认', asset: 'assets/icons/default.png'),
    AppIconOption(
        id: 'artistic', label: 'Artistic', asset: 'assets/icons/artistic.png'),
    AppIconOption(id: 'glass', label: 'Glass', asset: 'assets/icons/glass.png'),
    AppIconOption(id: 'neon', label: 'Neon', asset: 'assets/icons/neon.png'),
  ];

  /// 当前平台是否支持切换（Android/iOS）。
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// id → 平台参数（Android 全限定别名 / iOS 键 / 默认）。
  static String? platformIconName(String? id) {
    if (id == null) {
      return _isAndroid ? '$androidPackage.DEFAULT' : null;
    }
    return _isAndroid ? '$androidPackage.icon_$id' : id;
  }

  /// 平台返回值 → id（无法识别回退默认）。
  static String? idFromPlatformName(String? name) {
    if (name == null || name.isEmpty) return null;
    var n = name;
    if (_isAndroid) {
      if (n.endsWith('.DEFAULT')) return null;
      final marker = '.icon_';
      final i = n.lastIndexOf(marker);
      if (i >= 0) {
        n = n.substring(i + marker.length);
      } else if (n.startsWith('icon_')) {
        n = n.substring('icon_'.length);
      }
    }
    return options.any((o) => o.id == n) ? n : null;
  }

  /// 系统是否支持备用图标。
  static Future<bool> supports() async {
    if (!isSupported) return false;
    try {
      return await FlutterDynamicIconPlus.supportsAlternateIcons;
    } catch (_) {
      return false;
    }
  }

  /// 当前生效的图标 id（null = 默认）。
  static Future<String?> currentId() async {
    if (!isSupported) return null;
    try {
      return idFromPlatformName(await FlutterDynamicIconPlus.alternateIconName);
    } catch (_) {
      return null;
    }
  }

  /// 本机标识读取（测试可注入替身，避免依赖 device_info 平台通道）。
  @visibleForTesting
  static Future<
          ({
            List<String> brands,
            List<String> manufactures,
            List<String> models
          })>
      Function() deviceBlacklistLoader = loadDeviceBlacklist;

  /// 应用图标（id=null 还原默认）。失败抛出，由调用方提示。
  ///
  /// Android：把本机厂商/品牌/型号作为「黑名单」传入 —— 与自身恒匹配，
  /// 插件 `containsOnBlacklist` 命中 → 走**立即** `changeAppIcon`（组件启停
  /// 当场生效），否则插件只起 Service、要等应用被划掉才生效（小米/MIUI
  /// 尤甚，插件文档点名）。
  static Future<void> apply(String? id) async {
    if (!isSupported) return;
    if (_isAndroid) {
      final blacklist = await deviceBlacklistLoader();
      await FlutterDynamicIconPlus.setAlternateIconName(
        iconName: platformIconName(id),
        blacklistBrands: blacklist.brands,
        blacklistManufactures: blacklist.manufactures,
        blacklistModels: blacklist.models,
      );
      return;
    }
    await FlutterDynamicIconPlus.setAlternateIconName(
      iconName: platformIconName(id),
    );
  }

  /// 启动自愈：已存设置与系统当前图标不一致时重新应用（Android/iOS）。
  static Future<void> syncOnStart(String? desiredId) async {
    if (!isSupported) return;
    try {
      final current = await currentId();
      if (current != desiredId) await apply(desiredId);
    } catch (_) {}
  }

  /// 读取本机标识构造黑名单（与设备自身恒匹配 → 强制立即分支）。
  static Future<
      ({
        List<String> brands,
        List<String> manufactures,
        List<String> models
      })> loadDeviceBlacklist() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return blacklistArgs(
        brand: info.brand,
        manufacturer: info.manufacturer,
        model: info.model,
      );
    } catch (_) {
      return blacklistArgs();
    }
  }

  /// 黑名单参数构造（纯函数，便于单测）：任一标识非空即用自身命中；
  /// 全空时兜底小米/红米（最常见的问题厂商）。
  @visibleForTesting
  static ({List<String> brands, List<String> manufactures, List<String> models})
      blacklistArgs({String? brand, String? manufacturer, String? model}) {
    final b = (brand ?? '').trim();
    final m = (manufacturer ?? '').trim();
    final mo = (model ?? '').trim();
    if (b.isEmpty && m.isEmpty && mo.isEmpty) {
      return (
        brands: const ['Redmi'],
        manufactures: const ['Xiaomi'],
        models: const <String>[],
      );
    }
    return (
      brands: [if (b.isNotEmpty) b],
      manufactures: [if (m.isNotEmpty) m],
      models: [if (mo.isNotEmpty) mo],
    );
  }
}

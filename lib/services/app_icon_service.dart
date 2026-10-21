import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';

/// 一个可选的应用图标（默认 + 备用）。
class AppIconOption {
  const AppIconOption({
    required this.id,
    required this.label,
    required this.asset,
  });

  /// 图标 id：null = 默认（default）；其余为备用图标键（artistic/mint/glass）。
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
/// - Android：走自有 `himi/app_icon` 通道，每次切换启用目标 activity-alias
///   并禁用其余全部别名，避免历史脏状态下多个别名同时启用导致桌面不刷新。
class AppIconService {
  AppIconService._();

  /// Android 原生图标切换通道（见 AppIconPlugin.kt）。
  static const MethodChannel androidChannel = MethodChannel('himi/app_icon');

  /// 可选图标：默认 default + 备用 artistic/mint/glass（顺序即设置页顺序）。
  static const List<AppIconOption> options = [
    AppIconOption(id: null, label: '默认', asset: 'assets/icons/default.png'),
    AppIconOption(
        id: 'artistic', label: '艺术字', asset: 'assets/icons/artistic.png'),
    AppIconOption(id: 'mint', label: '薄荷绿', asset: 'assets/icons/mint.png'),
    AppIconOption(id: 'glass', label: '玻璃紫', asset: 'assets/icons/glass.png'),
  ];

  /// 当前平台是否支持切换（Android/iOS）。
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 平台返回值 → id（无法识别回退默认）。
  static String? idFromPlatformName(String? name) {
    if (name == null || name.isEmpty || name == 'default') return null;
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
      if (_isAndroid) {
        return await androidChannel.invokeMethod<bool>('supports') ?? false;
      }
      return await FlutterDynamicIconPlus.supportsAlternateIcons;
    } catch (_) {
      return false;
    }
  }

  /// 当前生效的图标 id（null = 默认）。
  static Future<String?> currentId() async {
    if (!isSupported) return null;
    try {
      final name = _isAndroid
          ? await androidChannel.invokeMethod<String>('getIcon')
          : await FlutterDynamicIconPlus.alternateIconName;
      return idFromPlatformName(name);
    } catch (_) {
      return null;
    }
  }

  /// 应用图标（id=null 还原默认）。失败抛出，由调用方回滚设置并提示。
  ///
  /// Android：启用目标别名后禁用其余全部别名，并回查实际生效值。
  /// iOS：只走公开 API（`isSilent: false`）。插件 1.4.1 的静默分支执行
  /// 私有 API 后**从不回传 result**（completion 丢弃且不调 result），
  /// await 会永久挂起；且与后续调用存在竞态（iOS 拒绝并发
  /// setAlternateIconName）。公开 API 完整回传成功/错误，系统会弹
  /// 「已更改图标」提示（设置页文案已注明）。
  static Future<void> apply(String? id) async {
    if (!isSupported) return;
    final target = _validateId(id);
    try {
      if (_isAndroid) {
        await androidChannel.invokeMethod<bool>('setIcon', {
          'id': target ?? 'default',
        });
        final actual = await currentId();
        if (actual != target) {
          throw StateError('图标未生效：期望 ${target ?? 'default'}，实际 $actual');
        }
        return;
      }
      await _applyIos(target);
      final actual = await currentId();
      if (actual != target) {
        throw StateError('图标未生效：期望 ${target ?? 'default'}，实际 $actual');
      }
    } catch (e) {
      debugPrint('AppIconService.apply($id) failed: $e');
      rethrow;
    }
  }

  static String? _validateId(String? id) {
    if (id != null && !options.any((o) => o.id == id)) {
      throw ArgumentError.value(id, 'id', '未知应用图标');
    }
    return id;
  }

  /// iOS 切换：公开 API 单次调用（见 [apply] 注释：为何不用静默分支）。
  static Future<void> _applyIos(String? id) async {
    await FlutterDynamicIconPlus.setAlternateIconName(
      iconName: id,
      isSilent: false,
    );
  }

  /// 启动自愈：已存设置与系统当前图标不一致时重新应用（Android/iOS）。
  static Future<void> syncOnStart(String? desiredId) async {
    if (!isSupported) return;
    try {
      final current = await currentId();
      if (current != desiredId) await apply(desiredId);
    } catch (e) {
      debugPrint('AppIconService.syncOnStart($desiredId) failed: $e');
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 返回键拦截回调：返回 true = 已消费本次返回（页面自行处理，如关表单/取消布局）；
/// 返回 false = 未消费，继续走壳层默认返回逻辑。
typedef ShellBackIntercept = bool Function();

/// 壳层返回键拦截器：页面在特殊状态（内联表单、TV 布局模式）时注册回调，
/// MainShell._handleBack 首行查询并优先执行。
///
/// 生命周期：页面在进入特殊状态时 register，退出时 clear，dispose 时 clear。
class ShellBackInterceptNotifier extends StateNotifier<ShellBackIntercept?> {
  ShellBackInterceptNotifier() : super(null);

  void register(ShellBackIntercept intercept) => state = intercept;

  void clear() => state = null;
}

final shellBackInterceptProvider =
    StateNotifierProvider<ShellBackInterceptNotifier, ShellBackIntercept?>(
        (ref) => ShellBackInterceptNotifier());

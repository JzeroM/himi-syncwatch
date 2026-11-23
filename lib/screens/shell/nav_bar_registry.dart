import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';

/// 底部导航栏样式注册表（698 N15-E）：款式 =「动效性格」，皮肤统一液态
/// 玻璃家族（各款自带「液态玻璃」开关的双形态）。**新增款式 = 加枚举 +
/// [NavBarStyle.build] 一个分支**，外观页选择行自动出现（未来加款零改壳）。
enum NavBarStyle {
  /// ① 玻璃水滴（默认，现行款）：液滴安静跟随（snappy 弹簧）+ 拖动切换。
  glassCapsule('玻璃水滴'),

  /// ② 流体液态：bouncy 弹簧过冲 + 速度拉伸 + 图标弹跳（双玻璃形态）。
  fluidGlass('流体液态');

  const NavBarStyle(this.label);

  /// 外观页显示名。
  final String label;

  /// 存档解析（未知值回默认款，容错旧数据）。
  static NavBarStyle parse(String? raw) => values.firstWhere(
        (e) => e.name == raw,
        orElse: () => NavBarStyle.glassCapsule,
      );

  /// 顶栏房间入口是否显示（698 N28）：②款水滴分裂的「开房/加入」子滴
  /// 已接管房间入口 → 顶栏只留搜索；①款保持房间钮 + 搜索。
  static bool shouldShowRoomMenu(String? navBarStyleRaw) =>
      parse(navBarStyleRaw) != NavBarStyle.fluidGlass;

  /// 构建款式（壳层统一切换入口）。[onCreateRoom]/[onJoinRoom] 仅②款
  /// 水滴分裂的「开房/加入」子滴消费（698 N28）。
  Widget build({
    required int currentIndex,
    required ValueChanged<int> onSelect,
    VoidCallback? onCreateRoom,
    VoidCallback? onJoinRoom,
  }) {
    switch (this) {
      case NavBarStyle.glassCapsule:
        return ShellNavBar(currentIndex: currentIndex, onSelect: onSelect);
      case NavBarStyle.fluidGlass:
        return FluidGlassNavBar(
          currentIndex: currentIndex,
          onSelect: onSelect,
          onCreateRoom: onCreateRoom,
          onJoinRoom: onJoinRoom,
        );
    }
  }
}

/// 导航栏样式宿主：按设置分发到注册款（切样式即时生效）。
class NavBarStyleHost extends ConsumerWidget {
  const NavBarStyleHost({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.onCreateRoom,
    this.onJoinRoom,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// ②款「开房/加入」子滴回调（N28）。
  final VoidCallback? onCreateRoom;
  final VoidCallback? onJoinRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = NavBarStyle.parse(
      ref.watch(settingsProvider.select((s) => s.navBarStyle)),
    );
    return style.build(
      currentIndex: currentIndex,
      onSelect: onSelect,
      onCreateRoom: onCreateRoom,
      onJoinRoom: onJoinRoom,
    );
  }
}

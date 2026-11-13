import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/screens/settings/engine_config_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

/// 697：单个引擎的独立设置子页（TV 模式从引擎板块点进来）。
///
/// ## 为什么需要
///
/// 690 的 TV 引擎设置在「播放器配置」页用**分段胶囊**切换引擎。但那个
/// 胶囊的 `Focus(canRequestFocus: false)` 让节点**永远拿不到焦点**，
/// `onKeyEvent` 里的左右键处理是死代码——遥控器根本切不到别的引擎
/// （真机反馈「焦点切换不到别的引擎上」）。
///
/// 697 改为**纵向引擎板块 + 独立子页**：
/// - 「播放器配置」页只列 3 个引擎板块（`SettingsCategoryCard`，
///   TV 下自带焦点环，上下键天然可遍历）
/// - 点板块 → push 本页，只展示该引擎的专属设置
/// - 返回时焦点回到进入时那个板块（由调用方 `_openEngineDetail` 处理）
///
/// 内容复用 [engineSettingChildren]（单一事实源，避免两处设置项漂移）。
class EngineDetailScreen extends ConsumerWidget {
  const EngineDetailScreen({
    super.key,
    required this.engine,
  });

  /// 目标引擎。路由层从 `engineId` 解析后传入。
  final PlayerEngine engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 【为什么直接把设置项铺进 SettingsSubPage】`SettingsSubPage` 本身
    // 是 `ListView`；若再嵌一层 `EngineTabBody`（也是 ListView）会因
    // 高度无界而报错。这里直接取 children 铺平。
    return SettingsSubPage(
      pageKey: ValueKey('engineDetailPage_${engine.id}'),
      title: engine.label,
      children: engineSettingChildren(context, ref, engine),
    );
  }
}

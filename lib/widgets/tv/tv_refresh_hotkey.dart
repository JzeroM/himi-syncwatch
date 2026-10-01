import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';

/// TV 模式遥控器菜单键（contextMenu）触发页面刷新。
///
/// 下拉刷新依赖触摸手势，TV 遥控器不可用；菜单键是电视端惯用刷新入口。
/// 非 TV 模式原样透传（零影响）；触摸端 [RefreshIndicator] 保留并存。
/// 焦点在页面内容内时，按键事件沿焦点链到达本层（冷启动未落焦时
/// 菜单键不响应，方向键/OK 落焦后即可用）。
class TvRefreshHotkey extends ConsumerWidget {
  const TvRefreshHotkey({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (!tvMode) return child;

    // canRequestFocus: false —— 本层 Focus 包住整个页面内容，rect 是
    // 全屏 body；若可聚焦，方向遍历会把它当巨大候选抢占焦点，焦点落上
    // 后按上键「源上方无候选」→ 遍历失败 + 列表已到顶 → 吞键，焦点再也
    // 回不到顶栏。禁用 request 后仍留在焦点祖先链上，菜单键照常冒泡。
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.contextMenu) {
          onRefresh();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

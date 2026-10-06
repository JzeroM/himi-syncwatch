import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/search/global_search_screen.dart';
import 'package:himi_syncwatch/screens/search/remote_search_screen.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 顶部「搜索」入口按钮：已认证服务器存在时可点，打开聚合搜索。
///
/// 从首页 AppBar 迁出为共享组件：TV 顶栏与首页顶栏（非 TV）复用。
/// TV 模式打开扫码远程搜索页（手机搜索电视打开，附「电视本机搜索」备选），
/// 非 TV 打开本机搜索页；TV 模式按钮为 [TvFocusable] 焦点环形态。
class MediaSearchButton extends ConsumerWidget {
  const MediaSearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 原首页逻辑：仅已认证服务器时展示搜索入口
    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated ?? false;
    if (!hasServer) return const SizedBox.shrink();

    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (!tvMode) {
      return IconButton(
        icon: const Icon(Icons.search),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: () => _openSearch(context, tvMode: false),
      );
    }
    return TvFocusable(
      radius: 12,
      onTap: () => _openSearch(context, tvMode: true),
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.search),
      ),
    );
  }

  void _openSearch(BuildContext context, {required bool tvMode}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            tvMode ? const RemoteSearchScreen() : const GlobalSearchScreen(),
      ),
    );
  }
}

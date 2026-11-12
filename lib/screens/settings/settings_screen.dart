import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

/// 设置主页（690 方案）：**六个分类玻璃卡片**。
///
/// ## 为什么改
///
/// 旧实现是 5 行 `ListTile` + `Divider`——Material 默认列表，与整套液态
/// 玻璃风格完全不搭（整个应用最不「玻璃」的页面）。
///
/// 现在每个分类是一张独立玻璃卡片：
/// - 图标 36×36 圆形主色渐变底
/// - 悬停上浮 + 主色描边（TV 焦点环）
/// - 响应式列数：手机 1 列 / 平板 2 列 / 宽屏 3 列
///
/// ## 690 新增「数据」分类
///
/// 缓存管理从「通用」迁到独立的「数据」页（路由 `/settings/data`）。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// 分类定义（key 保持向后兼容，测试依赖）。
  static const _categories = <_CategorySpec>[
    _CategorySpec(
      keyName: 'settingsCategoryAppearance',
      icon: Icons.palette_outlined,
      title: '外观',
      subtitle: '主题色、分类页每行海报数、液态玻璃',
      route: '/settings/appearance',
    ),
    _CategorySpec(
      keyName: 'settingsCategoryPlayer',
      icon: Icons.play_circle_outline,
      title: '播放器',
      subtitle: '引擎设置、片头片尾、网速、弹幕',
      route: '/settings/player',
    ),
    _CategorySpec(
      keyName: 'settingsCategoryGeneral',
      icon: Icons.tune,
      title: '通用',
      subtitle: 'TV 模式、同步到 TV、顶栏时间、导出日志',
      route: '/settings/general',
    ),
    // 690：新增「数据」——缓存管理独立成页
    _CategorySpec(
      keyName: 'settingsCategoryData',
      icon: Icons.storage_outlined,
      title: '数据',
      subtitle: '清理图片、弹幕、临时文件与诊断日志',
      route: '/settings/data',
    ),
    _CategorySpec(
      keyName: 'settingsCategoryExperimental',
      icon: Icons.science_outlined,
      title: '实验性',
      subtitle: '渲染兼容模式、播放调试面板、深度诊断',
      route: '/settings/experimental',
    ),
    _CategorySpec(
      keyName: 'settingsCategoryAbout',
      icon: Icons.info_outline,
      title: '关于',
      subtitle: '版本信息、检查更新',
      route: '/settings/about',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 690：响应式列数——手机 1 / 平板 2 / 宽屏 3。
          final width = constraints.maxWidth;
          final columns = width >= 1100 ? 3 : (width >= 640 ? 2 : 1);
          const gap = 12.0;
          final pad = 16.0;
          final itemWidth =
              (width - pad * 2 - gap * (columns - 1)) / columns;

          // 690：用 `ListView`（而非 SingleChildScrollView + Wrap）——
          // TV 的「两段式 OK」靠 `traversalDescendants` 找首个可聚焦项，
          // `Wrap` 下的焦点遍历顺序不稳定（真机/测试都会落不到焦）。
          // ListView 是 Sliver 列表，遍历顺序与旧实现一致。
          final rows = (_categories.length + columns - 1) ~/ columns;
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              pad,
              GlassConfig.topInsetOf(context) + 8,
              pad,
              GlassConfig.bottomReserveOf(context),
            ),
            itemCount: rows,
            itemBuilder: (context, row) {
              return Padding(
                padding: EdgeInsets.only(bottom: gap),
                child: Row(
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (row * columns + c < _categories.length)
                        SizedBox(
                          width: itemWidth,
                          child: SettingsCategoryCard(
                            key: ValueKey(
                                _categories[row * columns + c].keyName),
                            icon: _categories[row * columns + c].icon,
                            title: _categories[row * columns + c].title,
                            subtitle: _categories[row * columns + c].subtitle,
                            tvMode: tvMode,
                            onTap: () => context.push(
                                _categories[row * columns + c].route),
                          ),
                        )
                      else
                        SizedBox(width: itemWidth),
                      if (c < columns - 1) const SizedBox(width: gap),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 分类卡片定义（纯数据）。
class _CategorySpec {
  const _CategorySpec({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

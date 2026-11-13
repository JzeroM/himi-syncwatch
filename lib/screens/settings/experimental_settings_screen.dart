import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_common.dart';
import 'package:himi_syncwatch/services/log_service.dart';

/// 实验性设置子页：**只保留诊断**。
///
/// ## 697 精简
///
/// 此前这里是「渲染（仅 Android）+ 诊断 + 高级（A/B 对比）」三组开关：
/// - 渲染兼容模式 / HDR image=0 / 硬解 low_latency / 8-bit 渲染表面
/// - HDR GL 渲染方案 / 音频自适应同步
///
/// 这些开关都是**设备相关**的底层引擎参数，普通用户开了只会黑屏或卡顿，
/// 真出问题也应该由诊断日志定位而不是让用户自己试。现已全部移除
/// （字段仍保留在 `AppSettings` 里，兼容旧存档与既有代码路径）。
///
/// 同时把「导出运行日志」从「通用」迁到这里——诊断能力集中在一处，
/// 用户报问题时只需要进一个页面。
class ExperimentalSettingsScreen extends ConsumerWidget {
  const ExperimentalSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SettingsSubPage(
      pageKey: const ValueKey('experimentalSettingsPage'),
      title: '实验性',
      children: [
        SettingsGroupCard(
          title: '诊断',
          children: [
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () =>
                  notifier.update(showSyncDebug: !settings.showSyncDebug),
              child: SwitchListTile(
                title: const Text('播放调试面板'),
                subtitle: const Text('实时显示 HDR / 杜比视界参数，可拖拽移动'),
                value: settings.showSyncDebug,
                onChanged: (v) => notifier.update(showSyncDebug: v),
              ),
            ),
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () =>
                  notifier.update(deepDiagnostics: !settings.deepDiagnostics),
              child: SwitchListTile(
                title: const Text('深度诊断'),
                subtitle: const Text(
                  '抓取 mdk 内部日志获取实测帧率。仅诊断卡顿时开启，可能增加少量开销',
                ),
                value: settings.deepDiagnostics,
                onChanged: (v) => notifier.update(deepDiagnostics: v),
              ),
            ),
            // 697：从「通用」迁入——诊断相关操作集中在本页。
            settingsTvWrapRow(
              tvMode: settings.tvMode,
              onTap: () => LogService().shareLogs(),
              child: ListTile(
                key: const ValueKey('exportLogsTile'),
                leading: const Icon(Icons.bug_report),
                title: const Text('导出运行日志'),
                subtitle: const Text('保存最近 1000 条日志并分享'),
                onTap: () => LogService().shareLogs(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

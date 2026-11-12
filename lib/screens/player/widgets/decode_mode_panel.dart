import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 解码模式面板（播放器右上 popover，180dp 宽）。
///
/// 【深色磨砂（587）】与播放器其他弹层统一：走 [GlassContainer] 的
/// `popup: true` 分支（近黑 65% 竖向渐变 + 白 20% 描边 + 重投影 + 实时
/// 折射模糊）。文字恒白（正文 14/w500、说明 12/w500 白 70%），选中只靠
/// 行底 accent 20% + 单选圈表达——与安卓 `decodeOptionRow` / 鸿蒙
/// `DecodeContent` 逐值一致。
class DecodeModePanel extends ConsumerWidget {
  final ValueChanged<String> onSwitchMode;

  const DecodeModePanel({
    super.key,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 687：只订阅 decodeMode（旧写法先取整个 AppSettings 再读字段，
    // 等价于全量监听）。
    final currentMode =
        ref.watch(settingsProvider.select((s) => s.decodeMode));
    final modes = ['auto', 'hw', 'sw'];
    final labels = {'auto': '智能', 'hw': '硬解', 'sw': '软解'};
    final descriptions = {
      'auto': '优先硬解，失败回退软解',
      'hw': '纯硬解，失败不回退',
      'sw': '纯软解，CPU 占用高',
    };

    return GestureDetector(
      onTap: () {},
      child: SizedBox(
        width: 180,
        child: GlassContainer(
          popup: true,
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行：`解码模式` 15 w600 + 当前档位 14 w500（正文一律纯白，
              // 档位不用强调色——强调只由选项行的单选圈/行底表达）。
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    const Text(
                      '解码模式',
                      style: TextStyle(
                        color: GlassConfig.playerPanelTextPrimary,
                        fontSize: GlassConfig.playerPanelTitleSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      labels[currentMode] ?? '',
                      style: const TextStyle(
                        color: GlassConfig.playerPanelTextPrimary,
                        fontSize: GlassConfig.playerPanelBodySize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 0.5,
                color: GlassConfig.playerPanelDivider,
              ),
              ...modes.map((mode) {
                final isSelected = currentMode == mode;
                // TV 遥控：选项行可聚焦（焦点环 + Enter 选择），触摸行为不变
                return TvFocusable(
                  autofocus: modes.first == mode,
                  onTap: () => onSwitchMode(mode),
                  radius: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? GlassConfig.playerPanelSelectedBg
                          : null,
                      // 每行底边通栏 0.5dp（含末行，与深色版一致）
                      border: const Border(
                          bottom: BorderSide(
                              color: GlassConfig.playerPanelDivider,
                              width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : GlassConfig.playerPanelTextSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(labels[mode]!,
                                  style: const TextStyle(
                                      color: GlassConfig.playerPanelTextPrimary,
                                      fontSize: GlassConfig.playerPanelBodySize,
                                      fontWeight: FontWeight.w500)),
                              Text(descriptions[mode]!,
                                  style: const TextStyle(
                                      color: GlassConfig.playerPanelTextSecondary,
                                      fontSize: GlassConfig.playerPanelCaptionSize,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}

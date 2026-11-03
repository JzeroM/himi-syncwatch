import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 解码模式面板（播放器右上 popover，180dp 宽）。
///
/// 【白底磨砂】与播放器其他弹层统一：白基竖向渐变 + 暗描边 + 重投影，
/// 文字近黑、次级黑 54%，选中行强调色 12% 底 + 强调色文字/图标。
/// 顶栏、底栏等浮在视频上的控件仍保持深色玻璃（白字）。
class DecodeModePanel extends ConsumerWidget {
  final ValueChanged<String> onSwitchMode;

  const DecodeModePanel({
    super.key,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(settingsProvider).decodeMode;
    final modes = ['auto', 'hw', 'sw'];
    final labels = {'auto': '智能', 'hw': '硬解', 'sw': '软解'};
    final descriptions = {
      'auto': '优先硬解，失败回退软解',
      'hw': '纯硬解，失败不回退',
      'sw': '纯软解，CPU 占用高',
    };

    return GestureDetector(
      onTap: () {},
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              GlassConfig.playerPanelWhiteTop,
              GlassConfig.playerPanelWhite,
              GlassConfig.playerPanelWhiteBottom,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: GlassConfig.playerPanelRimLight),
          boxShadow: GlassConfig.playerPanelShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题行：`解码模式` 13 加粗 + 当前档位 12 强调色。
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    const Text(
                      '解码模式',
                      style: TextStyle(
                        color: GlassConfig.playerPanelTextPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      labels[currentMode] ?? '',
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 12,
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
                          ? const Color(0xFF6366F1).withValues(alpha: 0.12)
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
                                  style: TextStyle(
                                      color: GlassConfig.playerPanelTextPrimary,
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              Text(descriptions[mode]!,
                                  style: const TextStyle(
                                      color: GlassConfig.playerPanelTextSecondary,
                                      fontSize: 10)),
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

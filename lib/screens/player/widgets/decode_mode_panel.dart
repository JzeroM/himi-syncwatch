import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';

class DecodeModePanel extends ConsumerWidget {
  final bool isDolbyVisionP5;
  final ValueChanged<String> onSwitchMode;

  const DecodeModePanel({
    super.key,
    required this.isDolbyVisionP5,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isDolbyVisionP5) {
      return Container(
        width: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF6366F1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.radio_button_checked, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('软解', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        Text('DV P5 强制软解', style: TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: modes.map((mode) {
            final isSelected = currentMode == mode;
            return InkWell(
              onTap: () => onSwitchMode(mode),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF6366F1).withValues(alpha: 0.3) : null,
                  border: const Border(bottom: BorderSide(color: Colors.white12, width: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? const Color(0xFF6366F1) : Colors.white54,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(labels[mode]!, style: TextStyle(
                            color: Colors.white, fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          )),
                          Text(descriptions[mode]!, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

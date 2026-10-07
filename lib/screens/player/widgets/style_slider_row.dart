import 'package:flutter/material.dart';

/// 调节面板共享滑杆行：标签(44) + 滑杆(自适应) + 数值(48)。
///
/// 字幕样式与弹幕调节面板共用（行间上下各 10px → 相邻行净距 +20px，
/// 方便拖动操作）；数值文本带 [valueKey] 供测试定位。
Widget styleSliderRow({
  required String label,
  required String valueText,
  required String valueKey,
  required Widget slider,
}) {
  return Padding(
    key: valueKey.isEmpty ? null : ValueKey('${valueKey}Row'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        Expanded(child: slider),
        SizedBox(
          width: 48,
          child: Text(
            valueText,
            key: ValueKey(valueKey),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    ),
  );
}

/// 面板段标题（组合面板区分字幕段/弹幕段）。
Widget panelSectionHeader(String title) {
  return Padding(
    key: ValueKey('${title}SectionHeader'),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Text(
      title,
      style: const TextStyle(fontSize: 11, color: Colors.white38),
    ),
  );
}

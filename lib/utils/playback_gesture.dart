import 'package:flutter/material.dart';

/// 双击播放/暂停手势的指示器图标。
///
/// 显示**当前可执行的动作**（与底部控制栏播放/暂停按钮语义一致）：
/// 播放中显示暂停图标，暂停后显示播放图标。
IconData playPauseHintIcon(bool playing) =>
    playing ? Icons.pause : Icons.play_arrow;

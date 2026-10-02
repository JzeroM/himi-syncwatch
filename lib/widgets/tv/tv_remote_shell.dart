import 'package:flutter/material.dart';
import 'package:himi_syncwatch/widgets/tv/tv_directional_scroll.dart';

/// TV 遥控器公共挂载壳：生产（MaterialApp.builder）与测试共用同一结构，
/// 避免测试挂载层与线上不一致。
///
/// 两层职责：
/// 1. [TvRemoteShortcuts]：方向键焦点贯通 + OK 作用域落焦；
/// 2. `navigationMode: directional`：Slider/TextField 等传统导航组件在
///    directional 下只消费左右键（上下放行）——否则焦点落在主题色 HSV
///    滑块上时上下键被调值截获，遥控器既卡死又"上下变调色板进度"。
class TvRemoteShell extends StatelessWidget {
  const TvRemoteShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(navigationMode: NavigationMode.directional),
      child: TvRemoteShortcuts(child: child),
    );
  }
}

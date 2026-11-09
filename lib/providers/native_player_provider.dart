import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 原生播放器窗口是否已打开（649）。
///
/// 【为什么需要】Windows 走原生独立窗口（HDR 直出）时，Flutter 播放页不可见，
/// 但路由仍在栈里。用户从详情页**再次**点播放按钮时，不应再 push 一个
/// PlayerScreen（会创建第二个窗口），而应聚焦已有窗口。
///
/// 由 PlayerScreen 在原生 UI 激活/退出时更新，播放入口据此判断。
final nativePlayerActiveProvider = StateProvider<bool>((ref) => false);

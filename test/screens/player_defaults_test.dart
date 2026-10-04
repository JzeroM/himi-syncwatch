import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

void main() {
  test('播放器默认音量与亮度均为 80', () {
    expect(kPlayerDefaultVolume, closeTo(0.8, 1e-9));
    expect(kPlayerDefaultBrightness, closeTo(0.8, 1e-9));
    expect((kPlayerDefaultVolume * 100).round(), equals(80));
  });

  testWidgets('PlayerScreen.focusWithin：判定焦点是否在热键层子树内', (tester) async {
    final hotkey = FocusNode(debugLabel: 'hotkey');
    final inControls = FocusNode(debugLabel: 'inControls');
    final other = FocusNode(debugLabel: 'other');
    addTearDown(hotkey.dispose);
    addTearDown(inControls.dispose);
    addTearDown(other.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          // 热键层子树（模拟 PlayerHotkey 包裹控制条焦点）
          Focus(
            focusNode: hotkey,
            child: Focus(focusNode: inControls, child: const SizedBox()),
          ),
          // 其他路由/分支（模拟底部弹窗焦点，不应被抢）
          Focus(focusNode: other, child: const SizedBox()),
        ],
      ),
    ));
    await tester.pump();

    expect(PlayerScreen.focusWithin(hotkey, hotkey), isTrue,
        reason: 'root 自身视为在子树内');
    expect(PlayerScreen.focusWithin(hotkey, inControls), isTrue,
        reason: '控制条内焦点应回落热键层');
    expect(PlayerScreen.focusWithin(hotkey, other), isFalse,
        reason: '其他路由焦点不能被抢');
    expect(PlayerScreen.focusWithin(hotkey, null), isFalse, reason: '空焦点安全');
  });
}

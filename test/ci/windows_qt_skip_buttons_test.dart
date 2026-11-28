import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N78：Qt 播放器「跳过片头/片尾」胶囊位置守卫。
///
/// 用户要求：片头 → 播放器**左侧纵轴中心**；片尾 → **右侧纵轴中心**。
void main() {
  final qml = File('native/windows_qt_player/src/qml/Overlay.qml').readAsStringSync();

  test('片头胶囊在左侧纵轴中心', () {
    expect(qml, contains('id: skipIntroCapsule'));
    expect(qml, contains('x: Theme.barPadH'),
        reason: '片头贴左缘内边距');
    expect(qml, contains('y: (parent.height - height) / 2'),
        reason: '纵轴中心');
  });

  test('片尾胶囊在右侧纵轴中心', () {
    expect(qml, contains('id: skipOutroCapsule'));
    expect(qml, contains('x: parent.width - Theme.barPadH - width'),
        reason: '片尾贴右缘内边距');
    expect(qml, contains('y: (parent.height - height) / 2'),
        reason: '纵轴中心');
  });
}
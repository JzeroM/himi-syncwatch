import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/playback_gesture.dart';

void main() {
  group('playPauseHintIcon', () {
    test('播放中显示暂停图标（当前可执行动作）', () {
      expect(playPauseHintIcon(true), Icons.pause);
    });

    test('暂停后显示播放图标', () {
      expect(playPauseHintIcon(false), Icons.play_arrow);
    });
  });
}

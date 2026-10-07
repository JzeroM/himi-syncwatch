import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

import '../helpers/test_fakes.dart';

/// update(danmaku*) 透传与落盘（v1.1.134 弹幕配置）。
void main() {
  group('update(danmaku*)（弹幕配置落盘）', () {
    test('单字段透传并落盘一次', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(danmakuApiUrl: 'http://10.0.0.2:9321/TOKEN');

      expect(notifier.state.danmakuApiUrl, 'http://10.0.0.2:9321/TOKEN');
      expect(notifier.persistCount, 1);
    });

    test('多字段一次更新（行数/屏蔽/滑杆）', () async {
      final notifier = FakeSettingsNotifier();
      await notifier.update(
        danmakuDefaultOn: false,
        danmakuScrollRows: 8,
        danmakuTopRows: 1,
        danmakuBottomRows: 6,
        danmakuBlockTop: true,
        danmakuBlockBottom: true,
        danmakuBlockWords: '广告,刷屏',
        danmakuLimitCount: true,
        danmakuMaxCount: 1000,
        danmakuSpeed: 1.5,
        danmakuFontSize: 0.75,
        danmakuOpacity: 0.5,
      );

      final s = notifier.state;
      expect(s.danmakuDefaultOn, isFalse);
      expect(s.danmakuScrollRows, 8);
      expect(s.danmakuTopRows, 1);
      expect(s.danmakuBottomRows, 6);
      expect(s.danmakuBlockTop, isTrue);
      expect(s.danmakuBlockBottom, isTrue);
      expect(s.danmakuBlockWords, '广告,刷屏');
      expect(s.danmakuLimitCount, isTrue);
      expect(s.danmakuMaxCount, 1000);
      expect(s.danmakuSpeed, 1.5);
      expect(s.danmakuFontSize, 0.75);
      expect(s.danmakuOpacity, 0.5);
      expect(notifier.persistCount, 1);
    });

    test('未传字段保留原值', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(danmakuApiUrl: 'http://a.b', danmakuSpeed: 1.2),
      );
      await notifier.update(danmakuScrollRows: 7);

      expect(notifier.state.danmakuApiUrl, 'http://a.b');
      expect(notifier.state.danmakuSpeed, 1.2);
      expect(notifier.state.danmakuScrollRows, 7);
    });

    test('传空串清空 API 地址（恢复默认）', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(danmakuApiUrl: 'http://a.b'),
      );
      await notifier.update(danmakuApiUrl: '');
      expect(notifier.state.danmakuApiUrl, '');
    });

    test('恢复默认：批量写回默认值', () async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(
          danmakuDefaultOn: false,
          danmakuApiUrl: 'http://x',
          danmakuScrollRows: 9,
          danmakuOpacity: 0.3,
        ),
      );
      await notifier.update(
        danmakuDefaultOn: true,
        danmakuApiUrl: '',
        danmakuScrollRows: 4,
        danmakuTopRows: 4,
        danmakuBottomRows: 4,
        danmakuBlockTop: false,
        danmakuBlockBottom: false,
        danmakuBlockWords: '',
        danmakuLimitCount: false,
        danmakuMaxCount: 500,
        danmakuSpeed: 1.0,
        danmakuFontSize: 1.0,
        danmakuOpacity: 1.0,
      );
      final s = notifier.state;
      expect(s.danmakuDefaultOn, isTrue);
      expect(s.danmakuApiUrl, '');
      expect(s.danmakuScrollRows, 4);
      expect(s.danmakuTopRows, 4);
      expect(s.danmakuBottomRows, 4);
      expect(s.danmakuBlockTop, isFalse);
      expect(s.danmakuBlockBottom, isFalse);
      expect(s.danmakuBlockWords, '');
      expect(s.danmakuLimitCount, isFalse);
      expect(s.danmakuMaxCount, 500);
      expect(s.danmakuSpeed, 1.0);
      expect(s.danmakuFontSize, 1.0);
      expect(s.danmakuOpacity, 1.0);
      expect(notifier.persistCount, 1);
    });
  });
}

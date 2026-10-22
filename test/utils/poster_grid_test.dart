import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/utils/poster_grid.dart';

void main() {
  group('posterGridColumns', () {
    test('自动模式：手机 4 列、宽屏按 180、TV 按 120', () {
      expect(posterGridColumns(width: 400, tvMode: false), 4);
      expect(posterGridColumns(width: 1000, tvMode: false), 5);
      expect(posterGridColumns(width: 960, tvMode: true), 8);
    });

    test('指定列数优先，但受每列最小 80 逻辑px 与平台上限约束', () {
      expect(
        posterGridColumns(width: 1000, tvMode: false, columns: 6),
        6,
      );
      expect(
        posterGridColumns(width: 400, tvMode: false, columns: 6),
        5,
        reason: '400 / 80 = 5，放不下 6 列',
      );
      expect(
        posterGridColumns(width: 1920, tvMode: true, columns: 99),
        14,
        reason: 'TV 上限 14 列',
      );
      expect(
        posterGridColumns(width: 1920, tvMode: false, columns: 99),
        12,
        reason: '非 TV 宽屏上限 12 列',
      );
    });

    test('极窄宽度仍至少 1 列', () {
      expect(posterGridColumns(width: 60, tvMode: false), 1);
    });
  });
}

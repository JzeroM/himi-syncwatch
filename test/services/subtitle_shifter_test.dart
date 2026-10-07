import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/subtitle_shifter.dart';

void main() {
  group('SubtitleShifter.SRT', () {
    test('正值延后显示', () {
      const src = '1\n00:00:01,000 --> 00:00:04,000\n你好\n';
      final out = SubtitleShifter.shiftSrt(src, 800);
      expect(out, contains('00:00:01,800 --> 00:00:04,800'));
      expect(out, contains('1\n'), reason: '索引号保留');
      expect(out, contains('你好'), reason: '文本保留');
    });

    test('负值提前，早于 0 钳到 0', () {
      const src = '00:00:01,000 --> 00:00:04,000';
      expect(
        SubtitleShifter.shiftSrt(src, -500),
        '00:00:00,500 --> 00:00:03,500',
      );
      expect(
        SubtitleShifter.shiftSrt(src, -2000),
        '00:00:00,000 --> 00:00:02,000',
        reason: '负时间钳到 0',
      );
    });

    test('进位：分秒边界跨位', () {
      expect(
        SubtitleShifter.shiftSrt('00:00:59,500 --> 00:01:00,250', 600),
        '00:01:00,100 --> 00:01:00,850',
      );
    });

    test('坐标后缀与毫秒 . 分隔原样兼容（VTT）', () {
      const src = '00:00:01.000 --> 00:00:02.000 X1:40 line:90%';
      final out = SubtitleShifter.shiftSrt(src, 1000);
      expect(out, '00:00:02.000 --> 00:00:03.000 X1:40 line:90%');
    });

    test('delta=0 恒等返回', () {
      const src = '00:00:01,000 --> 00:00:04,000';
      expect(SubtitleShifter.shiftSrt(src, 0), src);
    });
  });

  group('SubtitleShifter.ASS', () {
    test('Dialogue 行起止字段偏移，文本逗号保留', () {
      const src = '[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          'Dialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,你好, 世界\n';
      final out = SubtitleShifter.shiftAss(src, 500);
      expect(out, contains('Dialogue: 0,0:00:01.50,0:00:04.50,'));
      expect(out, contains(',你好, 世界'), reason: '文本内逗号原样');
      expect(out, contains('Format: Layer'), reason: '非 Dialogue 行不动');
      expect(out, contains('[Events]'), reason: '头保留');
    });

    test('负值提前，钳到 0；厘秒进位', () {
      expect(
        SubtitleShifter.shiftAss('Dialogue: 0,0:00:00.50,0:00:02.00,X', -800),
        'Dialogue: 0,0:00:00.00,0:00:01.20,X',
      );
      expect(
        SubtitleShifter.shiftAss('Dialogue: 0,0:00:59.95,0:01:00.00,X', 100),
        'Dialogue: 0,0:01:00.05,0:01:00.10,X',
      );
    });

    test('时间字段格式不匹配时原样保留', () {
      const src = 'Dialogue: 0,garbage,end,Style,,0,0,0,,文本';
      expect(SubtitleShifter.shiftAss(src, 1000), src);
    });
  });

  group('SubtitleShifter.shift 分派', () {
    test('含 Dialogue 视为 ASS', () {
      expect(SubtitleShifter.looksLikeAss('Dialogue: 0,0:00:01.00,…'), isTrue);
      expect(SubtitleShifter.looksLikeAss('[Script Info]'), isFalse);
      expect(SubtitleShifter.looksLikeAss('Dialogue:'), isTrue);
    });

    test('SRT 文本走 SRT 分支', () {
      final out = SubtitleShifter.shift('00:00:01,000 --> 00:00:02,000', 500);
      expect(out, '00:00:01,500 --> 00:00:02,500');
    });

    test('delta=0 直接恒等', () {
      const src = '00:00:01,000 --> 00:00:02,000';
      expect(SubtitleShifter.shift(src, 0), src);
    });
  });
}

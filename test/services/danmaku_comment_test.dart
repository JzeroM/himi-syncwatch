import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';

void main() {
  group('DanmakuParser.parseComment', () {
    test('标准条目：时间/模式/颜色/文本', () {
      final c = DanmakuParser.parseComment({
        'p': '12.5,1,25,16777215',
        'm': '前方高能',
      });
      expect(c, isNotNull);
      expect(c!.time, 12.5);
      expect(c.mode, DanmakuMode.scroll);
      expect(c.color, 0xFFFFFFFF);
      expect(c.text, '前方高能');
    });

    test('模式 4=底部 5=顶部 其余=滚动', () {
      expect(
        DanmakuParser.parseComment({'p': '1,4,25,1', 'm': 'a'})!.mode,
        DanmakuMode.bottom,
      );
      expect(
        DanmakuParser.parseComment({'p': '1,5,25,1', 'm': 'b'})!.mode,
        DanmakuMode.top,
      );
      expect(
        DanmakuParser.parseComment({'p': '1,6,25,1', 'm': 'c'})!.mode,
        DanmakuMode.scroll,
        reason: '逆向滚动按滚动处理',
      );
      expect(
        DanmakuParser.parseComment({'p': '1,8,25,1', 'm': 'd'})!.mode,
        DanmakuMode.scroll,
        reason: '代码弹幕按滚动处理',
      );
    });

    test('十进制颜色补齐不透明 alpha', () {
      // 0xFF0000 红（无 alpha 位）
      expect(
        DanmakuParser.parseComment({'p': '0,1,25,16711680', 'm': '红'})!.color,
        0xFFFF0000,
      );
      // 已带 alpha 位也不影响低 24 位
      expect(
        DanmakuParser.parseComment({'p': '0,1,25,-1', 'm': 'x'})!.color,
        0xFFFFFFFF,
        reason: '负数按补码位运算取低 24 位',
      );
    });

    test('坏条目返回 null：缺 p / p 字段不足 / 非法数字 / 空文本', () {
      expect(DanmakuParser.parseComment({'m': '无p'}), isNull);
      expect(DanmakuParser.parseComment({'p': '1,1,25', 'm': 'x'}), isNull);
      expect(DanmakuParser.parseComment({'p': 'x,1,25,1', 'm': 'y'}), isNull);
      expect(DanmakuParser.parseComment({'p': '1,q,25,1', 'm': 'y'}), isNull);
      expect(DanmakuParser.parseComment({'p': '1,1,25,abc', 'm': 'y'}), isNull);
      expect(DanmakuParser.parseComment({'p': '1,1,25,1', 'm': ''}), isNull);
      expect(DanmakuParser.parseComment({'p': 1, 'm': 'y'}), isNull);
    });

    test('负时间按非法条目跳过', () {
      expect(DanmakuParser.parseComment({'p': '-1,1,25,1', 'm': 'x'}), isNull);
    });
  });

  group('DanmakuParser.parseComments / parseResponse', () {
    test('混合好坏条目只保留合法项', () {
      final list = DanmakuParser.parseComments([
        {'p': '1.0,1,25,1', 'm': 'ok1'},
        {'p': 'bad', 'm': 'skip'},
        {'p': '2.0,5,25,2', 'm': 'ok2'},
        42,
        null,
      ]);
      expect(list.length, 2);
      expect(list[0].text, 'ok1');
      expect(list[1].mode, DanmakuMode.top);
    });

    test('非 List 输入返回空', () {
      expect(DanmakuParser.parseComments('x'), isEmpty);
      expect(DanmakuParser.parseComments(null), isEmpty);
    });

    test('parseResponse 取 comments 字段，结构异常返回空', () {
      final list = DanmakuParser.parseResponse({
        'count': 1,
        'comments': [
          {'p': '0,1,25,1', 'm': 'hello'},
        ],
      });
      expect(list.single.text, 'hello');
      expect(DanmakuParser.parseResponse({'success': false}), isEmpty);
      expect(DanmakuParser.parseResponse(null), isEmpty);
    });
  });
}

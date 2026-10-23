import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_comment.dart';

void main() {
  group('PlayerScreen.isBitmapSubtitleCodec（位图字幕判定）', () {
    test('PGS/VobSub/DVB 判定为位图', () {
      for (final c in const [
        'pgssub',
        'PGS',
        'hdmv_pgs_subtitle',
        'dvdsub',
        'dvbsub',
        'vobsub',
        'dvd_subtitle',
        'dvb_subtitle',
      ]) {
        expect(PlayerScreen.isBitmapSubtitleCodec(c), isTrue, reason: c);
      }
    });

    test('文本字幕不判为位图', () {
      for (final c in const [
        'subrip',
        'srt',
        'ass',
        'ssa',
        'mov_text',
        'webvtt',
        '',
      ]) {
        expect(PlayerScreen.isBitmapSubtitleCodec(c), isFalse, reason: c);
      }
    });
  });

  group('PlayerScreen.subtitleStyleWrites（PGS 位置修复）', () {
    test('PGS 强制底部对齐后再写位置，大小保持可调', () {
      final writes = PlayerScreen.subtitleStyleWrites(
        forceBitmapBottom: true,
        scale: 1.2,
        marginY: 80,
      );

      expect(writes.map((e) => e.name), [
        'subtitle.alignment.y',
        'subtitle.scale',
        'subtitle.margin.y',
      ]);
      expect(writes[0].value, '1');
      expect(writes[1].value, '1.20');
      expect(writes[2].value, '80');
    });

    test('文本/ASS 不强制改垂直对齐', () {
      final writes = PlayerScreen.subtitleStyleWrites(
        forceBitmapBottom: false,
        scale: 1.0,
        marginY: 22,
      );

      expect(writes.map((e) => e.name), [
        'subtitle.scale',
        'subtitle.margin.y',
      ]);
    });
  });

  group('PlayerScreen.danmakuJsonFor（Erika 原生弹幕 JSON）', () {
    test('映射 time/content/type/color', () {
      final json = PlayerScreen.danmakuJsonFor(const [
        DanmakuComment(
            time: 1.5, mode: DanmakuMode.scroll, color: 0xFFFF0000, text: 'hi'),
        DanmakuComment(
            time: 2.0, mode: DanmakuMode.top, color: 0xFF00FF00, text: 'top'),
        DanmakuComment(
            time: 3.0,
            mode: DanmakuMode.bottom,
            color: 0xFF0000FF,
            text: 'bot'),
      ]);
      final list = jsonDecode(json) as List;
      expect(list.length, 3);
      expect(list[0],
          {'time': 1.5, 'content': 'hi', 'type': 'scroll', 'color': '#ff0000'});
      expect(list[1]['type'], 'top');
      expect(list[1]['color'], '#00ff00');
      expect(list[2]['type'], 'bottom');
      expect(list[2]['color'], '#0000ff');
    });

    test('空列表 → []', () {
      expect(PlayerScreen.danmakuJsonFor(const []), '[]');
    });
  });
}

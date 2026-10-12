import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';

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
      for (final c in const ['subrip', 'srt', 'ass', 'ssa', 'mov_text', 'webvtt', '']) {
        expect(PlayerScreen.isBitmapSubtitleCodec(c), isFalse, reason: c);
      }
    });
  });
}

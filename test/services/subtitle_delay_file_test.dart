import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/subtitle_delay_file.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('himi_sub_delay_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('SRT 偏移后写 .srt 临时文件', () async {
    const src = '1\n00:00:01,000 --> 00:00:04,000\n你好\n';
    final path = await SubtitleDelayFile.write(
      text: src,
      delayMs: 800,
      dir: dir,
      now: DateTime(2026, 1, 1, 12),
    );

    expect(path.endsWith('.srt'), isTrue);
    expect(File(path).existsSync(), isTrue);
    final out = await File(path).readAsString();
    expect(out, contains('00:00:01,800 --> 00:00:04,800'));
    expect(out, contains('你好'), reason: '文本保留');
  });

  test('ASS 内容写 .ass 临时文件并偏移 Dialogue 行', () async {
    const src = '[Events]\nDialogue: 0,0:00:01.00,0:00:04.00,D,,0,0,0,,文本\n';
    final path = await SubtitleDelayFile.write(
      text: src,
      delayMs: -500,
      dir: dir,
      now: DateTime(2026, 1, 1, 12),
    );

    expect(path.endsWith('.ass'), isTrue);
    final out = await File(path).readAsString();
    expect(out, contains('Dialogue: 0,0:00:00.50,0:00:03.50,D,,'));
  });

  test('不同时间戳生成不同文件名（不相互覆盖）', () async {
    final a = await SubtitleDelayFile.write(
        text: 'x', delayMs: 1, dir: dir, now: DateTime(2026, 1, 1, 12));
    final b = await SubtitleDelayFile.write(
        text: 'x', delayMs: 1, dir: dir, now: DateTime(2026, 1, 1, 12, 0, 1));
    expect(a, isNot(b));
    expect(File(a).existsSync(), isTrue);
    expect(File(b).existsSync(), isTrue);
  });
}

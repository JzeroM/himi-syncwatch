import 'dart:io';

import 'package:himi_syncwatch/services/subtitle_shifter.dart';

/// 字幕延迟：按偏移生成可外挂的临时字幕文件（mdk `setMedia` 用）。
class SubtitleDelayFile {
  const SubtitleDelayFile._();

  /// 偏移 [text] 后写入 [dir]，返回文件路径；扩展名按内容判定
  ///（ASS/SSA → `.ass`，否则 `.srt`）；文件名带时间戳防相互覆盖。
  static Future<String> write({
    required String text,
    required int delayMs,
    required Directory dir,
    DateTime? now,
  }) async {
    final shifted = SubtitleShifter.shift(text, delayMs);
    final ext = SubtitleShifter.looksLikeAss(text) ? 'ass' : 'srt';
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final file = File(
      '${dir.path}${Platform.pathSeparator}himi_sub_shift_$ts.$ext',
    );
    await file.writeAsString(shifted);
    return file.path;
  }
}

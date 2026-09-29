import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/codec_mime_map.dart';

void main() {
  group('视频 MIME 映射', () {
    test('当前问题媒体的编码名可映射', () {
      expect(CodecMimeMap.video('hevc'), 'video/hevc');
      expect(CodecMimeMap.video('avc'), 'video/avc');
    });

    test('大小写与空白不敏感', () {
      expect(CodecMimeMap.video('HEVC'), 'video/hevc');
      expect(CodecMimeMap.video('  h265 '), 'video/hevc');
    });

    test('未命中返回 null 而不是猜测', () {
      expect(CodecMimeMap.video('nosuchcodec'), isNull);
      expect(CodecMimeMap.video(null), isNull);
      expect(CodecMimeMap.video(''), isNull);
      expect(CodecMimeMap.video('   '), isNull);
    });
  });

  group('音频 MIME 映射', () {
    test('E-AC3 可映射', () {
      expect(CodecMimeMap.audio('eac3'), 'audio/eac3');
    });

    test('Dolby Atmos 走 ac4', () {
      expect(CodecMimeMap.audio('atmos'), 'audio/ac4');
    });

    test('常见音频编码', () {
      expect(CodecMimeMap.audio('aac'), 'audio/mp4a-latm');
      expect(CodecMimeMap.audio('truehd'), 'audio/truehd');
      expect(CodecMimeMap.audio('ac3'), 'audio/ac3');
      expect(CodecMimeMap.audio('flac'), 'audio/flac');
    });

    test('未命中返回 null', () {
      expect(CodecMimeMap.audio('unknown'), isNull);
      expect(CodecMimeMap.audio(null), isNull);
    });
  });

  test('同名 codec 在视频与音频表互不串味', () {
    // mpeg 在两边都存在但 MIME 不同，映射表需各自独立
    expect(CodecMimeMap.video('mpeg2'), 'video/mpeg2');
    expect(CodecMimeMap.audio('mpeg2'), isNull);
  });
}

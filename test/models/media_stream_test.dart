import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';

void main() {
  group('MediaStream toJson/fromJson', () {
    test('字幕流序列化/反序列化', () {
      final stream = MediaStream(
        type: 'Subtitle',
        codec: 'ass',
        language: 'chi',
        displayTitle: 'Chinese (ASS)',
        displayLanguage: 'Chinese',
        index: 2,
        isForced: false,
        isExternal: false,
        subtitleLocationType: 'InternalStream',
      );

      final json = stream.toJson();
      expect(json['Type'], equals('Subtitle'));
      expect(json['Codec'], equals('ass'));
      expect(json['Language'], equals('chi'));
      expect(json['DisplayTitle'], equals('Chinese (ASS)'));
      expect(json['DisplayLanguage'], equals('Chinese'));
      expect(json['Index'], equals(2));
      expect(json['IsForced'], isFalse);
      expect(json['IsExternal'], isFalse);
      expect(json['SubtitleLocationType'], equals('InternalStream'));

      final restored = MediaStream.fromJson(json);
      expect(restored.type, equals('Subtitle'));
      expect(restored.codec, equals('ass'));
      expect(restored.language, equals('chi'));
      expect(restored.displayTitle, equals('Chinese (ASS)'));
      expect(restored.index, equals(2));
      expect(restored.isExternal, isFalse);
    });

    test('音轨流序列化/反序列化', () {
      final stream = MediaStream(
        type: 'Audio',
        codec: 'aac',
        language: 'jpn',
        title: 'Japanese Audio',
        channels: 6,
        channelLayout: '5.1',
        isDefault: true,
        index: 1,
        bitRate: 192000,
        sampleRate: 48000,
      );

      final json = stream.toJson();
      expect(json['Type'], equals('Audio'));
      expect(json['Codec'], equals('aac'));
      expect(json['Language'], equals('jpn'));
      expect(json['Title'], equals('Japanese Audio'));
      expect(json['Channels'], equals(6));
      expect(json['ChannelLayout'], equals('5.1'));
      expect(json['IsDefault'], isTrue);
      expect(json['Index'], equals(1));
      expect(json['BitRate'], equals(192000));
      expect(json['SampleRate'], equals(48000));

      final restored = MediaStream.fromJson(json);
      expect(restored.type, equals('Audio'));
      expect(restored.codec, equals('aac'));
      expect(restored.language, equals('jpn'));
      expect(restored.channels, equals(6));
      expect(restored.channelLayout, equals('5.1'));
      expect(restored.isDefault, isTrue);
      expect(restored.index, equals(1));
      expect(restored.bitRate, equals(192000));
    });

    test('null 可选字段不出现在 JSON 中', () {
      final stream = MediaStream(
        type: 'Subtitle',
        codec: 'srt',
        index: 0,
      );

      final json = stream.toJson();
      expect(json.containsKey('Language'), isFalse);
      expect(json.containsKey('Title'), isFalse);
      expect(json.containsKey('Width'), isFalse);
      expect(json.containsKey('DisplayTitle'), isFalse);
      expect(json.containsKey('DisplayLanguage'), isFalse);
      expect(json.containsKey('ChannelLayout'), isFalse);
    });
  });

  group('roomInfo 消息 - 字幕/音轨字段', () {
    test('roomInfo 包含字幕/音轨数据时可正确解析', () {
      final subtitleStreams = [
        {
          'Type': 'Subtitle',
          'Codec': 'ass',
          'Language': 'chi',
          'DisplayTitle': 'Chinese (ASS)',
          'Index': 2,
          'IsForced': false,
          'IsExternal': false,
        },
        {
          'Type': 'Subtitle',
          'Codec': 'srt',
          'Language': 'eng',
          'DisplayTitle': 'English (SRT)',
          'Index': 3,
          'IsForced': false,
          'IsExternal': false,
        },
      ];

      final audioStreams = [
        {
          'Type': 'Audio',
          'Codec': 'aac',
          'Language': 'jpn',
          'Channels': 6,
          'ChannelLayout': '5.1',
          'IsDefault': true,
          'Index': 1,
        },
      ];

      final message = {
        'type': 'roomInfo',
        'userId': 'host_user',
        'episodeIds': ['ep1'],
        'subtitleStreams': subtitleStreams,
        'audioStreams': audioStreams,
        'defaultAudioStreamIndex': 1,
      };

      final parsedSubtitles = (message['subtitleStreams'] as List)
          .whereType<Map<String, dynamic>>()
          .map((s) => MediaStream.fromJson(s))
          .toList();
      final parsedAudios = (message['audioStreams'] as List)
          .whereType<Map<String, dynamic>>()
          .map((s) => MediaStream.fromJson(s))
          .toList();

      expect(parsedSubtitles.length, equals(2));
      expect(parsedSubtitles[0].type, equals('Subtitle'));
      expect(parsedSubtitles[0].codec, equals('ass'));
      expect(parsedSubtitles[0].language, equals('chi'));
      expect(parsedSubtitles[1].codec, equals('srt'));
      expect(parsedSubtitles[1].language, equals('eng'));

      expect(parsedAudios.length, equals(1));
      expect(parsedAudios[0].type, equals('Audio'));
      expect(parsedAudios[0].codec, equals('aac'));
      expect(parsedAudios[0].channels, equals(6));
      expect(parsedAudios[0].channelLayout, equals('5.1'));

      expect(message['defaultAudioStreamIndex'], equals(1));
    });

    test('roomInfo 无字幕/音轨数据时默认为空列表', () {
      final message = {
        'type': 'roomInfo',
        'userId': 'host_user',
        'episodeIds': ['ep1'],
      };

      final subtitleStreamsRaw = message['subtitleStreams'];
      final audioStreamsRaw = message['audioStreams'];

      expect(subtitleStreamsRaw, isNull);
      expect(audioStreamsRaw, isNull);

      final parsedSubtitles = subtitleStreamsRaw is List
          ? subtitleStreamsRaw
              .whereType<Map<String, dynamic>>()
              .map((s) => MediaStream.fromJson(s))
              .toList()
          : <MediaStream>[];
      final parsedAudios = audioStreamsRaw is List
          ? audioStreamsRaw
              .whereType<Map<String, dynamic>>()
              .map((s) => MediaStream.fromJson(s))
              .toList()
          : <MediaStream>[];

      expect(parsedSubtitles, isEmpty);
      expect(parsedAudios, isEmpty);
    });
  });

  group('MediaStream HDR/DV 检测', () {
    test('isDolbyVision', () {
      final dv = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
      );
      expect(dv.isDolbyVision, isTrue);

      final normal = MediaStream(type: 'Video', codec: 'hevc');
      expect(normal.isDolbyVision, isFalse);

      final hdr10 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'HDR',
      );
      expect(hdr10.isDolbyVision, isFalse);
    });

    test('isHDR', () {
      final dv = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
      );
      expect(dv.isHDR, isTrue);

      final hdr10 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'HDR',
      );
      expect(hdr10.isHDR, isTrue);

      final pq = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'PQ',
      );
      expect(pq.isHDR, isTrue);

      final hlg = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'HLG',
      );
      expect(hlg.isHDR, isFalse); // HLG 不是 isHDR

      final sdr = MediaStream(type: 'Video', codec: 'h264');
      expect(sdr.isHDR, isFalse);
    });

    test('hdrLabel', () {
      final dv = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
      );
      expect(dv.hdrLabel, equals('Dolby Vision'));

      final dvP5 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile50',
      );
      expect(dvP5.hdrLabel, equals('Dolby Vision P5'));

      final dvP7 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile76',
      );
      expect(dvP7.hdrLabel, equals('Dolby Vision P7'));

      final dvP8 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile81',
      );
      expect(dvP8.hdrLabel, equals('Dolby Vision P8'));

      final dvP84 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile84',
      );
      expect(dvP84.hdrLabel, equals('Dolby Vision P8.4'));

      final hdr10 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'HDR',
      );
      expect(hdr10.hdrLabel, equals('HDR10'));

      final hlg = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'HLG',
      );
      expect(hlg.hdrLabel, equals('HLG'));

      final sdr = MediaStream(type: 'Video', codec: 'h264');
      expect(sdr.hdrLabel, equals('SDR'));
    });

    test('DV + HDR 组合', () {
      // DV 内容通常也有 videoRange='PQ'
      final dvWithPQ = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        videoRange: 'PQ',
      );
      expect(dvWithPQ.isDolbyVision, isTrue);
      expect(dvWithPQ.isHDR, isTrue);
      expect(dvWithPQ.hdrLabel, equals('Dolby Vision')); // DV 优先于 PQ
    });

    test('isDolbyVisionProfile5', () {
      final dvP5 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile50',
      );
      expect(dvP5.isDolbyVisionProfile5, isTrue);

      final dvP7 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile76',
      );
      expect(dvP7.isDolbyVisionProfile5, isFalse);

      final dvP8 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile81',
      );
      expect(dvP8.isDolbyVisionProfile5, isFalse);

      final dvP84 = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
        extendedVideoSubType: 'DoviProfile84',
      );
      expect(dvP84.isDolbyVisionProfile5, isFalse);

      final dvNoSubType = MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: 'DolbyVision',
      );
      expect(dvNoSubType.isDolbyVisionProfile5, isFalse);

      final nonDV = MediaStream(type: 'Video', codec: 'hevc');
      expect(nonDV.isDolbyVisionProfile5, isFalse);
    });
  });

  group('MediaStream HDR 分层判定（1.1.187：VideoRangeType/色彩字段）', () {
    test('VideoRange 错标 SDR + VideoRangeType=HDR10 → isHDR/HDR10', () {
      // strm/重封装项典型形态：VideoRange 不可靠，VideoRangeType 准确
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'SDR',
        videoRangeType: 'HDR10',
      );
      expect(s.isHDR, isTrue);
      expect(s.hdrLabel, equals('HDR10'));
    });

    test('仅 TransferCharacteristics=smpte2084 → HDR10 兜底推断', () {
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        transferCharacteristics: 'smpte2084',
      );
      expect(s.isHDR, isTrue);
      expect(s.hdrLabel, equals('HDR10'));
    });

    test('VideoRangeType=DOVI（无 ExtendedVideoType）→ DV', () {
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRangeType: 'DOVI',
      );
      expect(s.isDolbyVision, isTrue);
      expect(s.isHDR, isTrue);
      expect(s.hdrLabel, equals('Dolby Vision'));
    });

    test('VideoRangeType=HLG → 标签 HLG，isHDR 保持 false（历史语义）', () {
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'SDR',
        videoRangeType: 'HLG',
      );
      expect(s.isHDR, isFalse);
      expect(s.hdrLabel, equals('HLG'));
    });

    test('传输特性 arib-std-b67 → HLG 标签', () {
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        transferCharacteristics: 'arib-std-b67',
      );
      expect(s.isHDR, isFalse);
      expect(s.hdrLabel, equals('HLG'));
    });

    test('VideoRange=PQ → 标签 HDR10（原误落 SDR 的修复）', () {
      final s = MediaStream(
        type: 'Video',
        codec: 'hevc',
        videoRange: 'PQ',
      );
      expect(s.hdrLabel, equals('HDR10'));
    });

    test('SDR 全空 → 非 HDR，标签 SDR', () {
      final s = MediaStream(type: 'Video', codec: 'h264');
      expect(s.isHDR, isFalse);
      expect(s.hdrLabel, equals('SDR'));
    });

    test('fromJson 解析新字段 + toJson 往返', () {
      final s = MediaStream.fromJson(const {
        'Type': 'Video',
        'Codec': 'hevc',
        'VideoRange': 'SDR',
        'VideoRangeType': 'HDR10',
        'ColorPrimaries': 'bt2020',
        'ColorSpace': 'bt2020nc',
        'TransferCharacteristics': 'smpte2084',
      });
      expect(s.videoRangeType, 'HDR10');
      expect(s.colorPrimaries, 'bt2020');
      expect(s.colorSpace, 'bt2020nc');
      expect(s.transferCharacteristics, 'smpte2084');
      expect(s.isHDR, isTrue);
      expect(s.hdrLabel, 'HDR10');

      final json = s.toJson();
      expect(json['VideoRangeType'], 'HDR10');
      expect(json['ColorPrimaries'], 'bt2020');
      expect(json['ColorSpace'], 'bt2020nc');
      expect(json['TransferCharacteristics'], 'smpte2084');
      final round = MediaStream.fromJson(json);
      expect(round.videoRangeType, 'HDR10');
      expect(round.isHDR, isTrue);
    });
  });
}

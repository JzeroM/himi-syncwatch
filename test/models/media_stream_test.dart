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
}

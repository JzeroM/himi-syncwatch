import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/version_preference.dart';

MediaSource _src(
  String id, {
  int? bitrate,
  bool hdr = false,
  bool dv = false,
}) {
  return MediaSource(
    id: id,
    name: id,
    bitrate: bitrate,
    mediaStreams: [
      MediaStream(
        type: 'Video',
        codec: 'hevc',
        extendedVideoType: dv ? 'DolbyVision' : null,
        videoRangeType: hdr ? 'HDR10' : (dv ? 'DOVI' : 'SDR'),
      ),
    ],
  );
}

void main() {
  group('VersionPreference 持久化', () {
    test('encode/decode 往返', () {
      final order = [
        VersionPreference.dolbyVision,
        VersionPreference.highBitrate,
        VersionPreference.sdr,
      ];
      final csv = VersionPreference.encode(order);
      final back = VersionPreference.decode(csv);
      expect(back.take(order.length).toList(), order);
    });

    test('空/非法 → 默认顺序且补齐全部维度', () {
      expect(VersionPreference.decode(''), VersionPreference.defaults);
      expect(VersionPreference.decode('bogus,x'), VersionPreference.defaults);
      expect(VersionPreference.decode('sdr').first, VersionPreference.sdr);
      expect(
        VersionPreference.decode('sdr').toSet(),
        VersionPreference.defaults.toSet(),
      );
    });
  });

  group('sortSourcesByPreference', () {
    test('高码率优先：码率高在前', () {
      final sources = [
        _src('a', bitrate: 1000),
        _src('c', bitrate: 3000),
        _src('b', bitrate: 2000),
      ];
      final sorted = sortSourcesByPreference(
          sources, [VersionPreference.highBitrate]);
      expect(sorted.map((s) => s.id), ['c', 'b', 'a']);
    });

    test('低码率优先：码率低在前', () {
      final sources = [
        _src('a', bitrate: 1000),
        _src('c', bitrate: 3000),
        _src('b', bitrate: 2000),
      ];
      final sorted = sortSourcesByPreference(
          sources, [VersionPreference.lowBitrate]);
      expect(sorted.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('HDR优先：HDR/DV 在前（同级保持服务端顺序）', () {
      final sources = [
        _src('sdr'),
        _src('hdr', hdr: true),
        _src('dv', dv: true),
      ];
      final sorted =
          sortSourcesByPreference(sources, [VersionPreference.hdr]);
      expect(sorted.first.id, anyOf('hdr', 'dv'));
      expect(sorted.last.id, 'sdr');
    });

    test('杜比优先：DV 最前', () {
      final sources = [
        _src('sdr'),
        _src('hdr', hdr: true),
        _src('dv', dv: true),
      ];
      final sorted = sortSourcesByPreference(
          sources, [VersionPreference.dolbyVision]);
      expect(sorted.first.id, 'dv');
    });

    test('由服务决定：保持原始（服务端）顺序', () {
      final sources = [_src('b'), _src('a'), _src('c')];
      final sorted = sortSourcesByPreference(
          sources, [VersionPreference.serverDefault]);
      expect(sorted.map((s) => s.id), ['b', 'a', 'c']);
    });

    test('多维度：首维度定序，次维度破平', () {
      final sources = [
        _src('hdrLow', bitrate: 1000, hdr: true),
        _src('sdrHigh', bitrate: 5000),
        _src('hdrHigh', bitrate: 4000, hdr: true),
      ];
      final sorted = sortSourcesByPreference(sources, [
        VersionPreference.hdr,
        VersionPreference.highBitrate,
      ]);
      expect(sorted.map((s) => s.id), ['hdrHigh', 'hdrLow', 'sdrHigh']);
    });

    test('不修改原列表', () {
      final sources = [_src('a', bitrate: 1), _src('b', bitrate: 2)];
      sortSourcesByPreference(sources, [VersionPreference.highBitrate]);
      expect(sources.map((s) => s.id), ['a', 'b']);
    });
  });

  group('preferredSource', () {
    test('返回偏好最高者；空列表 null', () {
      final sources = [_src('a', bitrate: 1), _src('b', bitrate: 9)];
      expect(
        preferredSource(sources, [VersionPreference.highBitrate])!.id,
        'b',
      );
      expect(preferredSource(const [], VersionPreference.defaults), isNull);
    });
  });
}

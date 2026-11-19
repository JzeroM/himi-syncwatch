import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/services/player/media_info_summary.dart';

void main() {
  group('① 徽章格式化（进度条上方胶囊行）', () {
    test('完整示例：[4K] [DV P5] [HEVC] [60.0 fps] [29Mbps] [20.50G]', () {
      expect(
        buildMediaBadges(
          width: 3840,
          height: 1606,
          doviProfile: 5,
          codecName: 'hevc',
          fps: 60,
          bitRateBps: 29000000,
          fileBytes: 22011707392, // 20.50 GiB
        ),
        ['4K', 'DV P5', 'HEVC', '60.0 fps', '29Mbps', '20.50G'],
      );
    });

    test('无值项省略（不显示空胶囊）', () {
      expect(buildMediaBadges(width: 1920, height: 800), ['1080P']);
      expect(buildMediaBadges(), isEmpty);
    });

    test('DV 优先；无 DV 时 HDR10/HLG 兜底徽章', () {
      expect(
          buildMediaBadges(doviProfile: 8, hdr10: true), ['DV P8']);
      expect(buildMediaBadges(hdr10: true), ['HDR10']);
      expect(buildMediaBadges(hlg: true), ['HLG']);
    });

    test('分辨率档位（4K/2K/1080P/720P）', () {
      expect(resolutionTier(3840, 2160), '4K');
      expect(resolutionTier(2560, 1440), '2K');
      expect(resolutionTier(1920, 1080), '1080P');
      expect(resolutionTier(1280, 720), '720P');
      expect(resolutionTier(0, 0), isNull);
    });

    test('编码短名映射', () {
      expect(codecShortName('hevc'), 'HEVC');
      expect(codecShortName('h265'), 'HEVC');
      expect(codecShortName('h264'), 'H.264');
      expect(codecShortName('av1'), 'AV1');
      expect(codecShortName('vp9'), 'VP9');
      expect(codecShortName(null), isNull);
    });

    test('码率/大小徽章', () {
      expect(formatMbpsBadge(29000000), '29Mbps');
      expect(formatMbpsBadge(9800000), '9.8Mbps');
      expect(formatSizeBadge(22011707392), '20.50G');
      expect(formatSizeBadge(512 << 20), '512M');
    });
  });

  group('② 详情面板四组（标签中文/值英文/每条一行/缺项省略）', () {
    test('全量源 → 文件/显示/视频/音频 四组齐全', () {
      final groups = buildMediaInfoGroups(const MediaInfoSource(
        fileName: 'movie.mkv',
        fileBytes: 15 << 30,
        container: 'mkv',
        cacheText: '80.75 MiB',
        vo: 'gpu-next',
        gpuContext: 'd3d11',
        refreshRateHz: 144,
        droppedDecoder: 0,
        droppedOutput: 4,
        videoCodecDesc: 'H.265 / HEVC',
        hwdec: 'd3d11va',
        fps: 60,
        width: 3840,
        height: 1606,
        pixelFormat: 'p010',
        colorMatrix: 'bt.2020-ncl',
        primaries: 'bt.2020',
        transfer: 'pq',
        hdr10Text: 'MaxCLL 1300 cd/m²',
        videoBitrateBps: 14691000,
        audioCodecDesc: 'AAC [LC]',
        channels: 2,
        sampleRateHz: 48000,
        audioBitrateBps: 124000,
      ));
      expect(groups.map((g) => g.title), ['文件', '显示', '视频', '音频']);
      // 每条信息独占一行：文件组 4 行、显示组 4 行、视频组 10 行、音频组 4 行
      expect(groups[0].rows.length, 4);
      expect(groups[1].rows.length, 4);
      expect(groups[2].rows.length, 10);
      expect(groups[3].rows.length, 4);
      expect(groups[0].rows.first.label, '文件名');
      expect(groups[0].rows.first.value, 'movie.mkv');
    });

    test('值缺失整行省略、整组无行整组省略', () {
      final groups = buildMediaInfoGroups(
          const MediaInfoSource(fileName: 'a.mkv', width: 1920, height: 800));
      expect(groups.map((g) => g.title), ['文件', '视频']);
      expect(groups[0].rows.length, 1, reason: '只有文件名一行');
      expect(groups[1].rows.length, 1, reason: '只有分辨率一行');
      expect(buildMediaInfoGroups(const MediaInfoSource()), isEmpty);
    });
  });

  group('③ 引擎 mediaInfo 抽取', () {
    test('AdapterMediaInfo → 静态源（视频/音频字段）', () {
      final info = const AdapterMediaInfo(
        video: [
          AdapterVideoStream(
            codec: 'hevc',
            width: 3840,
            height: 1606,
            doviProfile: 5,
            formatName: 'p010',
            bitRate: 29000000,
          ),
        ],
        audio: [
          AdapterAudioStream(
            codec: 'aac',
            channels: 2,
            sampleRate: 48000,
            bitRate: 124000,
          ),
        ],
      );
      final s = mediaInfoFromPlayer(info, fileName: 'movie.mkv');
      expect(s.fileName, 'movie.mkv');
      expect(s.videoCodecDesc, 'HEVC');
      expect(s.width, 3840);
      expect(s.height, 1606);
      expect(s.pixelFormat, 'p010');
      expect(s.videoBitrateBps, 29000000);
      expect(s.audioCodecDesc, 'AAC');
      expect(s.channels, 2);
      expect(s.sampleRateHz, 48000);
    });

    test('空 mediaInfo → 全空源（不抛异常）', () {
      final s = mediaInfoFromPlayer(null);
      expect(s.videoCodecDesc, isNull);
      expect(s.width, isNull);
    });
  });
}

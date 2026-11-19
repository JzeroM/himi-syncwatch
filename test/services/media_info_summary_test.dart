import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/player/media_info_summary.dart';

void main() {
  group('① 徽章格式化（六项全显不省略，Emby 主数据源）', () {
    test('完整示例（新顺序：范围→分辨率→编解码→帧率→码率→大小）', () {
      expect(
        buildMediaBadges(const MediaBadgeSource(
          width: 3840,
          height: 1606,
          dvProfileLabel: 'DoviProfile50',
          codecName: 'hevc',
          fps: 60,
          bitRateBps: 29000000,
          fileBytes: 22011707392, // 20.50 GiB
        )),
        ['DV P5', '4K', 'HEVC', '60.0 fps', '29Mbps', '20.50G'],
      );
    });

    test('六项全显不省略（极缺兜底 —，产品拍板）', () {
      expect(buildMediaBadges(const MediaBadgeSource()),
          ['SDR', '-', '-', '-', '-', '-']);
    });

    test('DV profile：Emby DoviProfile50/81 → DV P5 / DV P8.1', () {
      expect(
          videoRangeBadge(dvProfileLabel: 'DoviProfile50'), 'DV P5');
      expect(
          videoRangeBadge(dvProfileLabel: 'DoviProfile81'), 'DV P8.1');
      expect(videoRangeBadge(doviProfile: 5), 'DV P5',
          reason: '运行时 profile 兜底');
      expect(videoRangeBadge(hdr10: true), 'HDR10');
      expect(videoRangeBadge(hlg: true), 'HLG');
      expect(videoRangeBadge(), 'SDR');
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

  group('①b HDR10 亮度语义（修「值恒为 0」）', () {
    test('亮度范围优先；max-cll 仅 >0 显示；sig-peak 兜底', () {
      expect(
        hdr10LumaText(minLuma: 0.0001, maxLuma: 1000, maxCll: 1300, maxFall: 1080),
        'Mastering display: 0.0001 / 1000 cd/m²   MaxCLL: 1300 cd/m²   MaxFALL: 1080 cd/m²',
      );
      // max-cll 恒 0 是真机坑：不得显示 MaxCLL 0，改走 sig-peak
      expect(
        hdr10LumaText(minLuma: 0.0001, maxLuma: 1000, sigPeak: 10, maxCll: 0),
        'Mastering display: 0.0001 / 1000 cd/m²   峰值 1000 cd/m²',
      );
      expect(hdr10LumaText(), isNull);
    });
  });

  group('①c Emby 映射（详情页同源）', () {
    test('MediaItem → 徽章源/详情源（含音频三源字段）', () {
      final item = MediaItem(
        id: 'x',
        name: 'movie',
        type: 'Movie',
        mediaSources: [
          MediaSource(
            id: 's1',
            name: 'movie',
            container: 'mkv',
            size: 22011707392,
            bitrate: 29000000,
            width: 3840,
            height: 1606,
            defaultAudioStreamIndex: 1,
            mediaStreams: [
              MediaStream(
                type: 'Video',
                codec: 'hevc',
                width: 3840,
                height: 1606,
                bitRate: 29000000,
                frameRate: 60,
                profile: 'Main 10',
                extendedVideoSubType: 'DoviProfile50',
                videoRangeType: 'DOVI',
                index: 0,
              ),
              MediaStream(
                type: 'Audio',
                codec: 'aac',
                channels: 2,
                sampleRate: 48000,
                bitRate: 124000,
                profile: 'LC',
                index: 1,
              ),
            ],
          ),
        ],
      );
      final b = badgeSourceFromEmby(item);
      expect(buildMediaBadges(b),
          ['DV P5', '4K', 'HEVC', '60.0 fps', '29Mbps', '20.50G']);
      final s = mediaInfoFromEmby(item, fileName: 'movie.mkv');
      expect(s.container, 'mkv');
      expect(s.videoCodecDesc, 'HEVC [Main 10]');
      expect(s.audioCodecDesc, 'AAC [LC]');
      expect(s.channels, 2);
      expect(s.sampleRateHz, 48000);
      expect(s.audioBitrateBps, 124000);
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

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_matcher.dart';

void main() {
  group('DanmakuMatcher.basename / stripExtension', () {
    test('Windows 与 Unix 路径 basename', () {
      expect(
        DanmakuMatcher.basename(r'D:\Anime\葬送的芙莉莲 S01E01.mkv'),
        '葬送的芙莉莲 S01E01.mkv',
      );
      expect(DanmakuMatcher.basename('/mnt/nas/anime/ep01.mp4'), 'ep01.mp4');
      expect(DanmakuMatcher.basename('plain.mkv'), 'plain.mkv');
    });

    test('去扩展名只剥最后一段，多点文件名保留中段', () {
      expect(DanmakuMatcher.stripExtension('file.mkv'), 'file');
      expect(
        DanmakuMatcher.stripExtension('S01E01.2160p.WEB-DL.mkv'),
        'S01E01.2160p.WEB-DL',
      );
      expect(DanmakuMatcher.stripExtension('noext'), 'noext');
      expect(DanmakuMatcher.stripExtension('.hidden'), '.hidden',
          reason: '开头点不算扩展名');
    });
  });

  group('DanmakuMatcher.fromEpisode', () {
    test('剧集构造 `剧名.SxxExx`（零填充）', () {
      expect(
        DanmakuMatcher.fromEpisode(
          name: '第1话',
          seriesName: '葬送的芙莉莲',
          season: 1,
          number: 1,
        ),
        '葬送的芙莉莲.S01E01',
      );
      expect(
        DanmakuMatcher.fromEpisode(
          name: '第12话',
          seriesName: '某剧',
          season: 2,
          number: 12,
        ),
        '某剧.S02E12',
      );
    });

    test('非剧集（season/number ≤ 0）或缺剧名回退 name', () {
      expect(
        DanmakuMatcher.fromEpisode(name: '千与千寻', seriesName: '宫崎骏', season: 0),
        '千与千寻',
      );
      expect(
        DanmakuMatcher.fromEpisode(
            name: '第1话', seriesName: '', season: 1, number: 1),
        '第1话',
      );
      expect(
        DanmakuMatcher.fromEpisode(
            name: '第1话', seriesName: '剧名', season: 1, number: 0),
        '第1话',
      );
    });
  });

  group('DanmakuMatcher.resolve', () {
    test('Path 优先于剧集构造', () {
      expect(
        DanmakuMatcher.resolve(
          path: r'C:\tv\custom.name.s01e01.1080p.mkv',
          name: '第1话',
          seriesName: '某剧',
          season: 1,
          number: 1,
        ),
        'custom.name.s01e01.1080p',
      );
    });

    test('无 Path 时按剧集构造，再回退 name', () {
      expect(
        DanmakuMatcher.resolve(
          name: '第1话',
          seriesName: '某剧',
          season: 1,
          number: 1,
        ),
        '某剧.S01E01',
      );
      expect(DanmakuMatcher.resolve(name: '电影名'), '电影名');
    });

    test('全空返回 null；空 Path 视为缺失', () {
      expect(DanmakuMatcher.resolve(), isNull);
      expect(DanmakuMatcher.resolve(path: '   '), isNull);
      expect(DanmakuMatcher.fromPath(null), isNull);
    });
  });

  group('DanmakuMatcher.cleanTitle', () {
    test('剥离扩展名/SxxExx/年份/发布标签并归一空格', () {
      expect(
        DanmakuMatcher.cleanTitle(
          'Oppenheimer.2023.2160p.WEB-DL.H265.mkv',
        ),
        'Oppenheimer',
      );
      expect(
        DanmakuMatcher.cleanTitle('葬送的芙莉莲.S01E01.1080p.WEB-DL'),
        '葬送的芙莉莲',
      );
      expect(
        DanmakuMatcher.cleanTitle('流浪地球2 (2023)'),
        '流浪地球2',
      );
    });

    test('保留纯标题；不误删片名中的数字', () {
      expect(DanmakuMatcher.cleanTitle('流浪地球2'), '流浪地球2');
      expect(DanmakuMatcher.cleanTitle('1917'), '1917');
      expect(DanmakuMatcher.cleanTitle('  '), '');
    });
  });

  group('DanmakuMatcher.parseEpisodeNumber', () {
    test('中文「第N话/集/回/期」', () {
      expect(DanmakuMatcher.parseEpisodeNumber('第9话 序歌'), 9);
      expect(DanmakuMatcher.parseEpisodeNumber('【bilibili1】 第12集'), 12);
      expect(DanmakuMatcher.parseEpisodeNumber('第 3 回'), 3);
    });

    test('EP/E 前缀与纯数字开头', () {
      expect(DanmakuMatcher.parseEpisodeNumber('EP05 - 结尾'), 5);
      expect(DanmakuMatcher.parseEpisodeNumber('E7'), 7);
      expect(DanmakuMatcher.parseEpisodeNumber('03 标题'), 3);
    });

    test('无法提取返回 null', () {
      expect(DanmakuMatcher.parseEpisodeNumber('序章'), isNull);
      expect(DanmakuMatcher.parseEpisodeNumber(''), isNull);
    });
  });

  group('M1：parseSeasonEpisode（SxxExx / 1x02）', () {
    test('SxxExx 解析季+集', () {
      expect(DanmakuMatcher.parseSeasonEpisode('S01E02'),
          (season: 1, episode: 2));
      expect(DanmakuMatcher.parseSeasonEpisode('[Subs] Title S01E05 1080p'),
          (season: 1, episode: 5));
      expect(DanmakuMatcher.parseSeasonEpisode('s2 e10'),
          (season: 2, episode: 10));
    });

    test('1x02 解析季+集', () {
      expect(DanmakuMatcher.parseSeasonEpisode('Title.1x02.mkv'),
          (season: 1, episode: 2));
      expect(DanmakuMatcher.parseSeasonEpisode('3X25 结局'),
          (season: 3, episode: 25));
    });

    test('词边界防误判：Files01e12 不命中', () {
      expect(DanmakuMatcher.parseSeasonEpisode('Files01e12'), isNull);
    });

    test('无显式形态返回 null', () {
      expect(DanmakuMatcher.parseSeasonEpisode('序章'), isNull);
      expect(DanmakuMatcher.parseSeasonEpisode(''), isNull);
    });
  });

  group('M1：parseEpisodeNumber 全变体', () {
    test('SxxExx / 1x02 提取集号', () {
      expect(DanmakuMatcher.parseEpisodeNumber('[ANi] 葬送的芙莉莲 S01E05'), 5);
      expect(DanmakuMatcher.parseEpisodeNumber('Title.1x02'), 2);
    });

    test('Episode 全词与 EP/E 等价', () {
      expect(DanmakuMatcher.parseEpisodeNumber('Episode 12'), 12);
      expect(DanmakuMatcher.parseEpisodeNumber('Episode12 结尾'), 12);
    });

    test('「 - NN - 」/「 - NN」（AniList 式命名）', () {
      expect(
        DanmakuMatcher.parseEpisodeNumber('Title - 01 - 魔法使いの弟子'),
        1,
      );
      expect(DanmakuMatcher.parseEpisodeNumber('Title - 12'), 12);
    });

    test('「[NN]」/「[NNv2]」字幕组括号集数', () {
      expect(DanmakuMatcher.parseEpisodeNumber('Title [01v2]'), 1);
      expect(DanmakuMatcher.parseEpisodeNumber('Title [08]'), 8);
    });

    test('中缀裸数字（排除年份与分辨率）', () {
      expect(DanmakuMatcher.parseEpisodeNumber('Title 03 1080p'), 3);
      expect(DanmakuMatcher.parseEpisodeNumber('Title 2023 05'), 5);
      expect(DanmakuMatcher.parseEpisodeNumber('Title 720p'), isNull);
      expect(DanmakuMatcher.parseEpisodeNumber('Title 2023'), isNull);
      expect(DanmakuMatcher.parseEpisodeNumber('Title 1080i'), isNull);
    });

    test('年份不冒充集数（dash/bracket/开头）', () {
      expect(DanmakuMatcher.parseEpisodeNumber('Title - 2023'), isNull);
      expect(DanmakuMatcher.parseEpisodeNumber('Title [2023]'), isNull);
      expect(DanmakuMatcher.parseEpisodeNumber('1984 回忆'), isNull);
    });
  });

  group('M1：cleanTitle 集号残段清洗', () {
    test('「 - NN - xxx」整段后缀丢弃', () {
      expect(
        DanmakuMatcher.cleanTitle('葬送的芙莉莲 - 01 - 魔法使いの弟子 1080p'),
        '葬送的芙莉莲',
      );
      expect(DanmakuMatcher.cleanTitle('Title - 12'), 'Title');
    });

    test('1x02 / Episode N / 第N话 残段', () {
      expect(DanmakuMatcher.cleanTitle('Title.1x02.2160p'), 'Title');
      expect(DanmakuMatcher.cleanTitle('Title Episode 3'), 'Title');
      expect(DanmakuMatcher.cleanTitle('某剧 第12话'), '某剧');
    });

    test('括号集数与 (TV)/(OVA) 标签', () {
      expect(DanmakuMatcher.cleanTitle('Title [01v2]'), 'Title');
      expect(DanmakuMatcher.cleanTitle('Title (TV)'), 'Title');
      expect(DanmakuMatcher.cleanTitle('Title [OVA]'), 'Title');
    });

    test('年份括号照旧剥离、片名数字不误删', () {
      expect(DanmakuMatcher.cleanTitle('Title [2023] 1080p'), 'Title');
      expect(DanmakuMatcher.cleanTitle('命运石之门 0'), '命运石之门 0');
    });
  });

  group('M1：fromEpisode 文件名兜底解析', () {
    test('元数据缺季/集时从文件名解析 SxxExx', () {
      expect(
        DanmakuMatcher.fromEpisode(
          name: '[ANi] Title - S01E05 1080p',
          seriesName: 'Title',
        ),
        'Title.S01E05',
      );
      expect(
        DanmakuMatcher.fromEpisode(
          name: 'Title.1x02.mkv',
          seriesName: 'Title',
        ),
        'Title.S01E02',
      );
    });

    test('元数据优先，文件名不覆盖', () {
      expect(
        DanmakuMatcher.fromEpisode(
          name: 'S02E09 xxx',
          seriesName: '剧',
          season: 1,
          number: 3,
        ),
        '剧.S01E03',
      );
    });

    test('文件名也无集号时仍回退 name', () {
      expect(
        DanmakuMatcher.fromEpisode(name: '千与千寻', seriesName: '宫崎骏'),
        '千与千寻',
      );
    });
  });
}

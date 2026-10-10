import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:url_launcher/url_launcher.dart';

/// 详情页底部「相似推荐 / 外部链接 / 工作室 / 媒体信息 / 视频 / 音频」区块
/// （仅非 TV 渲染）。数据来自 Emby 详情字段与 `MediaStreams`。
class MediaDetailsSection extends StatelessWidget {
  const MediaDetailsSection({
    super.key,
    required this.item,
    this.streamsItem,
    this.selectedSource,
    this.similarItems = const [],
    this.onOpenSimilar,
  });

  final MediaItem item;

  /// 媒体信息（路径/大小/时间）与视频/音频流的取数条目：
  /// 电影 = 主条目；剧集 = 当前选中集（null 时回退 [item]）。
  /// 外部链接/工作室仍取 [item]（剧集本身）。
  final MediaItem? streamsItem;

  /// 当前选中版本（电影 = `_selectedMediaSourceId` 对应源；剧集 = 该集
  /// `_episodeSourceIds` 对应源）。非空时视频/音频流、路径、大小优先取
  /// 该版本——`item.mediaStreams` 是 Emby 默认源的顶层流，切版本后
  /// 不变（v1.1.177：修「切换版本后底部媒体信息不更新」）。
  final MediaSource? selectedSource;

  /// 相似推荐条目（渲染在「外部链接」之上；空则不显示）。
  final List<MediaItem> similarItems;

  /// 点击相似推荐卡片。
  final void Function(MediaItem item)? onOpenSimilar;

  MediaItem get _mediaItem => streamsItem ?? item;

  /// 生效流列表：选中版本有解析到流时优先用它，否则回退条目顶层流
  /// （个别源未带 MediaStreams 时避免整卡消失）。
  List<MediaStream> get _effectiveStreams {
    final src = selectedSource;
    if (src != null && src.mediaStreams.isNotEmpty) return src.mediaStreams;
    return _mediaItem.mediaStreams;
  }

  /// 生效路径：选中版本优先，回退条目顶层路径，再回退默认源（首个）路径。
  String? get _effectivePath => selectedSource?.path ??
      _mediaItem.path ??
      (_mediaItem.mediaSources.isNotEmpty
          ? _mediaItem.mediaSources.first.path
          : null);

  /// 生效大小：选中版本优先，回退默认源（首个）大小。
  int? get _effectiveSize =>
      selectedSource?.size ??
      (_mediaItem.mediaSources.isNotEmpty
          ? _mediaItem.mediaSources.first.size
          : null);

  /// 有可展示内容才渲染。
  static bool hasContent(MediaItem item,
      {List<MediaItem> similarItems = const [],
      MediaItem? streamsItem,
      MediaSource? selectedSource}) {
    final m = streamsItem ?? item;
    return similarItems.isNotEmpty ||
        item.externalUrls.isNotEmpty ||
        item.providerIds.isNotEmpty ||
        item.studios.isNotEmpty ||
        selectedSource?.path != null ||
        m.path != null ||
        (selectedSource != null && selectedSource.mediaStreams.isNotEmpty) ||
        m.mediaStreams.isNotEmpty;
  }

  /// 外链组装（优先 Emby `ExternalUrls`，缺失用 `ProviderIds` 拼常见站点）。
  static List<ExternalUrl> externalLinksFor(MediaItem item) {
    final out = <ExternalUrl>[];
    final seen = <String>{};
    void add(String name, String url) {
      if (url.isEmpty || !seen.add(name)) return;
      out.add(ExternalUrl(name: name, url: url));
    }

    for (final e in item.externalUrls) {
      add(e.name, e.url);
    }
    final p = item.providerIds;
    if (p['Imdb'] != null) {
      add('IMDb', 'https://www.imdb.com/title/${p['Imdb']}/');
    }
    if (p['Tmdb'] != null) {
      final kind = item.isSeries ? 'tv' : 'movie';
      add('TheMovieDb', 'https://www.themoviedb.org/$kind/${p['Tmdb']}');
    }
    if (p['Tvdb'] != null) {
      add('TheTVDB', 'https://www.thetvdb.com/?id=${p['Tvdb']}');
    }
    return out;
  }

  static String formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '-';
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(2)} G';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} M';
  }

  static String formatBitrate(int? bps) {
    if (bps == null || bps <= 0) return '-';
    if (bps >= 1000000) {
      final mbps = bps / 1000000;
      return '${mbps.toStringAsFixed(mbps >= 10 ? 0 : 1)} Mbps';
    }
    return '${(bps / 1000).round()} kbps';
  }

  static String formatDate(DateTime? d) {
    if (d == null) return '-';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  static String aspectRatio(int? w, int? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return '-';
    var a = w, b = h;
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return '${w ~/ a}:${h ~/ a}';
  }

  @override
  Widget build(BuildContext context) {
    final links = externalLinksFor(item);
    final media = _mediaItem;
    final streams = _effectiveStreams;
    final video = streams.where((s) => s.type == 'Video').toList();
    final audios = streams.where((s) => s.type == 'Audio').toList();
    final path = _effectivePath;
    final size = _effectiveSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (similarItems.isNotEmpty) ...[
          const _SectionTitle('相似推荐'),
          SizedBox(
            height: PosterCard.heightFor(88),
            child: ListView.builder(
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: similarItems.length,
              itemBuilder: (context, index) {
                final sim = similarItems[index];
                return SizedBox(
                  width: 96,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: PosterCard(
                      key: ValueKey('posterCard_${sim.id}'),
                      item: sim,
                      width: 88,
                      onTap: () => onOpenSimilar?.call(sim),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (links.isNotEmpty) ...[
          const _SectionTitle('外部链接'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final l in links) _LinkChip(link: l)],
          ),
          const SizedBox(height: 20),
        ],
        if (item.studios.isNotEmpty) ...[
          const _SectionTitle('工作室'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in item.studios) _GlassChip(label: s),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (path != null || size != null || media.dateCreated != null) ...[
          const _SectionTitle('媒体信息'),
          if (path != null) ...[
            const Text('路径:',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 4),
            SelectableText(
              path,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (size != null)
                Text(
                  formatSize(size),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              if (media.dateCreated != null)
                Text(
                  '加入时间: ${formatDate(item.dateCreated)}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (video.isNotEmpty || audios.isNotEmpty)
          _VideoAudioCards(video: video, audios: audios),
      ],
    );
  }
}

class _VideoAudioCards extends StatelessWidget {
  const _VideoAudioCards({required this.video, required this.audios});

  final List<MediaStream> video;
  final List<MediaStream> audios;

  @override
  Widget build(BuildContext context) {
    final specs = <_StreamSpec>[
      for (final v in video) _StreamSpec('视频', Icons.movie, _videoRows(v)),
      for (final a in audios)
        _StreamSpec('音频', Icons.music_note, _audioRows(a)),
    ];
    if (specs.isEmpty) return const SizedBox.shrink();

    // 高度按最长卡内容自适应：表头 + 内边距 + 最大行数 × 行高。
    // 行高（13 号字 + 上下 padding 3）取 ~26，留适量余量防裁切；
    // 所有卡被同一高度约束 → 与最长卡等高对齐。
    final maxRows =
        specs.map((s) => s.rows.length).fold<int>(0, (a, b) => a > b ? a : b);
    final height = 60.0 + maxRows * 26.0;

    // 横向排列、可左右滑动
    return SizedBox(
      height: height,
      child: ListView.separated(
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: specs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 300,
          child: _StreamCard(
            title: specs[i].title,
            icon: specs[i].icon,
            rows: specs[i].rows,
          ),
        ),
      ),
    );
  }
}

/// 单张流信息卡的内容规格（标题 + 图标 + 行）。
class _StreamSpec {
  const _StreamSpec(this.title, this.icon, this.rows);
  final String title;
  final IconData icon;
  final List<(String, String)> rows;
}

List<(String, String)> _videoRows(MediaStream s) {
  final rows = <(String, String)>[];
  void add(String k, String? v) {
    if (v != null && v.isNotEmpty && v != '-') rows.add((k, v));
  }

  add('标题', s.displayTitle ?? s.title);
  add('编解码器', s.codec);
  add('配置', s.profile);
  add('等级', s.level?.toString());
  add('分辨率',
      (s.width != null && s.height != null) ? '${s.width}x${s.height}' : null);
  add('长宽比', MediaDetailsSection.aspectRatio(s.width, s.height));
  add('交错', s.isInterlaced == true ? '是' : '否');
  add('帧率', s.frameRate != null ? '${s.frameRate} fps' : null);
  add('比特率',
      s.bitRate != null ? MediaDetailsSection.formatBitrate(s.bitRate) : null);
  add('视频范围', s.hdrLabel);
  add('基色', s.colorPrimaries);
  add('色彩空间', s.colorSpace);
  add('色彩转换', s.transferCharacteristics);
  add('位深度', s.bitDepth != null ? '${s.bitDepth} bit' : null);
  add('像素格式', s.pixelFormat);
  add('参考帧', s.refFrames?.toString());
  return rows;
}

List<(String, String)> _audioRows(MediaStream s) {
  final rows = <(String, String)>[];
  void add(String k, String? v) {
    if (v != null && v.isNotEmpty && v != '-') rows.add((k, v));
  }

  add('标题', s.displayTitle ?? s.title);
  add('语言', s.displayLanguage ?? s.language);
  add('编解码器', s.codec);
  add('配置', s.profile);
  add('布局', s.channelLayout);
  add('频道', s.channels != null ? '${s.channels} ch' : null);
  add('比特率',
      s.bitRate != null ? MediaDetailsSection.formatBitrate(s.bitRate) : null);
  add('采样率', s.sampleRate != null ? '${s.sampleRate} Hz' : null);
  add('默认', s.isDefault == true ? '是' : '否');
  return rows;
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.title,
    required this.icon,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return GlassContainer(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(r.$1,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white60)),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link});
  final ExternalUrl link;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
      },
      child: GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(link.name,
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 玻璃胶囊（工作室等纯展示项）。
class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(label,
          style: const TextStyle(fontSize: 13, color: Colors.white)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:url_launcher/url_launcher.dart';

/// 详情页底部「外部链接 / 工作室 / 媒体信息」区块（仅非 TV 渲染）。
/// 数据来自 Emby 详情字段：`ExternalUrls/ProviderIds/Studios/Path/DateCreated`
/// 与 `MediaStreams` 的编解码细节。
class MediaDetailsSection extends StatelessWidget {
  const MediaDetailsSection({super.key, required this.item});

  final MediaItem item;

  /// 有可展示内容才渲染。
  static bool hasContent(MediaItem item) =>
      item.externalUrls.isNotEmpty ||
      item.providerIds.isNotEmpty ||
      item.studios.isNotEmpty ||
      item.path != null ||
      item.mediaStreams.isNotEmpty;

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
    final video = item.mediaStreams.where((s) => s.type == 'Video').toList();
    final audios = item.mediaStreams.where((s) => s.type == 'Audio').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              for (final s in item.studios)
                Chip(
                  label: Text(s, style: const TextStyle(fontSize: 13)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (item.path != null ||
            item.mediaSources.isNotEmpty ||
            item.dateCreated != null) ...[
          const _SectionTitle('媒体信息'),
          if (item.path != null) ...[
            const Text('路径:',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 4),
            SelectableText(
              item.path!,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (item.mediaSources.isNotEmpty)
                Text(
                  formatSize(item.mediaSources.first.size),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              if (item.dateCreated != null)
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
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final v in video)
          _StreamCard(title: '视频', icon: Icons.movie, rows: _videoRows(v)),
        for (final a in audios)
          _StreamCard(title: '音频', icon: Icons.music_note, rows: _audioRows(a)),
      ],
    );
  }
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
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
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
    return ActionChip(
      avatar: const Icon(Icons.open_in_new, size: 14),
      label: Text(link.name, style: const TextStyle(fontSize: 13)),
      onPressed: () {
        launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication);
      },
    );
  }
}

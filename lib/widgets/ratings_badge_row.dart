import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:simple_icons/simple_icons.dart';

/// 平台徽章样式表：品牌图标 + 显示色（纯表驱动，缺数据的平台自然不渲染）。
///
/// 显示色优先取品牌色；品牌本身是黑色（暗底不可见）的转白显示。
class _BadgeStyle {
  const _BadgeStyle.brand(this.icon, this.color) : emoji = null;

  /// 无品牌图标的平台用 emoji（烂番茄观众分的爆米花）。
  const _BadgeStyle.emoji(this.emoji)
      : icon = null,
        color = null;

  final IconData? icon;
  final Color? color;
  final String? emoji;
}

const Map<RatingPlatform, _BadgeStyle> _badgeStyles = {
  RatingPlatform.douban: _BadgeStyle.brand(SimpleIcons.douban, Color(0xff2d963d)),
  RatingPlatform.tmdb: _BadgeStyle.brand(
    SimpleIcons.themoviedatabase,
    Color(0xff01b4e4),
  ),
  RatingPlatform.imdb: _BadgeStyle.brand(SimpleIcons.imdb, Color(0xfff5c518)),
  RatingPlatform.rottenTomatoesCritic: _BadgeStyle.brand(
    SimpleIcons.rottentomatoes,
    Color(0xfffa320a),
  ),
  RatingPlatform.rottenTomatoesAudience: _BadgeStyle.emoji('🍿'),
  // Letterboxd 官方品牌色 #202830 在暗底不可见 → 用其点阵绿。
  RatingPlatform.letterboxd: _BadgeStyle.brand(
    SimpleIcons.letterboxd,
    Color(0xff00e054),
  ),
  RatingPlatform.trakt: _BadgeStyle.brand(SimpleIcons.trakt, Color(0xff9f42c6)),
  // Metacritic 品牌色为黑，暗底转白。
  RatingPlatform.metacritic: _BadgeStyle.brand(
    SimpleIcons.metacritic,
    Color(0xfff2f2f2),
  ),
};

/// 多平台评分行：行内「品牌图标 + 分数」小徽章（样式对齐参考截图）。
///
/// 纯展示组件：渲染顺序按 [RatingPlatform] 声明顺序，同平台去重，
/// 无数据平台自动隐藏（绝不留空徽章）。
class RatingsBadgeRow extends StatelessWidget {
  const RatingsBadgeRow({
    super.key,
    required this.badges,
    this.iconSize = 16,
    this.spacing = 12,
    this.runSpacing = 6,
    this.textStyle,
    this.alignment = WrapAlignment.start,
  });

  final List<HeroRatingBadge> badges;
  final double iconSize;
  final double spacing;
  final double runSpacing;
  final TextStyle? textStyle;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered(badges);
    if (ordered.isEmpty) return const SizedBox.shrink();
    final style = textStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        );
    return Wrap(
      alignment: alignment,
      spacing: spacing,
      runSpacing: runSpacing,
      children: [
        for (final badge in ordered)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(badge.platform),
              const SizedBox(width: 4),
              Text(badge.display, style: style),
            ],
          ),
      ],
    );
  }

  Widget _icon(RatingPlatform platform) {
    final spec = _badgeStyles[platform];
    if (spec == null) return SizedBox(width: iconSize, height: iconSize);
    if (spec.icon != null) {
      return Icon(spec.icon, size: iconSize, color: spec.color);
    }
    // emoji 自带配色，仅需对齐字号。
    return Text(
      spec.emoji!,
      style: TextStyle(fontSize: iconSize, height: 1),
    );
  }

  /// 按平台声明顺序排序并去重（同平台保留首个）。
  static List<HeroRatingBadge> _ordered(List<HeroRatingBadge> input) {
    final seen = <RatingPlatform>{};
    final unique = <HeroRatingBadge>[
      for (final b in input)
        if (seen.add(b.platform)) b,
    ];
    unique.sort((a, b) => a.platform.index.compareTo(b.platform.index));
    return unique;
  }
}

/// 异步评分行：首帧渲染种子徽章（本地分），网络数据到达后整体替换。
///
/// [query] 变化（换条目）时重新加载；[service] 内部按 IMDb id 缓存，
/// 重复构建不重复发请求。
class HeroRatingsLoader extends StatefulWidget {
  const HeroRatingsLoader({
    super.key,
    required this.query,
    required this.service,
    this.iconSize = 16,
    this.spacing = 12,
    this.textStyle,
    this.alignment = WrapAlignment.start,
  });

  final HeroRatingQuery query;
  final HeroRatingsSource service;
  final double iconSize;
  final double spacing;
  final TextStyle? textStyle;
  final WrapAlignment alignment;

  @override
  State<HeroRatingsLoader> createState() => _HeroRatingsLoaderState();
}

class _HeroRatingsLoaderState extends State<HeroRatingsLoader> {
  List<HeroRatingBadge> _badges = const [];

  /// 请求序号令牌：换条目后旧响晚到不得覆写新条目徽章（698 竞态）。
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _badges = widget.query.seedBadges;
    _load();
  }

  @override
  void didUpdateWidget(covariant HeroRatingsLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 条目变化或 service 实例变化（配 key 后 provider 重建）都需重拉。
    if (oldWidget.query.cacheKey != widget.query.cacheKey ||
        oldWidget.query.tmdbScore != widget.query.tmdbScore ||
        !identical(oldWidget.service, widget.service)) {
      _badges = widget.query.seedBadges;
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final badges = await widget.service.fetch(widget.query);
    // 竞态防护：期间换过条目/服务（seq 不同）则丢弃本次结果。
    if (!mounted || seq != _seq) return;
    setState(() => _badges = badges);
  }

  @override
  Widget build(BuildContext context) {
    return RatingsBadgeRow(
      badges: _badges,
      iconSize: widget.iconSize,
      spacing: widget.spacing,
      textStyle: widget.textStyle,
      alignment: widget.alignment,
    );
  }
}

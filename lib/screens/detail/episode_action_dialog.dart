import 'package:flutter/material.dart';

import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 打开剧集横卡的 TV 操作面板。
///
/// 三项操作与卡片状态联动：播放/继续播放、收藏/取消收藏、标记已观看/
/// 取消已观看。收藏与已观看切换后面板保持打开并即时更新文案；播放后
/// 关闭面板进入播放器。
Future<void> showEpisodeActionDialog({
  required BuildContext context,
  required String episodeId,
  required String title,
  required bool resume,
  required bool favorited,
  required bool watched,
  required Future<bool> Function() onToggleFavorite,
  required Future<bool> Function() onToggleWatched,
  required ValueChanged<bool> onPlay,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _EpisodeActionDialog(
      episodeId: episodeId,
      title: title,
      resume: resume,
      favorited: favorited,
      watched: watched,
      onToggleFavorite: onToggleFavorite,
      onToggleWatched: onToggleWatched,
      onPlay: onPlay,
    ),
  );
}

class _EpisodeActionDialog extends StatefulWidget {
  const _EpisodeActionDialog({
    required this.episodeId,
    required this.title,
    required this.resume,
    required this.favorited,
    required this.watched,
    required this.onToggleFavorite,
    required this.onToggleWatched,
    required this.onPlay,
  });

  final String episodeId;
  final String title;
  final bool resume;
  final bool favorited;
  final bool watched;
  final Future<bool> Function() onToggleFavorite;
  final Future<bool> Function() onToggleWatched;
  final ValueChanged<bool> onPlay;

  @override
  State<_EpisodeActionDialog> createState() => _EpisodeActionDialogState();
}

class _EpisodeActionDialogState extends State<_EpisodeActionDialog> {
  bool _resume = false;
  bool _favorited = false;
  bool _watched = false;
  bool _favoriteBusy = false;
  bool _watchedBusy = false;

  @override
  void initState() {
    super.initState();
    _resume = widget.resume;
    _favorited = widget.favorited;
    _watched = widget.watched;
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final next = !_favorited;
    setState(() {
      _favoriteBusy = true;
      _favorited = next;
    });
    final ok = await widget.onToggleFavorite();
    if (!mounted) return;
    setState(() {
      _favoriteBusy = false;
      if (!ok) _favorited = !next;
    });
  }

  Future<void> _toggleWatched() async {
    if (_watchedBusy) return;
    final next = !_watched;
    setState(() {
      _watchedBusy = true;
      _watched = next;
    });
    final ok = await widget.onToggleWatched();
    if (!mounted) return;
    setState(() {
      _watchedBusy = false;
      if (!ok) {
        _watched = !next;
      } else {
        // 标记已观看/取消后服务器会清除该集续播位置，播放项恢复「播放」。
        _resume = false;
      }
    });
  }

  void _play() {
    final resume = _resume;
    Navigator.of(context).pop();
    widget.onPlay(resume);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EpisodeActionRow(
              key: Key('episodeActionPlay_${widget.episodeId}'),
              icon: _resume ? Icons.play_circle_outline : Icons.play_arrow,
              label: _resume ? '继续播放' : '播放',
              subtitle: _resume ? '从上次观看进度继续' : '从头开始播放',
              autofocus: true,
              onTap: _play,
            ),
            _EpisodeActionRow(
              key: Key('episodeActionFavorite_${widget.episodeId}'),
              icon: _favorited ? Icons.favorite : Icons.favorite_border,
              label: _favorited ? '取消收藏' : '收藏',
              subtitle: _favorited ? '当前已收藏' : '当前未收藏',
              onTap: _toggleFavorite,
            ),
            _EpisodeActionRow(
              key: Key('episodeActionWatched_${widget.episodeId}'),
              icon: _watched ? Icons.check_circle : Icons.check_circle_outline,
              label: _watched ? '取消已观看' : '标记已观看',
              subtitle: _watched ? '当前已观看' : '当前未观看',
              onTap: _toggleWatched,
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeActionRow extends StatelessWidget {
  const _EpisodeActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return TvFocusable(
      autofocus: autofocus,
      radius: 8,
      scale: 1.0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

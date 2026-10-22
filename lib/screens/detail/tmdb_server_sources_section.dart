import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 详情页「资源渠道」栏：仅聚合模式显示，按 TMDB id 精确匹配。
class TmdbServerSourcesSection extends ConsumerStatefulWidget {
  const TmdbServerSourcesSection({
    super.key,
    required this.item,
    this.currentServerId,
  });

  final MediaItem item;
  final String? currentServerId;

  @override
  ConsumerState<TmdbServerSourcesSection> createState() =>
      _TmdbServerSourcesSectionState();
}

class _TmdbServerSourcesSectionState
    extends ConsumerState<TmdbServerSourcesSection> {
  List<TmdbAvailability> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TmdbServerSourcesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.tmdbId != widget.item.tmdbId ||
        oldWidget.currentServerId != widget.currentServerId) {
      _load();
    }
  }

  Future<void> _load() async {
    final service = ref.read(tmdbAggregateServiceProvider);
    if (service == null || widget.item.tmdbId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final result = await service.findAllAvailability(
        widget.item,
        ref.read(embyServerListProvider),
        activeServerId: ref.read(embyConfigProvider)?.id,
      );
      if (!mounted) return;
      setState(() {
        _entries = result.items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.tmdbId == null) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_entries.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '资源渠道',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 68,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final current = entry.server.id == widget.currentServerId;
              return TvFocusable(
                radius: 12,
                onTap: () {
                  if (current) return;
                  context.pushReplacement(
                    '/detail/${entry.item.id}?server=${Uri.encodeComponent(entry.server.id)}&aggregate=true',
                  );
                },
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ServerAvatar(
                        label: entry.server.label,
                        size: 34,
                        imageUrl: serverAvatarUrl(entry.server),
                        imageHeaders: {
                          if (entry.server.accessToken != null)
                            'X-Emby-Token': entry.server.accessToken!,
                        },
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              entry.server.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            current ? '当前服务器' : '切换资源',
                            style: TextStyle(
                              fontSize: 11,
                              color: current
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 首页来源模式切换：服务器 / TMDB 聚合。
class HomeModeButton extends ConsumerWidget {
  const HomeModeButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tmdb = ref.watch(settingsProvider.select((s) => s.isTmdbHome));
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final label = tmdb ? '服务器' : 'TMDB';
    final icon = tmdb ? Icons.dns_outlined : Icons.local_movies_outlined;
    void toggle() {
      ref.read(settingsProvider.notifier).update(
            homeSourceMode: tmdb ? 'server' : 'tmdb',
          );
    }

    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: tvMode ? null : toggle,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 18 : 19,
                  color: tmdb
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: tmdb ? '切换回服务器首页' : '切换到 TMDB 聚合首页',
      child: KeyedSubtree(
        key: const Key('homeModeButton'),
        child: tvMode
            ? TvFocusable(radius: 20, onTap: toggle, child: child)
            : glassWrap(context, child),
      ),
    );
  }

  Widget glassWrap(BuildContext context, Widget child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: child,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_option_dialog.dart';

/// 详情页操作图标行：版本 / 字幕 / 音轨选择器入口（电影与剧集页共用）。
///
/// - 版本图标：`onOpenVersion` 非空（多版本资源）时显示在最前；
///   选中版本后字幕/音轨的流列表切换为该版本的轨（联动）
/// - 字幕图标：`subtitleStreams` 非空时显示
/// - 音轨图标：音轨多于一条时显示
/// - 点击弹出选择器 bottom sheet。电影模式不传 [selection]/
///   [onSelectionChanged]，读写全局 [pendingTrackSelectionProvider]；
///   剧集模式传入 per-episode 的选择与回调（避免多集互相覆盖）
/// - TV 模式用 [TvFocusable] 包裹（焦点环 + Enter 走 onTap），触摸走内层按钮
class TrackActionRow extends ConsumerWidget {
  final MediaItem item;

  /// 当前选中版本 id（null = 默认；非 null 时版本图标高亮）。
  final String? selectedMediaSourceId;

  /// 打开版本选择器；null = 不显示版本图标（单版本资源）。
  final VoidCallback? onOpenVersion;

  /// 当前版本的字幕/音轨流（由详情页按选中版本计算后传入）。
  final List<MediaStream> subtitleStreams;
  final List<MediaStream> audioStreams;

  /// 当前预选（剧集模式传入 per-episode 值；null = 读全局 provider）。
  final TrackSelection? selection;

  /// 选择变化回调（剧集模式传入；null = 写全局 provider）。
  final ValueChanged<TrackSelection>? onSelectionChanged;

  /// 收藏态（null/未提供 = 不显示收藏入口）。
  final bool? isFavorite;

  /// 点击收藏/取消收藏（非空即显示爱心控件）。
  final VoidCallback? onToggleFavorite;

  /// 已观看态（配合 [onToggleWatched] 显示对勾控件）。
  final bool? isWatched;

  /// 点击标记/取消已观看（非空即显示对勾控件）。
  final VoidCallback? onToggleWatched;

  /// 从头播放（非空即显示，渲染在版本控件之前）。
  final VoidCallback? onPlayFromBeginning;

  const TrackActionRow({
    super.key,
    required this.item,
    this.selectedMediaSourceId,
    this.onOpenVersion,
    this.subtitleStreams = const [],
    this.audioStreams = const [],
    this.selection,
    this.onSelectionChanged,
    this.isFavorite,
    this.onToggleFavorite,
    this.isWatched,
    this.onToggleWatched,
    this.onPlayFromBeginning,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showVersion = onOpenVersion != null;
    final showSubtitle = subtitleStreams.isNotEmpty;
    final showAudio = audioStreams.length > 1;
    final showFavorite = onToggleFavorite != null;
    final showWatched = onToggleWatched != null;
    final showFromBeginning = onPlayFromBeginning != null;
    if (!showVersion &&
        !showSubtitle &&
        !showAudio &&
        !showFavorite &&
        !showWatched &&
        !showFromBeginning) {
      return const SizedBox.shrink();
    }

    // watch 无条件调用（Riverpod 约束）；剧集模式用显式 selection 覆盖
    final providerSelection = ref.watch(pendingTrackSelectionProvider);
    final current = selection ?? providerSelection;
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    Widget button({
      required Key key,
      required IconData icon,
      required bool active,
      required VoidCallback onTap,
    }) {
      final iconWidget = IconButton(
        key: key,
        icon: Icon(icon),
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface,
        tooltip: null,
        onPressed: onTap,
      );
      if (!tvMode) return iconWidget;
      return TvFocusable(
        radius: 12,
        onTap: onTap,
        child: ExcludeFocus(child: iconWidget),
      );
    }

    final children = <Widget>[
      if (showFromBeginning)
        button(
          key: const Key('playFromBeginningButton'),
          icon: Icons.replay,
          active: false,
          onTap: onPlayFromBeginning!,
        ),
      if (showVersion)
        button(
          key: const Key('versionSelectorButton'),
          icon: Icons.layers,
          active: selectedMediaSourceId != null,
          onTap: onOpenVersion!,
        ),
      if (showSubtitle)
        button(
          key: const Key('subtitleSelectorButton'),
          icon: Icons.subtitles_outlined,
          active: current?.subtitleIndex != null,
          onTap: () => showSubtitleSelector(
            context,
            ref,
            subtitleStreams,
            current: selection,
            onChanged: onSelectionChanged,
          ),
        ),
      if (showAudio)
        button(
          key: const Key('audioSelectorButton'),
          icon: Icons.audiotrack,
          active: current?.audioIndex != null,
          onTap: () => showAudioSelector(
            context,
            ref,
            audioStreams,
            current: selection,
            onChanged: onSelectionChanged,
          ),
        ),
      if (showFavorite)
        button(
          key: const Key('favoriteButton'),
          icon: (isFavorite ?? false) ? Icons.favorite : Icons.favorite_border,
          active: isFavorite ?? false,
          onTap: onToggleFavorite!,
        ),
      if (showWatched)
        button(
          key: const Key('watchedButton'),
          icon: (isWatched ?? false)
              ? Icons.check_circle
              : Icons.check_circle_outline,
          active: isWatched ?? false,
          onTap: onToggleWatched!,
        ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          children[i],
        ],
      ],
    );
  }
}

/// 选择器的一行选项：`value` 为 null=跟随默认、-1=关闭字幕、其余为
/// `MediaStream.index`。
class TrackOption {
  final String label;
  final int? value;

  const TrackOption(this.label, this.value);
}

/// 字幕选择器：「跟随默认」+「关闭字幕」+ 当前版本各字幕轨。
///
/// [current]/[onChanged] 为剧集模式的 per-episode 读写源；
/// 不传时读写全局 [pendingTrackSelectionProvider]（电影模式现行为）。
Future<void> showSubtitleSelector(
  BuildContext context,
  WidgetRef ref,
  List<MediaStream> streams, {
  TrackSelection? current,
  ValueChanged<TrackSelection>? onChanged,
}) {
  final audioIndex = current != null
      ? current.audioIndex
      : ref.read(pendingTrackSelectionProvider)?.audioIndex;
  final options = <TrackOption>[
    const TrackOption('跟随默认', null),
    const TrackOption('关闭字幕', -1),
    ...streams
        .where((s) => s.type == 'Subtitle')
        .map((s) => TrackOption(s.displayInfo, s.index)),
  ];
  return showTrackSelector(
    context,
    ref,
    title: '字幕',
    options: options,
    currentValue: current != null
        ? current.subtitleIndex
        : ref.read(pendingTrackSelectionProvider)?.subtitleIndex,
    onSelected: (value) {
      final next = TrackSelection(
        audioIndex: audioIndex,
        subtitleIndex: value,
      );
      if (onChanged != null) {
        onChanged(next);
      } else {
        ref.read(pendingTrackSelectionProvider.notifier).state = next;
      }
    },
  );
}

/// 音轨选择器：「跟随默认」+ 当前版本各音轨。
///
/// [current]/[onChanged] 语义同 [showSubtitleSelector]。
Future<void> showAudioSelector(
  BuildContext context,
  WidgetRef ref,
  List<MediaStream> streams, {
  TrackSelection? current,
  ValueChanged<TrackSelection>? onChanged,
}) {
  final subtitleIndex = current != null
      ? current.subtitleIndex
      : ref.read(pendingTrackSelectionProvider)?.subtitleIndex;
  final options = <TrackOption>[
    const TrackOption('跟随默认', null),
    ...streams
        .where((s) => s.type == 'Audio')
        .map((s) => TrackOption(s.displayInfo, s.index)),
  ];
  return showTrackSelector(
    context,
    ref,
    title: '音轨',
    options: options,
    currentValue: current != null
        ? current.audioIndex
        : ref.read(pendingTrackSelectionProvider)?.audioIndex,
    onSelected: (value) {
      final next = TrackSelection(
        audioIndex: value,
        subtitleIndex: subtitleIndex,
      );
      if (onChanged != null) {
        onChanged(next);
      } else {
        ref.read(pendingTrackSelectionProvider.notifier).state = next;
      }
    },
  );
}

/// 轨道选择弹层（字幕/音轨共用）：居中弹层 [showTvOptionDialog]，TV 遥控
/// D-pad 上下切换 + OK 选择（不用 RadioGroup——其内层方向键 Shortcut 会
/// 劫持 TV 导航导致弹层首次方向键即关闭跳选）。
Future<void> showTrackSelector(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<TrackOption> options,
  required int? currentValue,
  required void Function(int? value) onSelected,
}) {
  return showTvOptionDialog<int?>(
    context: context,
    title: title,
    currentValue: currentValue,
    onSelected: onSelected,
    options: [
      for (final option in options)
        TvOptionEntry(
          value: option.value,
          label: option.label,
          key: Key('trackOption_${option.value ?? 'auto'}'),
        ),
    ],
  );
}

/// 版本选择弹层（电影主条目与每集共用，居中弹层；当前版本对勾高亮）。
Future<void> showVersionSelector(
  BuildContext context, {
  required List<MediaSource> sources,
  required String? currentId,
  required ValueChanged<MediaSource> onSelected,
  String title = '选择版本',
}) {
  return showTvOptionDialog<String>(
    context: context,
    title: title,
    currentValue: currentId ?? '',
    onSelected: (id) {
      for (final source in sources) {
        if (source.id == id) {
          onSelected(source);
          return;
        }
      }
    },
    options: [
      for (final source in sources)
        TvOptionEntry(
          value: source.id,
          label: source.name,
          subtitle: source.displayLabel,
          key: Key('versionOption_${source.id}'),
        ),
    ],
  );
}

/// 版本切换时的预选轨迁移（纯函数）：不同版本的 `MediaStream.index`
/// 归属不同流集，直接沿用会错轨，故按「语言 + 类型」在新版本里找同
/// 语言轨；找不到则该轨清空。
///
/// [keepNegative]：字幕的 -1（显式关闭）需原样保留；音轨不保留。
/// 返回 null 表示两轨都被清空，调用方可据此整体清掉预选。
TrackSelection? migrateTrackSelection(
  TrackSelection selection, {
  required List<MediaStream> oldAudio,
  required List<MediaStream> newAudio,
  required List<MediaStream> oldSubtitle,
  required List<MediaStream> newSubtitle,
}) {
  int? migrate(
    int? index,
    List<MediaStream> from,
    List<MediaStream> to, {
    bool keepNegative = false,
  }) {
    if (index == null) return null;
    if (index < 0) return keepNegative ? index : null;
    MediaStream? old;
    for (final s in from) {
      if (s.index == index) {
        old = s;
        break;
      }
    }
    if (old == null) return null;
    final lang = old.language ?? old.displayLanguage;
    if (lang == null || lang.isEmpty) return null;
    for (final s in to) {
      final l = s.language ?? s.displayLanguage;
      if (l == lang) return s.index;
    }
    return null;
  }

  final newAudioIndex = migrate(selection.audioIndex, oldAudio, newAudio);
  final newSubtitleIndex = migrate(
    selection.subtitleIndex,
    oldSubtitle,
    newSubtitle,
    keepNegative: true,
  );
  if (newAudioIndex == null && newSubtitleIndex == null) return null;
  return TrackSelection(
    audioIndex: newAudioIndex,
    subtitleIndex: newSubtitleIndex,
  );
}

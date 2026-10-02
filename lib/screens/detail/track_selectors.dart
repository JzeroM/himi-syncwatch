import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/track_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 详情页操作图标行：字幕 / 音轨选择器入口（电影与剧集页共用）。
///
/// - 字幕图标：存在 `type=='Subtitle'` 轨时显示
/// - 音轨图标：存在多于一条 `type=='Audio'` 轨时显示
/// - 点击弹出选择器 bottom sheet，选中写入 [pendingTrackSelectionProvider]，
///   播放时经 `resolveInitialTracks` 应用到播放器
/// - TV 模式用 [TvFocusable] 包裹（焦点环 + Enter 走 onTap），触摸走内层按钮
class TrackActionRow extends ConsumerWidget {
  final MediaItem item;

  const TrackActionRow({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitles =
        item.mediaStreams.where((s) => s.type == 'Subtitle').toList();
    final audios = item.mediaStreams.where((s) => s.type == 'Audio').toList();

    final showSubtitle = subtitles.isNotEmpty;
    final showAudio = audios.length > 1;
    if (!showSubtitle && !showAudio) return const SizedBox.shrink();

    final selection = ref.watch(pendingTrackSelectionProvider);
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
      if (showSubtitle)
        button(
          key: const Key('subtitleSelectorButton'),
          icon: Icons.subtitles_outlined,
          active: selection?.subtitleIndex != null,
          onTap: () => showSubtitleSelector(context, ref, item),
        ),
      if (showAudio)
        button(
          key: const Key('audioSelectorButton'),
          icon: Icons.audiotrack,
          active: selection?.audioIndex != null,
          onTap: () => showAudioSelector(context, ref, item),
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

/// 字幕选择器：「跟随默认」+「关闭字幕」+ 各字幕轨。
Future<void> showSubtitleSelector(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  final options = <TrackOption>[
    const TrackOption('跟随默认', null),
    const TrackOption('关闭字幕', -1),
    ...item.mediaStreams
        .where((s) => s.type == 'Subtitle')
        .map((s) => TrackOption(s.displayInfo, s.index)),
  ];
  return showTrackSelector(
    context,
    ref,
    title: '字幕',
    options: options,
    currentValue: ref.read(pendingTrackSelectionProvider)?.subtitleIndex,
    onSelected: (value) {
      ref.read(pendingTrackSelectionProvider.notifier).state = TrackSelection(
        audioIndex: ref.read(pendingTrackSelectionProvider)?.audioIndex,
        subtitleIndex: value,
      );
    },
  );
}

/// 音轨选择器：「跟随默认」+ 各音轨。
Future<void> showAudioSelector(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) {
  final options = <TrackOption>[
    const TrackOption('跟随默认', null),
    ...item.mediaStreams
        .where((s) => s.type == 'Audio')
        .map((s) => TrackOption(s.displayInfo, s.index)),
  ];
  return showTrackSelector(
    context,
    ref,
    title: '音轨',
    options: options,
    currentValue: ref.read(pendingTrackSelectionProvider)?.audioIndex,
    onSelected: (value) {
      ref.read(pendingTrackSelectionProvider.notifier).state = TrackSelection(
        audioIndex: value,
        subtitleIndex: ref.read(pendingTrackSelectionProvider)?.subtitleIndex,
      );
    },
  );
}

/// 轨道选择底部弹窗（字幕/音轨共用，与 `_showVersionPicker` 同交互模式，
/// TV 遥控经由 MaterialApp.builder 层的 TvRemoteShortcuts 可正常操作）。
Future<void> showTrackSelector(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<TrackOption> options,
  required int? currentValue,
  required void Function(int? value) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          for (final option in options)
            RadioListTile<int?>(
              key: Key('trackOption_${option.value ?? 'auto'}'),
              title: Text(option.label),
              value: option.value,
              groupValue: currentValue,
              onChanged: (v) {
                onSelected(v);
                Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

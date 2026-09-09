import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const DetailScreen({super.key, required this.itemId});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  MediaItem? _item;
  List<MediaItem> _episodes = [];
  List<MediaItem> _similarItems = [];
  bool _isLoading = true;
  String? _error;
  bool _overviewExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final item = await embyService.getItemDetails(widget.itemId);

      if (item != null) {
        final futures = <Future>[];

        if (item.isSeries) {
          futures.add(
            embyService.getItems(
              parentId: widget.itemId,
              includeItemTypes: 'Episode',
            ).then((episodes) {
              _episodes = episodes;
            }),
          );
        }

        futures.add(
          embyService.getSimilarItems(widget.itemId).then((similar) {
            _similarItems = similar;
          }),
        );

        await Future.wait(futures);
      }

      setState(() {
        _item = item;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createRoom() async {
    if (_item == null) return;

    final agoraConfig = ref.read(agoraConfigProvider);
    if (agoraConfig == null || !agoraConfig.isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在侧边栏配置声网 App ID 和 App Certificate')),
        );
      }
      return;
    }

    // 1. 版本选择（如有）
    MediaSource? selectedSource;
    if (_item!.hasMultipleVersions) {
      selectedSource = await _showVersionPicker();
      if (selectedSource == null) return;
    }

    // 2. 电视剧 → 集数多选弹窗
    List<String>? selectedEpisodeIds;
    if (_item!.isSeries && _episodes.isNotEmpty) {
      final selectedEpisodes = await _showEpisodePicker();
      if (selectedEpisodes == null) return;
      selectedEpisodeIds = selectedEpisodes.map((e) => e.id).toList();
    }

    // 3. Token 数量弹窗
    final tokenCount = await _showTokenCountDialog();
    if (tokenCount == null) return;

    // 4. 构建房间码（仅含连接信息，媒体数据通过 RTM 发送）
    final channel = RoomCode.generateChannelId();
    final hostUid = RoomCode.generateHostUid();

    final roomCode = RoomCode.encode(
      appId: agoraConfig.appId,
      appCertificate: agoraConfig.appCertificate,
      channel: channel,
      hostUid: hostUid,
      tokenCount: tokenCount,
    );

    if (mounted) {
      final query = StringBuffer(
        'roomCode=${Uri.encodeComponent(roomCode)}&isHost=true',
      );
      if (selectedSource != null) {
        query.write('&mediaSourceId=${selectedSource.id}');
      }
      if (selectedEpisodeIds != null && selectedEpisodeIds.isNotEmpty) {
        query.write('&episodes=${Uri.encodeComponent(jsonEncode(selectedEpisodeIds))}');
      }
      context.push('/player/${_item!.id}?$query');
    }
  }

  Future<MediaSource?> _showVersionPicker() async {
    if (_item == null || !_item!.hasMultipleVersions) return null;
    return showModalBottomSheet<MediaSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择版本',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._item!.mediaSources.map((source) => ListTile(
                  leading: const Icon(Icons.movie),
                  title: Text(source.name),
                  subtitle: Text(source.displayLabel),
                  onTap: () => Navigator.pop(ctx, source),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<List<MediaItem>?> _showEpisodePicker() async {
    final selected = Set<String>.from(_episodes.map((e) => e.id));

    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '选择要一起看的集数',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            if (selected.length == _episodes.length) {
                              selected.clear();
                            } else {
                              selected.addAll(_episodes.map((e) => e.id));
                            }
                          });
                        },
                        child: Text(
                          selected.length == _episodes.length
                              ? '取消全选'
                              : '全选',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _episodes.length,
                    itemBuilder: (ctx, i) {
                      final ep = _episodes[i];
                      final isSelected = selected.contains(ep.id);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (v) {
                          setSheetState(() {
                            if (v == true) {
                              selected.add(ep.id);
                            } else {
                              selected.remove(ep.id);
                            }
                          });
                        },
                        secondary: SizedBox(
                          width: 48,
                          height: 32,
                          child: EmbyImage(
                            url: ep.posterUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          'S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0} - ${ep.name}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        '已选 ${selected.length} 集',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () {
                                final result = _episodes
                                    .where((e) => selected.contains(e.id))
                                    .toList();
                                Navigator.pop(ctx, result);
                              },
                        child: const Text('确认'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<int?> _showTokenCountDialog() async {
    final controller = TextEditingController(text: '10');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('建房设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('预签 Token 数量', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              '决定最多可容纳多少观众加入',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null && n > 0 && n <= 100) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDetails,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
      bottomNavigationBar:
          _item != null ? _buildBottomBar() : null,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  MediaSource? source;
                  if (_item!.hasMultipleVersions) {
                    source = await _showVersionPicker();
                    if (source == null) return;
                  }
                  final query = StringBuffer();
                  if (source != null) {
                    query.write('mediaSourceId=${source.id}');
                  }
                  final suffix = query.isNotEmpty ? '?$query' : '';
                  if (mounted) {
                    context.push('/player/${_item!.id}$suffix');
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始播放'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _createRoom,
                icon: const Icon(Icons.group_add),
                label: const Text('建房'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_item == null) return const SizedBox();
    final item = _item!;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                EmbyImage(
                  url: item.backdropUrl ?? item.posterUrl,
                  fit: BoxFit.cover,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                        Colors.black.withValues(alpha: 0.9),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.communityRating != null) ...[
                            const Icon(Icons.star, size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              item.communityRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                          if (item.year != null)
                            Text(
                              item.year!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          if (item.runtimeText != null) ...[
                            const SizedBox(width: 16),
                            Text(
                              item.runtimeText!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.genres.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: item.genres
                        .map((g) => Chip(
                              label: Text(g, style: const TextStyle(fontSize: 13)),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                if (item.overview != null && item.overview!.isNotEmpty) ...[
                  const Text(
                    '简介',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    firstChild: Text(
                      item.overview!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    secondChild: Text(
                      item.overview!,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    crossFadeState: _overviewExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                  if (item.overview!.length > 100)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _overviewExpanded = !_overviewExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _overviewExpanded ? '收起' : '更多',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
                if (item.mediaStreams.isNotEmpty) ...[
                  _buildMediaInfo(item),
                  const SizedBox(height: 20),
                ],
                if (item.hasMultipleVersions) ...[
                  _buildMediaSources(item),
                  const SizedBox(height: 20),
                ],
                if (_episodes.isNotEmpty) ...[
                  const Text(
                    '剧集',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._episodes.map((ep) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0} - ${ep.name}',
                        ),
                        subtitle: ep.overview != null
                            ? Text(ep.overview!,
                                maxLines: 2, overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: () => context.push('/player/${ep.id}'),
                      )),
                  const SizedBox(height: 20),
                ],
                if (_similarItems.isNotEmpty) ...[
                  const Text(
                    '相似推荐',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _similarItems.length,
                      itemBuilder: (context, index) {
                        final sim = _similarItems[index];
                        return SizedBox(
                          width: 110,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _SimilarCard(
                              item: sim,
                              onTap: () {
                                context.push('/detail/${sim.id}');
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSources(MediaItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '可用版本',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...item.mediaSources.map((source) => Card(
              child: ListTile(
                leading: const Icon(Icons.movie_creation_outlined),
                title: Text(source.name),
                subtitle: Text(source.displayLabel),
                dense: true,
              ),
            )),
      ],
    );
  }

  Widget _buildMediaInfo(MediaItem item) {
    final videoStreams =
        item.mediaStreams.where((s) => s.type == 'Video').toList();
    final audioStreams =
        item.mediaStreams.where((s) => s.type == 'Audio').toList();
    final subtitleStreams =
        item.mediaStreams.where((s) => s.type == 'Subtitle').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (videoStreams.isNotEmpty)
          _MediaInfoRow(
            label: '版本：',
            value: videoStreams.first.displayInfo,
          ),
        if (audioStreams.isNotEmpty)
          _MediaInfoRow(
            label: '音频：',
            value: audioStreams.map((s) => s.displayInfo).join('，'),
          ),
        if (subtitleStreams.isNotEmpty)
          _MediaInfoRow(
            label: '字幕：',
            value: subtitleStreams.map((s) => s.displayInfo).join('，'),
          ),
      ],
    );
  }
}

class _MediaInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _MediaInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  const _SimilarCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
                  if (item.communityRating != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              item.communityRating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

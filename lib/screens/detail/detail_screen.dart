import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/room_service.dart';

final roomServiceProvider = Provider<RoomService>((ref) => RoomService());

class DetailScreen extends ConsumerStatefulWidget {
  final String itemId;

  const DetailScreen({super.key, required this.itemId});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  MediaItem? _item;
  List<MediaItem> _episodes = [];
  bool _isLoading = true;
  String? _error;

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

      if (item != null && item.isSeries) {
        final episodes = await embyService.getItems(
          parentId: widget.itemId,
          includeItemTypes: 'Episode',
        );
        setState(() => _episodes = episodes);
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

    final roomService = ref.read(roomServiceProvider);
    final room = await roomService.createRoom(
      mediaItemId: _item!.id,
      mediaItemName: _item!.name,
      mediaItemPosterUrl: _item!.posterUrl,
      hostId: 'user-${DateTime.now().millisecondsSinceEpoch}',
      hostName: '房主',
    );

    if (room != null && mounted) {
      context.push('/player/${_item!.id}?roomId=${room.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_item == null) return const SizedBox();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: _item!.backdropUrl != null
                ? Image.network(
                    _item!.backdropUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildBackdropPlaceholder(),
                  )
                : _buildBackdropPlaceholder(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _item!.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_item!.year != null)
                      Text(_item!.year!, style: TextStyle(color: Colors.grey[400])),
                    const SizedBox(width: 16),
                    if (_item!.officialRating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_item!.officialRating!),
                      ),
                    const SizedBox(width: 16),
                    if (_item!.communityRating != null)
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(_item!.communityRating!.toStringAsFixed(1)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_item!.overview != null)
                  Text(
                    _item!.overview!,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _createRoom,
                    icon: const Icon(Icons.group_add),
                    label: const Text('发起房间'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_episodes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    '剧集',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._episodes.map((ep) => ListTile(
                        title: Text(
                          'S${ep.parentIndexNumber ?? 0}E${ep.indexNumber ?? 0} - ${ep.name}',
                        ),
                        subtitle: ep.overview != null
                            ? Text(ep.overview!, maxLines: 2, overflow: TextOverflow.ellipsis)
                            : null,
                        onTap: () => context.push('/player/${ep.id}'),
                      )),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackdropPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.movie, size: 64, color: Colors.grey),
      ),
    );
  }
}

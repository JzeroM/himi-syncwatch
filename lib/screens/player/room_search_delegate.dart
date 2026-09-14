import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

class RoomSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  final WidgetRef ref;
  final String roomCode;
  RoomSearchDelegate(this.ref, {required this.roomCode});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.length < 1) {
      return const Center(child: Text('输入关键词搜索资源'));
    }
    return FutureBuilder<List<MediaItem>>(
      future: ref.read(embyServiceProvider).searchItems(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('未找到结果'));
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: SizedBox(
                width: 50,
                height: 70,
                child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
              ),
              title: Text(item.name),
              subtitle: Text(item.year ?? ''),
              onTap: () {
                close(context, {
                  'itemId': item.id,
                  'name': item.name,
                  'poster': item.posterUrl ?? '',
                  'year': item.year ?? '',
                });
              },
            );
          },
        );
      },
    );
  }
}

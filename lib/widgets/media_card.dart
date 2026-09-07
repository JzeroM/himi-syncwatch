import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

class MediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool compact;
  final Size? fixedSize;

  const MediaCard({
    super.key,
    required this.item,
    this.onTap,
    this.compact = false,
    this.fixedSize,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EmbyImage(
                url: item.posterUrl,
                fit: BoxFit.cover,
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.year != null) ...[
                          Text(
                            item.year!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (item.officialRating != null)
                          Text(
                            item.officialRating!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[400],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            if (compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (fixedSize != null) {
      return SizedBox(
        width: fixedSize!.width,
        height: fixedSize!.height,
        child: card,
      );
    }
    return card;
  }
}

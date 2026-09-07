import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

class EmbyImage extends ConsumerWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? errorWidget;
  final Widget? placeholder;

  const EmbyImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context, final WidgetRef ref) {
    if (url == null || url!.isEmpty) {
      return errorWidget ?? _defaultError();
    }

    final config = ref.watch(embyConfigProvider);
    final token = config?.accessToken;

    final headers = <String, String>{
      if (token != null) 'X-Emby-Token': token,
    };

    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: headers,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) =>
          placeholder ??
          Container(
            color: Colors.grey[850],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      errorWidget: (_, __, ___) => errorWidget ?? _defaultError(),
    );
  }

  Widget _defaultError() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.movie, size: 48, color: Colors.grey),
      ),
    );
  }
}

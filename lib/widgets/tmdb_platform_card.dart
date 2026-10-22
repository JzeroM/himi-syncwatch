import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

class TmdbPlatformCard extends StatelessWidget {
  const TmdbPlatformCard({
    super.key,
    required this.platform,
    required this.onTap,
    this.width = 170,
    this.height = 84,
  });

  final TmdbPlatform platform;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        radius: 18,
        onTap: onTap,
        child: GlassContainer(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          showShadow: false,
          child: Center(
            child: Image.asset(
              platform.logoAsset,
              key: ValueKey('tmdbPlatformLogo_${platform.providerId}'),
              height: 30,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                return _PlatformName(name: platform.name);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformName extends StatelessWidget {
  const _PlatformName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 流媒体平台卡：品牌 Logo（TMDB watch provider），无 Logo 时显示名称。
class TmdbPlatformCard extends StatelessWidget {
  const TmdbPlatformCard({
    super.key,
    required this.platform,
    required this.imageBase,
    required this.logoPath,
    required this.onTap,
    this.width = 150,
    this.height = 84,
  });

  final TmdbPlatform platform;
  final String imageBase;
  final String? logoPath;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final logoUrl = TmdbService.imageUrl(imageBase, logoPath, size: 'w300');
    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        radius: 14,
        onTap: onTap,
        child: GlassContainer(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.all(10),
          child: Center(
            child: logoUrl == null
                ? Text(
                    platform.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : TmdbImage(
                    url: logoUrl,
                    fit: BoxFit.contain,
                    cacheWidth:
                        (width * MediaQuery.devicePixelRatioOf(context)).round(),
                    placeholder: const SizedBox.shrink(),
                    errorWidget: Text(
                      platform.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

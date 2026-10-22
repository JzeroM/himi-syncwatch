import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 流媒体平台卡：品牌 Logo 作为底图铺满卡片，前景再叠清晰 Logo。
///
/// TMDB 只提供透明品牌 Logo，没有平台封面；直接把 Logo `contain` 进卡片
/// 会留下大片空白。这里用同一张 Logo 放大模糊铺底填满视觉，再压一层暗色
/// 蒙罩，前景 Logo 保持 `contain` 完整不变形。
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
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        radius: 14,
        onTap: onTap,
        child: GlassContainer(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF3A3D49).withValues(alpha: 0.78),
                      const Color(0xFF17181E).withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
              if (logoUrl != null) ...[
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Transform.scale(
                    scale: 1.35,
                    child: Opacity(
                      opacity: 0.55,
                      child: TmdbImage(
                        key: ValueKey(
                            'tmdbPlatformBackdrop_${platform.providerId}'),
                        url: logoUrl,
                        fit: BoxFit.cover,
                        cacheWidth: (width * dpr * 1.4).round(),
                        placeholder: const SizedBox.shrink(),
                        errorWidget: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x55000000),
                        Color(0x99000000),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 20,
                  ),
                  child: TmdbImage(
                    key: ValueKey('tmdbPlatformLogo_${platform.providerId}'),
                    url: logoUrl,
                    fit: BoxFit.contain,
                    cacheWidth: (width * dpr).round(),
                    placeholder: const SizedBox.shrink(),
                    errorWidget: _name(),
                  ),
                ),
              ] else
                Center(child: _name()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _name() {
    return Text(
      platform.name,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

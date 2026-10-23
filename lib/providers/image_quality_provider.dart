import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/services/hero_image_selector.dart';
import 'package:himi_syncwatch/services/image_size_probe.dart';

final imageSizeProbeProvider = Provider<ImageSizeProbe>((ref) {
  return ImageSizeProbe();
});

final heroImageSelectorProvider = Provider<HeroImageSelector>((ref) {
  return HeroImageSelector(probe: ref.watch(imageSizeProbeProvider));
});

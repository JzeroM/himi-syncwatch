import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class HimiImageCacheManager extends CacheManager with ImageCacheManager {
  HimiImageCacheManager._() : super(Config(isolatedKey));

  static const isolatedKey = 'himiCachedImageData';
  static const mobileDefaultKey = 'libCachedImageData';

  static final HimiImageCacheManager instance = HimiImageCacheManager._();

  static bool get useIsolatedKey =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static String get activeKey =>
      useIsolatedKey ? isolatedKey : mobileDefaultKey;

  static BaseCacheManager get activeManager =>
      CachedNetworkImageProvider.defaultCacheManager;

  static void install() {
    if (useIsolatedKey) {
      CachedNetworkImageProvider.defaultCacheManager = instance;
    }
  }
}

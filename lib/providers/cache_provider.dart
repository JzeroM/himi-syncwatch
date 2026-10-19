import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/services/cache/app_cache_service.dart';

final appCacheServiceProvider = Provider<CacheService>(
  (ref) => AppCacheService(),
);

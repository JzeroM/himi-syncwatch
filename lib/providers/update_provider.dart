import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/services/update/update_service.dart';

/// 检测更新服务（测试可 override 注入 fake）。
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

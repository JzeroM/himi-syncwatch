import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_service.dart';
import '../log_service.dart';

class UpdatePackageCleaner {
  const UpdatePackageCleaner({this.temporaryDirectory});

  final Future<Directory> Function()? temporaryDirectory;

  Future<int> cleanup({required String currentVersion}) async {
    final version = currentVersion.trim();
    if (version.isEmpty) return 0;

    final temp = await (temporaryDirectory ?? getTemporaryDirectory)();
    final updatesDir =
        Directory('${temp.path}${Platform.pathSeparator}updates');
    if (!await updatesDir.exists()) return 0;

    var removed = 0;
    await for (final entity in updatesDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (!name.startsWith('himi-sync-')) continue;
      final asset = parseRemoteAsset(name);
      if (asset == null) continue;
      if (compareVersions(asset.version, version) > 0) continue;
      try {
        await entity.delete();
        removed++;
      } catch (e) {
        LogService().log('Update', '清理已安装更新包失败: $name $e');
      }
    }
    if (removed > 0) {
      LogService().log('Update', '已清理 $removed 个已安装更新包');
    }
    return removed;
  }
}

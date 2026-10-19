import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:himi_syncwatch/services/log_service.dart';

/// 更新包目标平台。
enum UpdateTarget { android, windows, ios }

/// 远端目录里的一个可更新资产（版本信息从文件名解析，无需维护清单）。
class RemoteAsset {
  const RemoteAsset({
    required this.name,
    required this.version,
    required this.target,
    this.abi,
    this.size = 0,
    this.md5,
  });

  /// 文件名（如 `himi-sync-1.2.30-arm64-v8a.apk`）。
  final String name;

  /// 语义版本（`major.minor.patch`，忽略 `+构建号`）。
  final String version;

  final UpdateTarget target;

  /// Android 专属：`arm64-v8a` / `armeabi-v7a` / `x86_64` / `universal`。
  final String? abi;

  /// 文件字节数（列表 API 提供，0 = 未知）。
  final int size;

  /// 文件 MD5（列表 API 提供，null = 无法校验）。
  final String? md5;
}

/// 检查更新结果状态。
enum UpdateStatus {
  /// 远端有更高版本。
  available,

  /// 已是最新（或远端没有本平台资产）。
  upToDate,

  /// 网络/解析失败（静默处理，不打扰用户）。
  failed,
}

/// 检查更新结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.browseUrl,
    this.asset,
    this.error,
  });

  final UpdateStatus status;

  /// 本地当前版本（versionName）。
  final String currentVersion;

  /// OpenList 浏览页（无匹配资产时的兜底入口）。
  final String browseUrl;

  /// 命中的更高版本资产（仅 [UpdateStatus.available] 时非空）。
  final RemoteAsset? asset;

  final String? error;
}

/// DioException 消息里带上 HTTP 状态码，便于上层判断（如未知来源拦截）。
class UpdateDownloadException implements Exception {
  UpdateDownloadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'UpdateDownloadException($message, $statusCode)';
}

/// 检测更新服务：列表 API 自动发现 + 断点续传下载 + MD5 校验。
///
/// 数据源可以是任何提供 OpenList/AList 兼容 `/api/fs/list` 的实例，
/// 默认指向自建 OpenList（`/PACKAGES` 目录，匿名只读）。
class UpdateService {
  UpdateService({String? baseUrl, Dio? dio, this.downloadTimeout})
      : baseUrl = normalizeBaseUrl(baseUrl ?? defaultBaseUrl),
        _dio = dio ?? _createDio();

  /// 数据源根地址（可 `--dart-define=HIMI_UPDATE_BASE=...` 覆盖）。
  static const defaultBaseUrl = String.fromEnvironment(
    'HIMI_UPDATE_BASE',
    defaultValue: 'https://rink.eu.org',
  );

  /// 安装包所在远端目录（OpenList 的虚拟路径）。
  static const remoteDir = '/PACKAGES';

  /// 下载整体超时（测试可注入短值）。
  final Duration? downloadTimeout;

  final String baseUrl;
  final Dio _dio;

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      return HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
    };
    return dio;
  }

  static String normalizeBaseUrl(String url) {
    var v = url.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// 浏览页兜底地址。
  String get browseUrl => '$baseUrl$remoteDir';

  /// 资产下载地址（OpenList 稳定直链路径，302 到带签名的真实地址）。
  String downloadUrl(String name) => '$baseUrl/d$remoteDir/$name';

  /// 拉取远端目录资产列表（失败抛异常，由调用方决定静默或提示）。
  Future<List<RemoteAsset>> fetchAssets({CancelToken? cancelToken}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/api/fs/list',
      data: {
        'path': remoteDir,
        'password': '',
        'page': 1,
        'per_page': 200,
        'refresh': false,
      },
      options: Options(contentType: Headers.jsonContentType),
      cancelToken: cancelToken,
    );
    return assetsFromListJson(response.data);
  }

  /// 检查更新：仅当远端存在更高版本且匹配当前平台/ABI 时返回 available。
  Future<UpdateCheckResult> check({
    required String currentVersion,
    required UpdateTarget target,
    List<String> supportedAbis = const [],
    CancelToken? cancelToken,
  }) async {
    try {
      final assets = await fetchAssets(cancelToken: cancelToken);
      final asset = latestAssetFor(
        assets: assets,
        target: target,
        supportedAbis: supportedAbis,
      );
      if (asset == null ||
          compareVersions(asset.version, currentVersion) <= 0) {
        return UpdateCheckResult(
          status: UpdateStatus.upToDate,
          currentVersion: currentVersion,
          browseUrl: browseUrl,
          asset: asset,
        );
      }
      return UpdateCheckResult(
        status: UpdateStatus.available,
        currentVersion: currentVersion,
        browseUrl: browseUrl,
        asset: asset,
      );
    } catch (e) {
      LogService().log('Update', '检查更新失败: $e');
      return UpdateCheckResult(
        status: UpdateStatus.failed,
        currentVersion: currentVersion,
        browseUrl: browseUrl,
        error: e.toString(),
      );
    }
  }

  /// 下载资产到 [dir]/updates/，成功返回文件。
  ///
  /// - 已有部分文件时带 `Range` 续传（服务端返回 200 则从头重写）；
  /// - 链接过期（403/404/410）自动重取 `/d/` 直链后继续（最多 [maxAttempts] 次）；
  /// - 完成后若已知 MD5 则校验，不匹配删除文件并抛错。
  Future<File> download(
    RemoteAsset asset, {
    required Directory dir,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    int maxAttempts = 3,
  }) async {
    final updatesDir = Directory('${dir.path}/updates');
    if (!updatesDir.existsSync()) {
      updatesDir.createSync(recursive: true);
    }
    final file = File('${updatesDir.path}/${asset.name}');
    final url = downloadUrl(asset.name);

    var received = file.existsSync() ? file.lengthSync() : 0;
    // 已知大小且已下满：直接校验返回（重复点击/重启续传场景）
    if (asset.size > 0 && received >= asset.size) {
      await _verify(file, asset);
      return file;
    }

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        received = await _downloadOnce(
          url: url,
          file: file,
          startAt: received,
          expectedSize: asset.size,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        if (asset.size > 0 && received < asset.size) {
          lastError = UpdateDownloadException(
            '连接中断：$received/${asset.size}',
          );
          continue; // 续传重试
        }
        await _verify(file, asset);
        return file;
      } on UpdateDownloadException catch (e) {
        lastError = e;
        // 链接过期/资源不存在：重新走 /d/ 拿新签名地址后续传
        if (e.statusCode == 403 || e.statusCode == 404 || e.statusCode == 410) {
          received = file.existsSync() ? file.lengthSync() : 0;
          continue;
        }
        rethrow;
      } catch (e) {
        lastError = e;
        received = file.existsSync() ? file.lengthSync() : 0;
      }
    }
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
    throw UpdateDownloadException('下载失败: $lastError');
  }

  /// 单次下载尝试（含 302 跟随），返回本次结束后的已收字节数。
  Future<int> _downloadOnce({
    required String url,
    required File file,
    required int startAt,
    required int expectedSize,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final useRange = startAt > 0;
    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: useRange ? {'Range': 'bytes=$startAt-'} : null,
          validateStatus: (status) =>
              status != null &&
              (status == 200 || status == 206 || status == 416),
          followRedirects: true,
          receiveTimeout: receiveTimeoutFor(expectedSize),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw UpdateDownloadException(
        e.message ?? e.toString(),
        statusCode: e.response?.statusCode,
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 416) {
      // Range 越界：文件可能已完整，交由上层按长度校验
      return file.existsSync() ? file.lengthSync() : 0;
    }
    if (status < 200 || status >= 300) {
      throw UpdateDownloadException('HTTP $status', statusCode: status);
    }

    // 服务端忽略 Range 返回 200：从头重写
    final append = useRange && status == 206;
    var received = append ? startAt : 0;
    final body = response.data;
    if (body == null) {
      throw UpdateDownloadException('空响应体', statusCode: status);
    }

    final total = _totalFromHeaders(response.headers, received, expectedSize);
    final sink = file.openSync(mode: append ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in body.stream) {
        sink.writeFromSync(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      sink.closeSync();
    }
    return received;
  }

  int _totalFromHeaders(Headers headers, int received, int expectedSize) {
    final contentRange = headers.value('content-range');
    if (contentRange != null && contentRange.contains('/')) {
      final t = int.tryParse(contentRange.split('/').last);
      if (t != null && t > 0) return t;
    }
    final len = int.tryParse(headers.value(Headers.contentLengthHeader) ?? '');
    if (len != null && len > 0) return len + (received > 0 ? received : 0);
    return expectedSize > 0 ? expectedSize : 0;
  }

  Duration receiveTimeoutFor(int sizeBytes) {
    if (downloadTimeout != null) return downloadTimeout!;
    // 弱网 + 云盘限速：按大小给足时间（至少 5 分钟，最多 30 分钟）
    final seconds = (sizeBytes / (200 * 1024)).ceil().clamp(300, 1800);
    return Duration(seconds: seconds);
  }

  Future<void> _verify(File file, RemoteAsset asset) async {
    final expected = asset.md5?.trim().toUpperCase();
    if (expected == null || expected.isEmpty) return;
    if (asset.size > 0 && file.lengthSync() != asset.size) {
      throw UpdateDownloadException(
        '大小不符: ${file.lengthSync()}/${asset.size}',
      );
    }
    final digest =
        (await md5.bind(file.openRead()).first).toString().toUpperCase();
    if (digest != expected) {
      try {
        file.deleteSync();
      } catch (_) {}
      throw UpdateDownloadException('MD5 校验失败: $digest != $expected');
    }
  }
}

/// ------------------------------------------------------------------
/// 纯函数区（便于单测）
/// ------------------------------------------------------------------

final _androidRe = RegExp(
  r'^himi-sync-(\d+\.\d+\.\d+)-(arm64-v8a|armeabi-v7a|x86_64)\.apk$',
);
final _androidUniversalRe = RegExp(r'^himi-sync-(\d+\.\d+\.\d+)-universal\.apk$');
final _windowsRe = RegExp(r'^himi-sync-windows-(\d+\.\d+\.\d+)-setup\.exe$');
final _iosRe = RegExp(r'^himi-sync-ios-unsigned-(\d+\.\d+\.\d+)\.ipa$');

/// 从文件名解析资产（不匹配返回 null）。
RemoteAsset? parseRemoteAsset(
  String name, {
  int size = 0,
  String? md5,
}) {
  final android = _androidRe.firstMatch(name);
  if (android != null) {
    return RemoteAsset(
      name: name,
      version: android.group(1)!,
      target: UpdateTarget.android,
      abi: android.group(2),
      size: size,
      md5: md5,
    );
  }
  final universal = _androidUniversalRe.firstMatch(name);
  if (universal != null) {
    return RemoteAsset(
      name: name,
      version: universal.group(1)!,
      target: UpdateTarget.android,
      abi: 'universal',
      size: size,
      md5: md5,
    );
  }
  final windows = _windowsRe.firstMatch(name);
  if (windows != null) {
    return RemoteAsset(
      name: name,
      version: windows.group(1)!,
      target: UpdateTarget.windows,
      size: size,
      md5: md5,
    );
  }
  final ios = _iosRe.firstMatch(name);
  if (ios != null) {
    return RemoteAsset(
      name: name,
      version: ios.group(1)!,
      target: UpdateTarget.ios,
      size: size,
      md5: md5,
    );
  }
  return null;
}

/// 解析 OpenList `/api/fs/list` 响应体为资产列表（不认识的文件忽略）。
List<RemoteAsset> assetsFromListJson(Object? json) {
  if (json is! Map) return const [];
  final data = json['data'];
  if (data is! Map) return const [];
  final content = data['content'];
  if (content is! List) return const [];
  final assets = <RemoteAsset>[];
  for (final item in content) {
    if (item is! Map) continue;
    final name = item['name'];
    if (name is! String) continue;
    final hashInfo = item['hash_info'];
    final md5 = hashInfo is Map ? hashInfo['md5'] as String? : null;
    final size = (item['size'] as num?)?.toInt() ?? 0;
    final asset = parseRemoteAsset(name, size: size, md5: md5);
    if (asset != null) assets.add(asset);
  }
  return assets;
}

/// 版本比较：`a > b` 返回 1，`a < b` 返回 -1，相等返回 0。
/// 仅比较 major/minor/patch 三段数字（忽略 `v` 前缀与 `+build` 后缀）。
int compareVersions(String a, String b) {
  final pa = _versionParts(a);
  final pb = _versionParts(b);
  for (var i = 0; i < 3; i++) {
    final d = pa[i] - pb[i];
    if (d != 0) return d > 0 ? 1 : -1;
  }
  return 0;
}

List<int> _versionParts(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first.split('-').first;
  final parts = s.split('.');
  return [
    for (var i = 0; i < 3; i++)
      i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
  ];
}

/// 选出目标平台下版本最高的资产；Android 按 [supportedAbis] 顺序匹配 ABI，
/// 依次回退 `arm64-v8a` → `armeabi-v7a` → `universal`。
RemoteAsset? latestAssetFor({
  required List<RemoteAsset> assets,
  required UpdateTarget target,
  List<String> supportedAbis = const [],
}) {
  var best = <String, RemoteAsset>{};
  for (final a in assets) {
    if (a.target != target) continue;
    final cur = best[a.version];
    if (cur == null || _abiScore(a, supportedAbis) < _abiScore(cur, supportedAbis)) {
      best[a.version] = a;
    }
  }
  if (best.isEmpty) return null;
  final version = best.keys.reduce(
    (a, b) => compareVersions(a, b) >= 0 ? a : b,
  );
  return best[version];
}

/// ABI 偏好分（越小越优先）；不匹配设备 ABI 的返回 100 以免被选中。
int _abiScore(RemoteAsset a, List<String> supportedAbis) {
  if (a.target != UpdateTarget.android) return 0;
  final abi = a.abi ?? '';
  final idx = supportedAbis.indexOf(abi);
  if (idx >= 0) return idx;
  switch (abi) {
    case 'arm64-v8a':
      return 50;
    case 'armeabi-v7a':
      return 60;
    case 'universal':
      return 70;
    default:
      return 100;
  }
}

/// 当前平台对应的更新目标（不支持的平台返回 null）。
UpdateTarget? currentUpdateTarget() {
  if (Platform.isAndroid) return UpdateTarget.android;
  if (Platform.isWindows) return UpdateTarget.windows;
  if (Platform.isIOS) return UpdateTarget.ios;
  return null;
}

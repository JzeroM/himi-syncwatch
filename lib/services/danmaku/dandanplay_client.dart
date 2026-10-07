import 'package:dio/dio.dart';

import 'danmaku_comment.dart';

/// 弹幕接口错误分类（供 UI 差异化提示）。
enum DanmakuApiError {
  /// 未配置 API 地址。
  notConfigured,

  /// 网络不可达/超时。
  network,

  /// HTTP 非 2xx。
  http,

  /// 业务失败（`success: false` 等）。
  business,

  /// 响应结构无法解析。
  invalidResponse,
}

/// 弹幕接口异常。
class DanmakuApiException implements Exception {
  final DanmakuApiError kind;
  final String message;

  const DanmakuApiException(this.kind, this.message);

  @override
  String toString() => 'DanmakuApiException(${kind.name}: $message)';
}

/// 文件识别候选条目。
class MatchCandidate {
  /// 节目编号（弹幕库 ID）。
  final int episodeId;

  final String animeTitle;
  final String episodeTitle;

  const MatchCandidate({
    required this.episodeId,
    this.animeTitle = '',
    this.episodeTitle = '',
  });
}

/// dandanplay 协议客户端（自定义 danmu_api 源，免签名）。
///
/// 兼容 LogVar `danmu_api` 与弹弹play API v2 的公开接口子集：
/// `POST {base}/api/v2/match`、`GET {base}/api/v2/comment/{episodeId}`。
/// [baseUrl] 支持含 token 路径（`http://192.168.1.7:9321/TOKEN`），
/// 拼接时仅追加 `/api/v2/...`。后续接入弹弹play 官方源时在
/// [requestHeaders] 注入点补签名头即可，方法签名无需变更。
class DandanplayClient {
  /// 用户原始输入（可能为空）。
  final String rawBaseUrl;

  final Dio _dio;

  /// 诊断用：最近一次实际请求 URL（测试断言拼接结果）。
  Uri? lastRequestUri;

  DandanplayClient({required String baseUrl, Dio? dio})
      : rawBaseUrl = baseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 15),
              ),
            );

  /// 是否已配置可用地址。
  bool get isConfigured => resolveBaseUri() != null;

  /// 归一化根地址：去尾部 `/`、无 scheme 补 `http://`、丢
  /// query/fragment；非法/空返回 null。
  static String? normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return null;
    if (url.contains(' ')) return null; // 裸空格必为非法输入
    if (!url.contains('://')) url = 'http://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // Uri.replace(query: null) 语义为「保留」而非删除，手动重建
    final clean = Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return clean.toString().replaceAll(RegExp(r'/+$'), '');
  }

  Uri? resolveBaseUri() {
    final normalized = normalizeBaseUrl(rawBaseUrl);
    return normalized == null ? null : Uri.parse(normalized);
  }

  /// 拼接请求 URI：base 可能含 token 路径（`/TOKEN`），必须**追加**
  /// 而非覆盖 path（`Uri.replace(path:)` 会丢 token，禁用）。
  Uri _buildUri(String path, {Map<String, String>? query}) {
    final base = resolveBaseUri()!;
    final uri = Uri.parse('${base.toString()}$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// 请求头注入点：当前免签返回空；接入弹弹play 官方源时在此补
  /// `X-AppId`/`X-Timestamp`/`X-Signature`。
  Map<String, String> requestHeaders(String path) => const {};

  void _requireConfigured() {
    if (!isConfigured) {
      throw const DanmakuApiException(
        DanmakuApiError.notConfigured,
        '弹幕 API 地址未配置',
      );
    }
  }

  /// 文件识别：`fileName` 必填，[fileSize] 可选。
  /// 返回按相关度排序的候选；`isMatched=true` 时仅一条（精确关联）。
  Future<List<MatchCandidate>> match({
    required String fileName,
    int? fileSize,
  }) async {
    _requireConfigured();
    const path = '/api/v2/match';
    final uri = _buildUri(path);
    lastRequestUri = uri;
    final body = <String, dynamic>{
      'fileName': fileName,
      'matchMode': 'fileNameOnly',
      if (fileSize != null) 'fileSize': fileSize,
    };
    final data = await _post(uri, path, body);
    if (data == null) {
      throw const DanmakuApiException(
        DanmakuApiError.invalidResponse,
        '文件识别响应异常',
      );
    }
    final rawMatches = data['matches'];
    if (rawMatches is! List) {
      // success:false 或缺 matches 字段
      final message = data['errorMessage'];
      throw DanmakuApiException(
        DanmakuApiError.business,
        message is String && message.isNotEmpty ? message : '文件识别失败',
      );
    }
    final out = <MatchCandidate>[];
    for (final raw in rawMatches) {
      if (raw is! Map) continue;
      final id = raw['episodeId'];
      if (id is! num) continue;
      out.add(MatchCandidate(
        episodeId: id.toInt(),
        animeTitle: raw['animeTitle'] is String ? raw['animeTitle'] : '',
        episodeTitle: raw['episodeTitle'] is String ? raw['episodeTitle'] : '',
      ));
    }
    return out;
  }

  /// 关键字搜索所有匹配剧集（`match` 未命中时的兜底，提升冷门/异名
  /// 片匹配率）。
  ///
  /// `GET {base}/api/v2/search/episodes?anime={keyword}`，响应
  /// `animes[].episodes[]`；扁平化为 [MatchCandidate]（`animeTitle`
  /// 取剧名、`episodeTitle` 取集标题），保持原顺序。
  Future<List<MatchCandidate>> searchEpisodes(String keyword) async {
    _requireConfigured();
    final query = keyword.trim();
    if (query.isEmpty) return const [];
    const path = '/api/v2/search/episodes';
    final uri = _buildUri(path, query: {'anime': query});
    lastRequestUri = uri;
    final data = await _get(uri, path);
    if (data == null) {
      throw const DanmakuApiException(
        DanmakuApiError.invalidResponse,
        '搜索响应异常',
      );
    }
    if (data['success'] == false) {
      final message = data['errorMessage'];
      throw DanmakuApiException(
        DanmakuApiError.business,
        message is String && message.isNotEmpty ? message : '搜索失败',
      );
    }
    final animes = data['animes'];
    if (animes is! List) {
      throw const DanmakuApiException(
        DanmakuApiError.invalidResponse,
        '搜索结果字段缺失',
      );
    }
    final out = <MatchCandidate>[];
    for (final anime in animes) {
      if (anime is! Map) continue;
      final animeTitle =
          anime['animeTitle'] is String ? anime['animeTitle'] as String : '';
      final episodes = anime['episodes'];
      if (episodes is! List) continue;
      for (final ep in episodes) {
        if (ep is! Map) continue;
        final id = ep['episodeId'];
        if (id is! num) continue;
        out.add(MatchCandidate(
          episodeId: id.toInt(),
          animeTitle: animeTitle,
          episodeTitle:
              ep['episodeTitle'] is String ? ep['episodeTitle'] as String : '',
        ));
      }
    }
    return out;
  }

  /// 获取弹幕（`withRelated` 聚合第三方来源；`format=json` 兼容
  /// danmu_api 显式格式参数，官方服务忽略未知参数）。
  Future<List<DanmakuComment>> fetchComments(int episodeId) async {
    _requireConfigured();
    final path = '/api/v2/comment/$episodeId';
    final uri = _buildUri(
      path,
      query: const {'withRelated': 'true', 'format': 'json'},
    );
    lastRequestUri = uri;
    final data = await _get(uri, path);
    if (data == null) {
      throw const DanmakuApiException(
        DanmakuApiError.invalidResponse,
        '弹幕响应异常',
      );
    }
    if (data['success'] == false) {
      final message = data['errorMessage'];
      throw DanmakuApiException(
        DanmakuApiError.business,
        message is String && message.isNotEmpty ? message : '获取弹幕失败',
      );
    }
    if (data['comments'] is! List) {
      throw const DanmakuApiException(
        DanmakuApiError.invalidResponse,
        '弹幕字段缺失',
      );
    }
    return DanmakuParser.parseResponse(data);
  }

  Future<Map<String, dynamic>?> _get(Uri uri, String path) async {
    try {
      final response = await _dio.getUri<Map<String, dynamic>>(
        uri,
        options: Options(headers: requestHeaders(path)),
      );
      return response.data;
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  Future<Map<String, dynamic>?> _post(
    Uri uri,
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _dio.postUri<Map<String, dynamic>>(
        uri,
        data: body,
        options: Options(headers: requestHeaders(path)),
      );
      return response.data;
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  DanmakuApiException _translate(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) {
      return DanmakuApiException(
        DanmakuApiError.http,
        'HTTP $status',
      );
    }
    // 无 response：连接失败/超时/响应解析异常
    return DanmakuApiException(
      DanmakuApiError.network,
      e.message ?? e.error?.toString() ?? '网络错误',
    );
  }
}

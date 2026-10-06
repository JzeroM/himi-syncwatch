import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:himi_syncwatch/services/remote_search/remote_search_html.dart';

/// 手机端搜索结果条目：字段由上层组装（海报为已追加访问令牌的完整地址）。
class RemoteSearchItem {
  const RemoteSearchItem({
    required this.id,
    required this.name,
    required this.serverId,
    required this.serverName,
    this.year,
    this.poster,
  });

  final String id;
  final String name;
  final String serverId;
  final String serverName;
  final String? year;
  final String? poster;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverId': serverId,
        'serverName': serverName,
        if (year != null) 'year': year,
        if (poster != null) 'poster': poster,
      };
}

/// 搜索处理器：返回该词的聚合结果（由上层注入，失败抛出转 400/500）。
typedef RemoteSearchHandler = Future<List<RemoteSearchItem>> Function(
    String query);

/// 选片处理器：返回 null 表示成功，返回字符串表示业务错误。
typedef RemoteSelectHandler = Future<String?> Function(
    String serverId, String itemId);

/// 扫码远程搜索服务（纯 Dart，不依赖 Flutter）。
///
/// 手机扫码打开 `url`（含随机 token），GET 返回搜索单页并下发会话 Cookie：
/// - `POST /api/search {q}` → [onSearch] → `{ok, results:[...]}`
/// - `POST /api/select {serverId,itemId}` → [onSelect] → 电视跳转详情
/// 服务生命周期跟随二维码页：`stop()` 后端口立即释放。
class RemoteSearchServer {
  RemoteSearchServer({
    required this.onSearch,
    required this.onSelect,
    this.basePort = 17892,
    this.portProbeCount = 10,
  });

  final RemoteSearchHandler onSearch;
  final RemoteSelectHandler onSelect;

  /// 首选端口；被占用时依次探测 `basePort + 1 ... + [portProbeCount] - 1`。
  final int basePort;
  final int portProbeCount;

  static const cookieName = 'himi_rs';

  HttpServer? _server;
  String? _token;
  int? _port;
  List<String> _ips = const [];

  bool get isRunning => _server != null;
  int? get port => _port;
  String? get token => _token;

  /// 已检测到的本机局域网 IPv4（不含回环）。
  List<String> get ips => List.unmodifiable(_ips);

  /// 手机扫码入口（多网卡时取第一个 IP，其余在页面页脚给出备选链接）。
  String? get url {
    if (!isRunning || _ips.isEmpty || _port == null || _token == null) {
      return null;
    }
    return 'http://${_ips.first}:$_port/?t=$_token';
  }

  Future<void> start() async {
    if (isRunning) return;

    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    _token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _ips = await _localIps();

    final candidates = basePort == 0
        ? [0]
        : [for (var i = 0; i < portProbeCount; i++) basePort + i];
    for (final port in candidates) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _port = _server!.port;
        break;
      } on SocketException {
        continue;
      }
    }
    if (_server == null) {
      _reset();
      throw StateError('无法绑定远程搜索端口（$basePort 起 $portProbeCount 个均被占用）');
    }

    _server!.listen(
      _handleRequest,
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _reset();
    await server?.close(force: true);
  }

  void _reset() {
    _server = null;
    _port = null;
    _token = null;
    _ips = const [];
  }

  Future<List<String>> _localIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      return [
        for (final ni in interfaces)
          for (final a in ni.addresses)
            if (!a.isLoopback) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }

  bool _authorized(HttpRequest req) {
    final token = _token;
    if (token == null) return false;
    if (req.uri.queryParameters['t'] == token) return true;
    for (final c in req.cookies) {
      if (c.name == cookieName && c.value == token) return true;
    }
    return false;
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (_server == null) return;
      final path = req.uri.path;

      if (req.method == 'GET' && (path == '/' || path.isEmpty)) {
        await _handleIndex(req);
        return;
      }
      if (!_authorized(req)) {
        await _sendJson(req, 403, {'ok': false, 'error': '无效或过期的访问令牌'});
        return;
      }
      if (req.method == 'POST' && path == '/api/search') {
        await _handleSearch(req);
        return;
      }
      if (req.method == 'POST' && path == '/api/select') {
        await _handleSelect(req);
        return;
      }
      await _sendJson(req, 404, {'ok': false, 'error': 'Not Found'});
    } catch (_) {
      try {
        await _sendJson(req, 500, {'ok': false, 'error': '服务器内部错误'});
      } catch (_) {}
    }
  }

  Future<void> _handleIndex(HttpRequest req) async {
    if (!_authorized(req)) {
      await _sendText(req, 403, '无效或过期的访问令牌，请重新扫码');
      return;
    }
    final html = buildRemoteSearchHtml(
      ips: _ips,
      port: _port ?? 0,
      token: _token ?? '',
    );
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.html;
    req.response.headers.add(
      HttpHeaders.setCookieHeader,
      '$cookieName=$_token; Path=/; SameSite=Strict',
    );
    req.response.write(html);
    await req.response.close();
  }

  Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('body must be an object');
    }
    return decoded;
  }

  Future<void> _handleSearch(HttpRequest req) async {
    Map<String, dynamic> body;
    try {
      body = await _readBody(req);
    } catch (_) {
      await _sendJson(req, 400, {'ok': false, 'error': '请求体不是合法 JSON'});
      return;
    }
    final q = body['q'];
    if (q != null && q is! String) {
      await _sendJson(req, 400, {'ok': false, 'error': 'q 必须是字符串'});
      return;
    }
    try {
      final items = await onSearch((q as String?)?.trim() ?? '');
      await _sendJson(req, 200, {
        'ok': true,
        'results': [for (final item in items) item.toJson()],
      });
    } catch (e) {
      await _sendJson(req, 400, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _handleSelect(HttpRequest req) async {
    Map<String, dynamic> body;
    try {
      body = await _readBody(req);
    } catch (_) {
      await _sendJson(req, 400, {'ok': false, 'error': '请求体不是合法 JSON'});
      return;
    }
    final serverId = body['serverId'];
    final itemId = body['itemId'];
    if (serverId is! String ||
        serverId.isEmpty ||
        itemId is! String ||
        itemId.isEmpty) {
      await _sendJson(req, 400, {'ok': false, 'error': 'serverId 与 itemId 必填'});
      return;
    }
    try {
      final error = await onSelect(serverId, itemId);
      if (error != null) {
        await _sendJson(req, 400, {'ok': false, 'error': error});
      } else {
        await _sendJson(req, 200, {'ok': true, 'message': '已在电视上打开'});
      }
    } catch (e) {
      await _sendJson(req, 400, {'ok': false, 'error': e.toString()});
    }
  }

  Future<void> _sendJson(
    HttpRequest req,
    int status,
    Map<String, dynamic> data,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(data));
    await req.response.close();
  }

  Future<void> _sendText(HttpRequest req, int status, String text) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.text;
    req.response.write(text);
    await req.response.close();
  }
}

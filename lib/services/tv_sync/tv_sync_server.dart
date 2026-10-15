import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:himi_syncwatch/models/emby_server_config.dart';

/// 配对确认回调：手机发起配对时由上层弹框，返回 true=同意（签发 token）。
typedef TvPairConfirm = Future<bool> Function(String phoneName, String ip);

/// 同步落库回调：body 里的服务器列表按 serverId upsert；返回 null 成功、
/// 字符串业务错误。
typedef TvSyncHandler = Future<String?> Function(List<EmbyServerConfig> servers);

/// TV 端局域网同步常驻服务（纯 Dart HttpServer，仿 LanConfigServer）。
///
/// - `GET  /api/info`   免鉴权：{deviceId, name}（手机验证用）
/// - `POST /api/pair`   body {phoneName} → [onPairRequest] 弹框 →
///                      同意返回 {ok, token}，拒绝 403
/// - `POST /api/sync`   header `X-Himi-Token` 鉴权；body
///                      {servers: [EmbyServerConfig JSON...]} → [onSync]
///
/// 生命周期：app 存活即常驻（tvMode=true 时由 provider 启动）。
class TvSyncServer {
  TvSyncServer({
    required this.onPairRequest,
    required this.onSync,
    required this.deviceId,
    required this.deviceName,
    this.basePort = 17894,
    this.portProbeCount = 10,
  });

  final TvPairConfirm onPairRequest;
  final TvSyncHandler onSync;
  final String deviceId;
  final String deviceName;

  final int basePort;
  final int portProbeCount;

  static const tokenHeader = 'X-Himi-Token';

  HttpServer? _server;
  String? _token;
  int? _port;

  bool get isRunning => _server != null;
  int? get port => _port;
  String? get token => _token;

  Future<void> start() async {
    if (isRunning) return;

    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    _token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

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
      throw StateError('无法绑定 TV 同步端口（$basePort 起 $portProbeCount 个均被占用）');
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
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (_server == null) return;
      final path = req.uri.path;

      if (req.method == 'GET' && path == '/api/info') {
        await _sendJson(req, 200, {
          'ok': true,
          'deviceId': deviceId,
          'name': deviceName,
        });
        return;
      }
      if (req.method == 'POST' && path == '/api/pair') {
        await _handlePair(req);
        return;
      }
      if (req.method == 'POST' && path == '/api/sync') {
        if (!_authorized(req)) {
          await _sendJson(
              req, 403, {'ok': false, 'error': '配对已失效，请重新配对'});
          return;
        }
        await _handleSync(req);
        return;
      }
      await _sendJson(req, 404, {'ok': false, 'error': 'Not Found'});
    } catch (_) {
      try {
        await _sendJson(req, 500, {'ok': false, 'error': '服务器内部错误'});
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest req) {
    final token = _token;
    if (token == null) return false;
    return req.headers.value(tokenHeader) == token ||
        req.uri.queryParameters['t'] == token;
  }

  Future<void> _handlePair(HttpRequest req) async {
    Map<String, dynamic> body;
    try {
      body = await _readJsonObject(req);
    } catch (_) {
      await _sendJson(req, 400, {'ok': false, 'error': '请求体不是合法 JSON'});
      return;
    }
    final phoneName = (body['phoneName'] as String? ?? '').trim();
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    final agreed = await onPairRequest(phoneName.isEmpty ? '未知设备' : phoneName, ip);
    if (!agreed) {
      await _sendJson(req, 403, {'ok': false, 'error': '配对被拒绝'});
      return;
    }
    await _sendJson(req, 200, {'ok': true, 'token': _token});
  }

  Future<void> _handleSync(HttpRequest req) async {
    Map<String, dynamic> body;
    try {
      body = await _readJsonObject(req);
    } catch (_) {
      await _sendJson(req, 400, {'ok': false, 'error': '请求体不是合法 JSON'});
      return;
    }
    final raw = body['servers'];
    if (raw is! List) {
      await _sendJson(req, 400, {'ok': false, 'error': '缺少 servers 数组'});
      return;
    }
    final servers = <EmbyServerConfig>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        servers.add(EmbyServerConfig.fromJson(item));
      }
    }
    if (servers.isEmpty) {
      await _sendJson(req, 400, {'ok': false, 'error': 'servers 为空或格式错误'});
      return;
    }
    try {
      final error = await onSync(servers);
      if (error != null) {
        await _sendJson(req, 400, {'ok': false, 'error': error});
      } else {
        await _sendJson(req, 200, {
          'ok': true,
          'message': '已同步 ${servers.length} 个服务器',
          'synced': servers.length,
        });
      }
    } catch (e) {
      await _sendJson(req, 400, {'ok': false, 'error': e.toString()});
    }
  }

  Future<Map<String, dynamic>> _readJsonObject(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('body must be an object');
    }
    return decoded;
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
}

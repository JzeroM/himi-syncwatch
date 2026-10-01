import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:himi_syncwatch/services/lan_config/lan_config_html.dart';

/// 业务处理器：入参为 JSON body；返回 null 表示成功，返回字符串表示业务错误。
typedef LanConfigHandler = Future<String?> Function(Map<String, dynamic> body);

/// 局域网扫码配置服务（纯 Dart，不依赖 Flutter）。
///
/// 手机扫码打开 `url`（含随机 token），GET 返回配置页并下发会话 Cookie，
/// POST /api/emby、/api/agora 经回调交给上层（注入 [onEmby]/[onAgora]）落库。
/// 服务生命周期跟随二维码页：`stop()` 后端口立即释放。
class LanConfigServer {
  LanConfigServer({
    required this.onEmby,
    required this.onAgora,
    this.basePort = 17890,
    this.portProbeCount = 10,
  });

  final LanConfigHandler onEmby;
  final LanConfigHandler onAgora;

  /// 首选端口；被占用时依次探测 `basePort + 1 ... + [portProbeCount] - 1`。
  final int basePort;
  final int portProbeCount;

  static const cookieName = 'himi_cfg';

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
      throw StateError('无法绑定局域网配置端口（$basePort 起 $portProbeCount 个均被占用）');
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
      if (req.method == 'POST' && path == '/api/emby') {
        await _handleAction(req, onEmby, success: 'Emby 服务器已连接并激活');
        return;
      }
      if (req.method == 'POST' && path == '/api/agora') {
        await _handleAction(req, onAgora, success: '声网配置已保存');
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
    final html = buildLanConfigHtml(
      ips: _ips,
      port: _port ?? 0,
      token: _token ?? '',
      mode: req.uri.queryParameters['mode'] ?? '',
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

  Future<void> _handleAction(
    HttpRequest req,
    LanConfigHandler handler, {
    required String success,
  }) async {
    Map<String, dynamic> body;
    try {
      final raw = await utf8.decoder.bind(req).join();
      final decoded = jsonDecode(raw.isEmpty ? '{}' : raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('body must be an object');
      }
      body = decoded;
    } catch (_) {
      await _sendJson(req, 400, {'ok': false, 'error': '请求体不是合法 JSON'});
      return;
    }

    try {
      final error = await handler(body);
      if (error != null) {
        await _sendJson(req, 400, {'ok': false, 'error': error});
      } else {
        await _sendJson(req, 200, {'ok': true, 'message': success});
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

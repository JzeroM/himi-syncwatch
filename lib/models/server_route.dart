import 'dart:math';

/// 服务器备用线路：与主线路（`EmbyServerConfig.serverUrl`）指向同一
/// Emby 实例的另一访问地址（不同域名/IP/端口/反代）。
class ServerRoute {
  const ServerRoute({
    required this.id,
    required this.name,
    required this.url,
    this.isReverseProxy = false,
  });

  final String id;
  final String name;
  final String url;

  /// 将此线路作为主线路的反向代理：激活时 API 走本线路 URL、
  /// 媒体流量（取流/字幕/图片）直连主线路（省反代带宽）。
  final bool isReverseProxy;

  ServerRoute copyWith({String? name, String? url, bool? isReverseProxy}) {
    return ServerRoute(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      isReverseProxy: isReverseProxy ?? this.isReverseProxy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'isReverseProxy': isReverseProxy,
      };

  factory ServerRoute.fromJson(Map<String, dynamic> json) {
    return ServerRoute(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      isReverseProxy: json['isReverseProxy'] as bool? ?? false,
    );
  }

  /// 新建线路的默认名：`Route N`（N = 当前线路数 + 1，防重后递增）。
  static String defaultName(Iterable<ServerRoute> existing) {
    final used = existing.map((r) => r.name).toSet();
    var n = existing.length + 1;
    while (used.contains('Route $n')) {
      n++;
    }
    return 'Route $n';
  }

  /// 新建线路的默认 id（列表内唯一即可，无需全局稳定）。
  static String newId(Iterable<ServerRoute> existing) {
    final used = existing.map((r) => r.id).toSet();
    var id = 'rt_${Random().nextInt(0xFFFFFF).toRadixString(16)}';
    while (used.contains(id)) {
      id = 'rt_${Random().nextInt(0xFFFFFF).toRadixString(16)}';
    }
    return id;
  }
}

final _whitespace = RegExp(r'\s');
final _digits = RegExp(r'^\d+$');

/// 规范化端口：空串表示不写端口；非法（非数字/越界）返回 null。
String? _normalizePort(String raw) {
  final p = raw.trim();
  if (p.isEmpty) return '';
  if (!_digits.hasMatch(p)) return null;
  final n = int.tryParse(p);
  if (n == null || n < 1 || n > 65535) return null;
  return '$n';
}

/// 编码 IPv6 zone id：`fe80::1%eth0` → `fe80::1%25eth0`。
/// 输入已带 `%25` 时先还原，避免二次编码。
String _encodeIpv6Zone(String host) =>
    host.replaceAll('%25', '%').replaceAll('%', '%25');

/// 规范化 host：IPv6 自动补方括号；IPv4/域名原样返回。
String? _normalizeHost(String raw) {
  var h = raw.trim();
  if (h.isEmpty || h.contains('://') || _whitespace.hasMatch(h)) return null;
  if (h.contains('/') ||
      h.contains('?') ||
      h.contains('#') ||
      h.contains('@')) {
    return null;
  }

  final hasOpen = h.startsWith('[');
  final hasClose = h.endsWith(']');
  if (hasOpen || hasClose) {
    if (!hasOpen || !hasClose) return null;
    h = h.substring(1, h.length - 1);
  }
  if (h.isEmpty || h.contains('[') || h.contains(']')) return null;

  if (!h.contains(':')) return h; // IPv4 / 域名

  final encoded = _encodeIpv6Zone(h);
  final probe = Uri.tryParse('http://[$encoded]');
  if (probe == null || probe.host.isEmpty) return null;
  return '[$encoded]';
}

/// 输入是否像完整服务器地址（用于粘贴后自动拆分）。
///
/// 单纯域名、单纯 `[IPv6]` 不算完整地址，避免覆盖默认端口；
/// 带 scheme、path、端口则视为完整地址。
bool looksLikeFullServerUrl(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t.contains('://') || t.contains('/')) return true;

  if (t.startsWith('[')) {
    final close = t.indexOf(']');
    if (close <= 1) return false;
    final rest = t.substring(close + 1);
    return rest.startsWith(':') && rest.length > 1;
  }

  final colon = t.indexOf(':');
  if (colon <= 0 || colon != t.lastIndexOf(':')) return false;
  final port = t.substring(colon + 1);
  return port.isNotEmpty && int.tryParse(port) != null;
}

/// 从分项字段拼服务器基地址。
///
/// - [host] 可填 IPv4、域名或 IPv6（裸地址/方括号均可），非法返回 null；
/// - [port] 空表示不写端口；非空必须是 1-65535；
/// - [path] 可选，自动补前导 `/`、去尾 `/`；
/// - [useHttps] 决定 scheme。
///
/// 例：`buildServerUrl(host: '192.168.1.100', port: '8096', useHttps: false)
///     == 'http://192.168.1.100:8096'`；
///     `buildServerUrl(host: '2408::1', port: '8096')
///     == 'http://[2408::1]:8096'`。
String? buildServerUrl({
  required String host,
  String? port,
  String? path,
  bool useHttps = false,
}) {
  final h = _normalizeHost(host);
  if (h == null) return null;

  final p = _normalizePort(port ?? '');
  if (p == null) return null;

  final scheme = useHttps ? 'https' : 'http';
  final portPart = p.isEmpty ? '' : ':$p';

  var pathPart = path?.trim() ?? '';
  if (pathPart.isNotEmpty && !pathPart.startsWith('/')) {
    pathPart = '/$pathPart';
  }
  if (pathPart.endsWith('/')) {
    pathPart = pathPart.substring(0, pathPart.length - 1);
  }

  return '$scheme://$h$portPart$pathPart';
}

/// [buildServerUrl] 的逆运算：解析服务器基地址为分项字段。
///
/// - 支持带/不带 scheme（缺省按 http）；
/// - 支持 `[IPv6]` / `[IPv6]:port`，裸 IPv6 视为非法；
/// - 非法输入（空/空格/非法端口/未闭合括号）返回 null；
/// - path 返回不带前导 `/` 的形式（与添加表单输入框习惯一致），
///   例：`http://1.2.3.4:8096/emby` → path `'emby'`。
({String host, String port, String path, bool useHttps})? parseServerUrl(
  String url,
) {
  var u = url.trim();
  if (u.isEmpty || _whitespace.hasMatch(u)) return null;

  var useHttps = false;
  if (u.startsWith('https://')) {
    useHttps = true;
    u = u.substring('https://'.length);
  } else if (u.startsWith('http://')) {
    u = u.substring('http://'.length);
  } else if (u.contains('://')) {
    return null; // 其他 scheme 不支持
  }

  // 拆 path（第一个 `/` 起）
  var path = '';
  final slash = u.indexOf('/');
  if (slash >= 0) {
    path = u.substring(slash + 1);
    u = u.substring(0, slash);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  if (u.isEmpty || u.contains('@')) return null;

  var host = u;
  var port = '';
  if (u.startsWith('[')) {
    final close = u.indexOf(']');
    if (close <= 1) return null;
    host = u.substring(1, close);
    if (!host.contains(':')) return null;

    final rest = u.substring(close + 1);
    if (rest.isNotEmpty) {
      if (!rest.startsWith(':')) return null;
      port = rest.substring(1);
      if (port.isEmpty) return null;
    }

    final probe = Uri.tryParse('http://[${_encodeIpv6Zone(host)}]');
    if (probe == null) return null;
  } else {
    final colon = u.indexOf(':');
    if (colon >= 0) {
      // 无方括号且出现多个冒号 => 裸 IPv6，不允许。
      if (colon != u.lastIndexOf(':') || colon == 0) return null;
      host = u.substring(0, colon);
      port = u.substring(colon + 1);
      if (port.isEmpty) return null;
    }
  }
  if (host.isEmpty) return null;

  final normalizedPort = _normalizePort(port);
  if (normalizedPort == null) return null;

  return (
    host: host.replaceAll('%25', '%'),
    port: normalizedPort,
    path: path,
    useHttps: useHttps,
  );
}

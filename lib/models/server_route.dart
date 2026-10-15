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

/// 从分项字段拼服务器基地址。
///
/// - [host] 只填 ip 或域名（已 trim），非法（空/含 `://`/空格）返回 null；
/// - [port] 空或非法不拼端口段；默认调用方传 `'8096'`；
/// - [path] 可选，自动补前导 `/`、去尾 `/`；
/// - [useHttps] 决定 scheme。
///
/// 例：`buildServerUrl(host: '192.168.1.100', port: '8096', useHttps: false)
///     == 'http://192.168.1.100:8096'`。
String? buildServerUrl({
  required String host,
  String? port,
  String? path,
  bool useHttps = false,
}) {
  final h = host.trim();
  if (h.isEmpty || h.contains('://') || h.contains(' ')) return null;

  final scheme = useHttps ? 'https' : 'http';
  final p = port?.trim() ?? '';
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
/// - 非法输入（空/含空格/非法端口）返回 null；
/// - path 返回不带前导 `/` 的形式（与添加表单输入框习惯一致），
///   例：`http://1.2.3.4:8096/emby` → path `'emby'`。
({String host, String port, String path, bool useHttps})? parseServerUrl(
  String url,
) {
  var u = url.trim();
  if (u.isEmpty || u.contains(' ')) return null;

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

  // 拆 host:port（IPv6 字面量不支持，Emby 内网场景罕见）
  var host = u;
  var port = '';
  final colon = u.indexOf(':');
  if (colon >= 0) {
    host = u.substring(0, colon);
    port = u.substring(colon + 1);
    if (port.isNotEmpty && int.tryParse(port) == null) return null;
  }
  if (host.isEmpty) return null;

  return (host: host, port: port, path: path, useHttps: useHttps);
}

/// 弹幕服务器（P5）。
///
/// ## 为什么需要「多个」
///
/// 之前只有一个 `danmakuApiUrl`：换源必须覆盖旧地址，且无法保留备用。
/// 现在把地址升级为**服务器列表**（每个条目 = 一个弹幕 API 端点），
/// 支持启用/停用与优先级，为后续多源检索（P2）留出扩展位。
///
/// ## 兼容
///
/// 老配置只有 `danmakuApiUrl`：升级时自动迁移成一条 `custom` 服务器，
/// 旧字段保留（只读兜底），因此降级回旧版本也不会丢地址。
class DanmakuServer {
  const DanmakuServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.type = 'custom',
    this.token,
    this.enabled = true,
    this.priority = 0,
  });

  /// 稳定标识（本地生成；用于列表 key 与备份还原）。
  final String id;

  /// 展示名。
  final String name;

  /// API 根地址（可含 token 路径）。
  final String baseUrl;

  /// 类型：`custom`（自建 danmu_api / 弹弹play 兼容端点）或 `dandanplay`。
  final String type;

  /// 可选鉴权 token（预留）。
  final String? token;

  /// 是否启用。
  final bool enabled;

  /// 优先级（越小越优先）。
  final int priority;

  DanmakuServer copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? type,
    String? token,
    bool? enabled,
    int? priority,
  }) =>
      DanmakuServer(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        type: type ?? this.type,
        token: token ?? this.token,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'type': type,
        if (token != null) 'token': token,
        'enabled': enabled,
        'priority': priority,
      };

  static DanmakuServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final baseUrl = raw['baseUrl'];
    if (baseUrl is! String || baseUrl.trim().isEmpty) return null;
    final id = raw['id'];
    return DanmakuServer(
      id: id is String && id.isNotEmpty
          ? id
          : 'srv-${baseUrl.hashCode.toUnsigned(32)}',
      name: (raw['name'] as String?)?.trim().isNotEmpty == true
          ? raw['name'] as String
          : baseUrl,
      baseUrl: baseUrl,
      type: (raw['type'] as String?) ?? 'custom',
      token: raw['token'] as String?,
      enabled: raw['enabled'] as bool? ?? true,
      priority: (raw['priority'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DanmakuServer &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.type == type &&
      other.token == token &&
      other.enabled == enabled &&
      other.priority == priority;

  @override
  int get hashCode =>
      Object.hash(id, name, baseUrl, type, token, enabled, priority);
}

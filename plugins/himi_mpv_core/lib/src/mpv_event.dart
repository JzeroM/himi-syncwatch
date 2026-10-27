import 'package:flutter/foundation.dart';

/// mpv 属性事件（原生 EventChannel 负载的强类型视图）。
@immutable
class MpvPropertyEvent {
  const MpvPropertyEvent(this.name, this.value);

  final String name;
  final Object? value;

  static MpvPropertyEvent? tryParse(Map<Object?, Object?> raw) {
    if (raw['type'] != 'property') return null;
    final name = raw['name'];
    if (name is! String) return null;
    return MpvPropertyEvent(name, raw['value']);
  }
}

/// mpv 事件（MPV_EVENT_*）。
@immutable
class MpvEvent {
  const MpvEvent(this.id, this.name);

  final int id;
  final String name;

  static MpvEvent? tryParse(Map<Object?, Object?> raw) {
    if (raw['type'] != 'event') return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! int || name is! String) return null;
    return MpvEvent(id, name);
  }
}

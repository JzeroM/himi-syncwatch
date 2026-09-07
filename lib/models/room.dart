class Room {
  final String id;
  final String mediaItemId;
  final String mediaItemName;
  final String? mediaItemPosterUrl;
  final String hostId;
  final String hostName;
  final List<RoomMember> members;
  final DateTime createdAt;
  final bool isPlaying;
  final double position;
  final double playbackRate;

  Room({
    required this.id,
    required this.mediaItemId,
    required this.mediaItemName,
    this.mediaItemPosterUrl,
    required this.hostId,
    required this.hostName,
    this.members = const [],
    required this.createdAt,
    this.isPlaying = false,
    this.position = 0,
    this.playbackRate = 1.0,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'] ?? '',
      mediaItemId: json['mediaItemId'] ?? '',
      mediaItemName: json['mediaItemName'] ?? '',
      mediaItemPosterUrl: json['mediaItemPosterUrl'],
      hostId: json['hostId'] ?? '',
      hostName: json['hostName'] ?? '',
      members: (json['members'] as List<dynamic>?)
              ?.map((m) => RoomMember.fromJson(m))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isPlaying: json['isPlaying'] ?? false,
      position: (json['position'] ?? 0).toDouble(),
      playbackRate: (json['playbackRate'] ?? 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaItemId': mediaItemId,
      'mediaItemName': mediaItemName,
      'mediaItemPosterUrl': mediaItemPosterUrl,
      'hostId': hostId,
      'hostName': hostName,
      'members': members.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isPlaying': isPlaying,
      'position': position,
      'playbackRate': playbackRate,
    };
  }
}

class RoomMember {
  final String id;
  final String name;
  final bool isHost;
  final DateTime joinedAt;

  RoomMember({
    required this.id,
    required this.name,
    this.isHost = false,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isHost: json['isHost'] ?? false,
      joinedAt: DateTime.parse(json['joinedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isHost': isHost,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }
}

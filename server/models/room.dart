class Room {
  final String id;
  final String mediaItemId;
  final String mediaItemName;
  final String? mediaItemPosterUrl;
  String hostId;
  String hostName;
  final List<RoomMember> members;
  final DateTime createdAt;
  bool isPlaying;
  double position;
  double playbackRate;

  Room({
    required this.id,
    required this.mediaItemId,
    required this.mediaItemName,
    this.mediaItemPosterUrl,
    required this.hostId,
    required this.hostName,
    List<RoomMember>? members,
    DateTime? createdAt,
    this.isPlaying = false,
    this.position = 0,
    this.playbackRate = 1.0,
  })  : members = members ?? [],
        createdAt = createdAt ?? DateTime.now();

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
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
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
    DateTime? joinedAt,
  }) : joinedAt = joinedAt ?? DateTime.now();

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isHost: json['isHost'] ?? false,
      joinedAt: json['joinedAt'] != null
          ? DateTime.parse(json['joinedAt'])
          : DateTime.now(),
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

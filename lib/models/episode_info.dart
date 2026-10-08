/// 播放器剧集条目（纯数据；从播放器/房间消息构建）。
class EpisodeInfo {
  final String id;
  final String name;
  final int season;
  final int number;
  final String poster;
  final String seriesName;
  final String? mediaSourceId;

  /// 来源服务器本地配置 id；null = 当前激活服务器。
  final String? serverId;

  const EpisodeInfo({
    required this.id,
    required this.name,
    this.season = 0,
    this.number = 0,
    this.poster = '',
    this.seriesName = '',
    this.mediaSourceId,
    this.serverId,
  });

  bool get isMovie => season == 0 && number == 0 && seriesName.isEmpty;
}

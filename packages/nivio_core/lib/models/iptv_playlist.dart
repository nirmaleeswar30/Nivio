class IptvPlaylist {
  final String id;
  final String name;

  /// M3U: the playlist URL. Xtream: the server address.
  final String url;

  /// 'm3u' or 'xtream'.
  final String type;

  /// Xtream only. The password is kept in secure storage, not here.
  final String? username;

  IptvPlaylist({
    required this.id,
    required this.name,
    required this.url,
    this.type = 'm3u',
    this.username,
  });

  bool get isXtream => type == 'xtream';

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) {
    return IptvPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      type: (json['type'] as String?) ?? 'm3u',
      username: json['username'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type,
      if (username != null) 'username': username,
    };
  }
}

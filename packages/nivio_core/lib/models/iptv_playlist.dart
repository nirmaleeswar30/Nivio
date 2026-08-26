class IptvPlaylist {
  final String id;
  final String name;
  final String url;

  IptvPlaylist({
    required this.id,
    required this.name,
    required this.url,
  });

  factory IptvPlaylist.fromJson(Map<String, dynamic> json) {
    return IptvPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
    };
  }
}

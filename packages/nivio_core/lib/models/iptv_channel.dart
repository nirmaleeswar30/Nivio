class IptvChannel {
  final String name;
  final String url;
  final String group;
  final String logo;
  final String tvgId;
  final bool isFavorite;
  
  IptvChannel({
    required this.name,
    required this.url,
    this.group = 'Uncategorized',
    this.logo = '',
    this.tvgId = '',
    this.isFavorite = false,
  });

  factory IptvChannel.fromJson(Map<String, dynamic> json) {
    return IptvChannel(
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      group: json['group'] ?? 'Uncategorized',
      logo: json['logo'] ?? '',
      tvgId: json['tvgId'] ?? '',
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'url': url,
      'group': group,
      'logo': logo,
      'tvgId': tvgId,
      'isFavorite': isFavorite,
    };
  }
}

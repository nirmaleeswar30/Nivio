/// Typed views over rqbit's HTTP API JSON. Only the fields Nivio needs are
/// modelled; everything is tolerant of missing/extra fields.

class TorrentFileInfo {
  TorrentFileInfo({
    required this.index,
    required this.name,
    required this.length,
    required this.included,
    this.components = const [],
  });

  /// Index of this file within the torrent (its `stream/<file_id>`).
  final int index;
  final String name;
  final int length;
  final bool included;
  final List<String> components;

  factory TorrentFileInfo.fromJson(int index, Map<String, dynamic> j) {
    return TorrentFileInfo(
      index: index,
      name: (j['name'] ?? '') as String,
      length: (j['length'] ?? 0) as int,
      included: (j['included'] ?? true) as bool,
      components: (j['components'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class TorrentDetails {
  TorrentDetails({
    required this.id,
    required this.infoHash,
    required this.name,
    required this.outputFolder,
    required this.totalPieces,
    required this.files,
  });

  final int? id;
  final String infoHash;
  final String? name;
  final String outputFolder;
  final int totalPieces;
  final List<TorrentFileInfo> files;

  factory TorrentDetails.fromJson(Map<String, dynamic> j) {
    final rawFiles = (j['files'] as List?) ?? const [];
    return TorrentDetails(
      id: j['id'] as int?,
      infoHash: (j['info_hash'] ?? '') as String,
      name: j['name'] as String?,
      outputFolder: (j['output_folder'] ?? '') as String,
      totalPieces: (j['total_pieces'] ?? 0) as int,
      files: [
        for (var i = 0; i < rawFiles.length; i++)
          TorrentFileInfo.fromJson(i, rawFiles[i] as Map<String, dynamic>),
      ],
    );
  }
}

class AddTorrentResponse {
  AddTorrentResponse({required this.id, required this.details});

  final int? id;
  final TorrentDetails details;

  factory AddTorrentResponse.fromJson(Map<String, dynamic> j) {
    return AddTorrentResponse(
      id: j['id'] as int?,
      details:
          TorrentDetails.fromJson((j['details'] ?? j) as Map<String, dynamic>),
    );
  }
}

class PeerStats {
  PeerStats({required this.live, required this.seen, required this.connecting});
  final int live;
  final int seen;
  final int connecting;

  factory PeerStats.fromJson(Map<String, dynamic> j) => PeerStats(
        live: (j['live'] ?? 0) as int,
        seen: (j['seen'] ?? 0) as int,
        connecting: (j['connecting'] ?? 0) as int,
      );
}

class TorrentStats {
  TorrentStats({
    required this.state,
    required this.progressBytes,
    required this.totalBytes,
    required this.finished,
    required this.downloadMbps,
    required this.uploadMbps,
    this.peers,
    this.error,
  });

  /// e.g. "initializing", "live", "paused", "error".
  final String state;
  final int progressBytes;
  final int totalBytes;
  final bool finished;
  final double downloadMbps;
  final double uploadMbps;
  final PeerStats? peers;
  final String? error;

  bool get isLive => state == 'live';
  double get progressFraction =>
      totalBytes == 0 ? 0 : progressBytes / totalBytes;

  factory TorrentStats.fromJson(Map<String, dynamic> j) {
    final live = j['live'] as Map<String, dynamic>?;
    final snapshot = live?['snapshot'] as Map<String, dynamic>?;
    final peerStats = snapshot?['peer_stats'] as Map<String, dynamic>?;
    final dl = live?['download_speed'] as Map<String, dynamic>?;
    final ul = live?['upload_speed'] as Map<String, dynamic>?;
    return TorrentStats(
      state: (j['state'] ?? 'unknown') as String,
      progressBytes: (j['progress_bytes'] ?? 0) as int,
      totalBytes: (j['total_bytes'] ?? 0) as int,
      finished: (j['finished'] ?? false) as bool,
      downloadMbps: ((dl?['mbps'] ?? 0) as num).toDouble(),
      uploadMbps: ((ul?['mbps'] ?? 0) as num).toDouble(),
      peers: peerStats == null ? null : PeerStats.fromJson(peerStats),
      error: j['error'] as String?,
    );
  }
}

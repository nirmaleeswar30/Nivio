import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Typed client over rqbit's localhost HTTP API.
///
/// All methods talk to `http://127.0.0.1:<port>` started by [RqbitEngine].
class RqbitClient {
  RqbitClient(this.baseUrl, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// e.g. `http://127.0.0.1:3030`
  final String baseUrl;
  final http.Client _http;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  /// Adds a torrent by magnet link, `.torrent` URL, or info-hash (auto-detected).
  ///
  /// [onlyFiles] restricts download to these file indices (the episode file).
  /// [listOnly] resolves metadata + file list without downloading — use it to
  /// pick the right file, then re-add or [updateOnlyFiles].
  Future<AddTorrentResponse> addTorrent(
    String magnetOrUrl, {
    bool overwrite = true,
    bool? isUrl,
    List<int>? onlyFiles,
    bool listOnly = false,
    String? outputFolder,
  }) async {
    final query = <String, String>{'overwrite': '$overwrite'};
    if (isUrl != null) query['is_url'] = '$isUrl';
    if (onlyFiles != null && onlyFiles.isNotEmpty) {
      query['only_files'] = onlyFiles.join(',');
    }
    if (listOnly) query['list_only'] = 'true';
    if (outputFolder != null && outputFolder.isNotEmpty) {
      query['output_folder'] = outputFolder;
    }

    final resp = await _http.post(
      _u('/torrents', query),
      body: magnetOrUrl,
      headers: {'content-type': 'text/plain'},
    );
    _ensureOk(resp, 'addTorrent');
    return AddTorrentResponse.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Lists all torrents currently in the session.
  Future<List<TorrentDetails>> listTorrents() async {
    final resp = await _http.get(_u('/torrents'));
    _ensureOk(resp, 'listTorrents');
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (body['torrents'] as List?) ?? const [];
    return [
      for (final t in list) TorrentDetails.fromJson(t as Map<String, dynamic>),
    ];
  }

  /// Creates and serves a torrent from a local file or folder path (complete on
  /// disk — no peers needed). Returns the magnet link (contains the info-hash).
  /// Requires the engine started with create enabled (it is).
  Future<String> createFromLocalPath(String path) async {
    final resp = await _http.post(
      _u('/torrents/create'),
      body: path,
      headers: {'content-type': 'text/plain'},
    );
    _ensureOk(resp, 'createFromLocalPath');
    return resp.body.trim();
  }

  Future<TorrentDetails> getDetails(int id) async {
    final resp = await _http.get(_u('/torrents/$id'));
    _ensureOk(resp, 'getDetails');
    return TorrentDetails.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<TorrentStats> getStats(int id) async {
    final resp = await _http.get(_u('/torrents/$id/stats/v1'));
    _ensureOk(resp, 'getStats');
    return TorrentStats.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// The direct, seekable stream URL for [fileId] in torrent [id] — hand this to
  /// the video player (media_kit).
  String streamUrl(int id, int fileId) =>
      '$baseUrl/torrents/$id/stream/$fileId';

  /// Change which files are actively downloaded after the torrent was added.
  Future<void> updateOnlyFiles(int id, List<int> fileIndices) async {
    final resp = await _http.post(
      _u('/torrents/$id/update_only_files'),
      body: jsonEncode({'only_files': fileIndices}),
      headers: {'content-type': 'application/json'},
    );
    _ensureOk(resp, 'updateOnlyFiles');
  }

  Future<void> pause(int id) => _action(id, 'pause');
  Future<void> start(int id) => _action(id, 'start');

  /// Remove from the session but keep downloaded files (resumable).
  Future<void> forget(int id) => _action(id, 'forget');

  /// Remove from the session and delete downloaded files.
  Future<void> delete(int id) => _action(id, 'delete');

  Future<void> _action(int id, String action) async {
    final resp = await _http.post(_u('/torrents/$id/$action'));
    // forget/delete of an unknown id can 404 during teardown races; ignore.
    if (resp.statusCode == 404) return;
    _ensureOk(resp, action);
  }

  void _ensureOk(http.Response resp, String what) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw RqbitApiException(what, resp.statusCode, resp.body);
    }
  }

  void close() => _http.close();
}

class RqbitApiException implements Exception {
  RqbitApiException(this.operation, this.statusCode, this.body);
  final String operation;
  final int statusCode;
  final String body;

  @override
  String toString() =>
      'RqbitApiException($operation: HTTP $statusCode: ${body.length > 300 ? '${body.substring(0, 300)}…' : body})';
}

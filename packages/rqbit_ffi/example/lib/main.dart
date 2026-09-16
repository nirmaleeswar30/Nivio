import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rqbit_ffi/rqbit_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'rqbit_ffi demo',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = Player();
  late final _controller = VideoController(_player);
  final _input = TextEditingController();

  RqbitClient? _client;
  String _status = 'starting engine…';
  bool _busy = false;
  int? _torrentId;
  TorrentStats? _stats;
  Timer? _statsTimer;

  @override
  void initState() {
    super.initState();
    _startEngine();
  }

  Future<void> _startEngine() async {
    try {
      _client = await RqbitEngine.instance.ensureStarted();
      setState(() => _status = 'engine ready at ${RqbitEngine.instance.baseUrl}');
    } catch (e) {
      setState(() => _status = 'engine start failed: $e');
    }
  }

  Future<void> _playMagnetOrUrl() async {
    final input = _input.text.trim();
    if (input.isEmpty || _client == null) return;
    await _guard(() async {
      setState(() => _status = 'adding torrent…');
      final isUrl = input.startsWith('http');
      final add = await _client!.addTorrent(input, isUrl: isUrl ? true : null);
      final id = add.id ?? 0;

      // Magnets resolve metadata from peers — wait for the file list.
      var details = await _client!.getDetails(id);
      for (var i = 0; details.files.isEmpty && i < 60; i++) {
        setState(() => _status = 'fetching metadata from peers… (${i}s)');
        await Future.delayed(const Duration(seconds: 1));
        details = await _client!.getDetails(id);
      }
      if (details.files.isEmpty) {
        setState(() => _status = 'no metadata (no peers?) — try a well-seeded magnet');
        return;
      }
      await _pickFileAndPlay(id, details);
    });
  }

  Future<void> _pickLocalVideo() async {
    if (_client == null) return;
    final res = await FilePicker.pickFiles(type: FileType.video);
    final path = res?.files.single.path;
    if (path == null) return;
    await _guard(() async {
      setState(() => _status = 'creating torrent from local file…');
      await _client!.createFromLocalPath(path);
      // The created torrent is now in the session; find it.
      final list = await _client!.listTorrents();
      if (list.isEmpty) {
        setState(() => _status = 'create failed');
        return;
      }
      final t = list.last;
      await _pickFileAndPlay(t.id ?? 0, t);
    });
  }

  Future<void> _pickFileAndPlay(int id, TorrentDetails details) async {
    // Choose the largest file (the video) in the torrent.
    final files = [...details.files]..sort((a, b) => b.length.compareTo(a.length));
    final target = files.first;
    // Restrict download to just that file.
    try {
      await _client!.updateOnlyFiles(id, [target.index]);
    } catch (_) {/* older torrents / single-file: ignore */}

    final url = _client!.streamUrl(id, target.index);
    _torrentId = id;
    setState(() => _status = 'streaming: ${target.name}');
    _startStatsPolling();
    await _player.open(Media(url));
  }

  void _startStatsPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final id = _torrentId;
      if (id == null || _client == null) return;
      try {
        final s = await _client!.getStats(id);
        if (mounted) setState(() => _stats = s);
      } catch (_) {}
    });
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      setState(() => _status = 'error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    final id = _torrentId;
    final client = _client;
    if (id != null && client != null) {
      client.forget(id).catchError((_) {});
    }
    _player.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('rqbit_ffi · torrent → media_kit')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'magnet: / .torrent URL / info-hash',
                      hintText: 'paste a well-seeded magnet link',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _playMagnetOrUrl,
                  child: const Text('Play'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickLocalVideo,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pick local video (offline test)'),
                ),
                const SizedBox(width: 12),
                if (_busy)
                  const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: Colors.tealAccent)),
            if (s != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'state=${s.state}  '
                  'peers=${s.peers?.live ?? 0}/${s.peers?.seen ?? 0}  '
                  '↓${s.downloadMbps.toStringAsFixed(2)} MiB/s  '
                  '${(s.progressFraction * 100).toStringAsFixed(1)}%',
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                color: Colors.black,
                child: Video(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

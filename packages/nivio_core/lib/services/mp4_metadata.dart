import 'dart:math' show min;
import 'dart:typed_data';

/// Reads track metadata from ISO base media files, without decoding
/// or downloading the media data. Offsets are relative to the supplied range.
class Mp4Metadata {
  static ({int offset, bool complete})? moviePosition(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    while (offset + 8 <= data.lengthInBytes) {
      final box = _box(data, offset, data.lengthInBytes);
      if (box == null) return null;
      if (box.type == 'moov') {
        return (offset: offset, complete: box.end <= data.lengthInBytes);
      }
      if (data.getUint32(offset) == 0) return null;
      offset = box.end;
    }
    return offset == 0 ? null : (offset: offset, complete: false);
  }

  static List<String> audioLanguages(Uint8List bytes, int movieOffset) {
    final data = ByteData.sublistView(bytes);
    final movie = _box(data, movieOffset, data.lengthInBytes);
    if (movie == null ||
        movie.type != 'moov' ||
        movie.end > data.lengthInBytes) {
      return const [];
    }
    final languages = <String>[];
    for (final (_, media) in _tracks(data, movie, 'soun')) {
      final boxes = _children(data, media);
      final extended = boxes.where((box) => box.type == 'elng').firstOrNull;
      if (extended != null && extended.payload + 4 < extended.end) {
        final tag = String.fromCharCodes(
          [
            for (var i = extended.payload + 4; i < extended.end; i++)
              data.getUint8(i),
          ].takeWhile((byte) => byte != 0),
        );
        if (RegExp(r'^[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*$').hasMatch(tag)) {
          languages.add(tag);
          continue;
        }
      }
      final header = boxes.where((box) => box.type == 'mdhd').firstOrNull;
      languages.add(header == null ? 'und' : _mediaLanguage(data, header));
    }
    return languages;
  }

  /// The sample description and track header can precede large sample tables
  /// in a partial movie box. Only read fields present in the supplied bytes.
  static List<int> videoHeights(Uint8List bytes, int movieOffset) {
    final data = ByteData.sublistView(bytes);
    final movie = _box(data, movieOffset, data.lengthInBytes);
    if (movie == null || movie.type != 'moov') return const [];
    final heights = <int>{};
    for (final (track, media) in _tracks(data, movie, 'vide', partial: true)) {
      final height = _sampleHeight(data, media) ?? _trackHeight(data, track);
      if (height != null) heights.add(height);
    }
    return heights.toList()..sort((a, b) => b.compareTo(a));
  }

  static int? _sampleHeight(ByteData data, _Mp4Box media) {
    final info = _child(data, media, 'minf', partial: true);
    if (info == null) return null;
    final table = _child(data, info, 'stbl', partial: true);
    if (table == null) return null;
    final descriptions = _child(data, table, 'stsd', partial: true);
    if (descriptions == null) return null;
    final entryStart = descriptions.payload + 8;
    if (!_contains(data, descriptions, entryStart, 8) ||
        data.getUint32(descriptions.payload + 4) == 0) {
      return null;
    }
    final end = min(descriptions.end, data.lengthInBytes);
    final entry = _box(data, entryStart, end);
    if (entry == null || entry.end > descriptions.end) return null;
    final size = entry.payload + 24;
    if (!_contains(data, entry, size, 4)) return null;
    return _validHeight(data.getUint16(size), data.getUint16(size + 2));
  }

  static int? _trackHeight(ByteData data, _Mp4Box track) {
    final header = _child(data, track, 'tkhd', partial: true);
    if (header == null || !_contains(data, header, header.payload, 1)) {
      return null;
    }
    final version = data.getUint8(header.payload);
    if (version != 0 && version != 1) return null;
    final size = header.payload + (version == 0 ? 76 : 88);
    if (!_contains(data, header, size, 8)) return null;
    return _validHeight(
      data.getUint32(size) >> 16,
      data.getUint32(size + 4) >> 16,
    );
  }

  static int? _validHeight(int width, int height) =>
      width > 0 && height > 0 && width <= 16384 && height <= 16384
      ? height
      : null;

  static bool _contains(ByteData data, _Mp4Box box, int offset, int size) =>
      offset + size <= box.end && offset + size <= data.lengthInBytes;

  static Iterable<(_Mp4Box, _Mp4Box)> _tracks(
    ByteData data,
    _Mp4Box movie,
    String kind, {
    bool partial = false,
  }) sync* {
    for (final track in _children(data, movie, partial: partial)) {
      if (track.type != 'trak') continue;
      final media = _child(data, track, 'mdia', partial: partial);
      if (media == null) continue;
      final handler = _child(data, media, 'hdlr', partial: partial);
      if (handler != null &&
          _contains(data, handler, handler.payload + 8, 4) &&
          _type(data, handler.payload + 8) == kind) {
        yield (track, media);
      }
    }
  }

  static _Mp4Box? _child(
    ByteData data,
    _Mp4Box parent,
    String type, {
    bool partial = false,
  }) => _children(
    data,
    parent,
    partial: partial,
  ).where((box) => box.type == type).firstOrNull;

  static String _mediaLanguage(ByteData data, _Mp4Box header) {
    if (header.payload >= header.end) return 'und';
    final version = data.getUint8(header.payload);
    if (version != 0 && version != 1) return 'und';
    final offset = header.payload + (version == 0 ? 20 : 32);
    if (offset + 2 > header.end) return 'und';
    final packed = data.getUint16(offset);
    final letters = [(packed >> 10) & 31, (packed >> 5) & 31, packed & 31];
    if (letters.any((value) => value < 1 || value > 26)) return 'und';
    return String.fromCharCodes(letters.map((value) => value + 96));
  }

  static Iterable<_Mp4Box> _children(
    ByteData data,
    _Mp4Box parent, {
    bool partial = false,
  }) sync* {
    final end = min(parent.end, data.lengthInBytes);
    var offset = parent.payload;
    while (offset + 8 <= end) {
      final box = _box(data, offset, end);
      if (box == null || box.end > parent.end || (!partial && box.end > end)) {
        return;
      }
      yield box;
      offset = box.end;
    }
  }

  static _Mp4Box? _box(ByteData data, int offset, int end) {
    if (offset < 0 || offset + 8 > end) return null;
    var size = data.getUint32(offset);
    var header = 8;
    if (size == 1) {
      if (offset + 16 > end) return null;
      size = data.getUint64(offset + 8);
      header = 16;
    }
    if (size == 0) size = end - offset;
    if (size < header || size > 0x1fffffffffffff - offset) return null;
    return (
      type: _type(data, offset + 4),
      payload: offset + header,
      end: offset + size,
    );
  }

  static String _type(ByteData data, int offset) => String.fromCharCodes([
    for (var i = offset; i < offset + 4; i++) data.getUint8(i),
  ]);
}

typedef _Mp4Box = ({String type, int payload, int end});

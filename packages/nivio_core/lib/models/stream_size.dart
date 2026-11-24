class StreamSize {
  static final _units = RegExp(
    r'(?<![A-Z0-9])(?<!\d[.,])(\d+(?:[.,]\d+)?)\s*([KMGT]I?B)(?![A-Z0-9])',
    caseSensitive: false,
  );
  static const _scale = {
    'K': 1024,
    'M': 1048576,
    'G': 1073741824,
    'T': 1099511627776,
  };

  static int? parse(Object? value) {
    if (value is num && !value.isFinite) return null;
    final bytes = value is num ? value.toInt() : int.tryParse('$value');
    if (bytes != null) return bytes > 0 ? bytes : null;
    final text = '$value'.trim();
    final match = _units.firstMatch(text);
    return match != null && match.start == 0 && match.end == text.length
        ? _parseUnits(match)
        : null;
  }

  static int? fromTitle(String title) {
    final sizes = _units.allMatches(title).map(_parseUnits).nonNulls.toSet();
    return sizes.length == 1 ? sizes.single : null;
  }

  static int? _parseUnits(RegExpMatch match) {
    final amount = double.parse(match[1]!.replaceAll(',', '.'));
    final bytes = amount * _scale[match[2]![0].toUpperCase()]!;
    return bytes.isFinite && bytes > 0 && bytes < 0x20000000000000
        ? bytes.round()
        : null;
  }

  static String format(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1024) return '${(gb / 1024).toStringAsFixed(2)} TB';
    if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(1)} KB';
  }
}

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// The mpv driver and codecs supported by the current system output.
typedef DolbyAudioRoute = ({String driver, String codecs});

DolbyAudioRoute? windowsDolbyOutput() {
  // Match mpv's default WASAPI endpoint and IEC 61937 carrier formats.
  if (CoInitializeEx(COINIT_APARTMENTTHREADED).isError) return null;
  try {
    return using((arena) {
      final enumerator = arena.com<IMMDeviceEnumerator>(
        GUID('bcde0395-e52f-467c-8e3d-c4579291692e'),
      );
      final endpoint = enumerator.getDefaultAudioEndpoint(eRender, eMultimedia);
      if (endpoint == null) return null;
      final client = arena
          .adopt(endpoint)
          .activate<IAudioClient>(CLSCTX_INPROC_SERVER, null);
      arena.adopt(client);

      final format = arena<WAVEFORMATEXTENSIBLE>();
      bool supports(String subformat, int channels, int channelMask) {
        const rate = 192000;
        final blockAlign = channels * 2;
        format.ref.Format
          ..wFormatTag = WAVE_FORMAT_EXTENSIBLE
          ..nChannels = channels
          ..nSamplesPerSec = rate
          ..nAvgBytesPerSec = rate * blockAlign
          ..nBlockAlign = blockAlign
          ..wBitsPerSample = 16
          ..cbSize = sizeOf<WAVEFORMATEXTENSIBLE>() - sizeOf<WAVEFORMATEX>();
        format.ref.Samples.wValidBitsPerSample = 16;
        format.ref.dwChannelMask = channelMask;
        format.ref.SubFormat.setGUID('$subformat-0cea-0010-8000-00aa00389b71');
        return client.isFormatSupported(
              AUDCLNT_SHAREMODE_EXCLUSIVE,
              format.cast<WAVEFORMATEX>(),
              null,
            ) ==
            S_OK;
      }

      final codecs = [
        if (supports('0000000a', 2, 0x0003)) 'eac3',
        if (supports('0000000c', 8, 0x063f)) 'truehd',
      ];
      return codecs.isEmpty
          ? null
          : (driver: 'wasapi', codecs: codecs.join(','));
    });
  } finally {
    CoUninitialize();
  }
}

Future<DolbyAudioRoute?> linuxDolbyOutput() async {
  final pipeWire = await _audioQuery('pw-dump', ['--no-colors']);
  if (pipeWire != null) {
    try {
      if (jsonDecode(pipeWire) case final List objects) {
        final route = _pipeWireDolbyOutput(objects);
        if (route != null) return route;
      }
    } on FormatException {
      // The PulseAudio interface can still provide the current sink's formats.
    }
  }

  final [defaultSink, output] = await Future.wait([
    _audioQuery('pactl', ['get-default-sink']),
    _audioQuery('pactl', ['--format=json', 'list', 'sinks']),
  ]);
  if (defaultSink == null || output == null) return null;
  final sinks = jsonDecode(output);
  return sinks is List ? _pulseDolbyOutput(defaultSink.trim(), sinks) : null;
}

DolbyAudioRoute? _pulseDolbyOutput(String defaultSink, List sinks) {
  for (final sink in sinks.whereType<Map>()) {
    if (sink['name'] != defaultSink || sink['formats'] is! List) continue;
    final formats = (sink['formats'] as List).whereType<String>();
    // PulseAudio does not reliably play TrueHD through its passthrough sinks.
    if (formats.any(
      (format) => format.split(',').first.trim() == 'eac3-iec61937',
    )) {
      return (driver: 'pulse', codecs: 'eac3');
    }
  }
  return null;
}

DolbyAudioRoute? _pipeWireDolbyOutput(List objects) {
  final nodes = objects.whereType<Map>();
  String? defaultSink;
  for (final node in nodes) {
    if (node case {
      'props': {'metadata.name': 'default'},
      'metadata': final List entries,
    }) {
      for (final entry in entries.whereType<Map>()) {
        if (entry['subject'] != 0 || entry['key'] != 'default.audio.sink') {
          continue;
        }
        final raw = entry['value'];
        final value = raw is String ? jsonDecode(raw) : raw;
        if (value case {'name': final String name}) defaultSink = name;
      }
    }
  }
  if (defaultSink == null) return null;

  final encodings = <String>{};
  for (final node in nodes) {
    if (node case {
      'info': {
        'props': {'node.name': final String name, 'media.class': 'Audio/Sink'},
        'params': {'EnumFormat': final List formats},
      },
    } when name == defaultSink) {
      for (final format in formats.whereType<Map>()) {
        if (format['mediaSubtype'] != 'iec958') continue;
        final codec = format['iec958Codec'];
        if (codec is String) encodings.add(codec.toUpperCase());
        if (codec is Map) {
          encodings.addAll(
            codec.values.whereType<String>().map((s) => s.toUpperCase()),
          );
        }
      }
    }
  }
  final codecs = [
    if (encodings.contains('EAC3')) 'eac3',
    if (encodings.contains('TRUEHD')) 'truehd',
  ];
  return codecs.isEmpty ? null : (driver: 'pipewire', codecs: codecs.join(','));
}

Future<String?> _audioQuery(String executable, List<String> arguments) async {
  try {
    final process = await Process.start(executable, arguments);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 1),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await errors;
    final text = await output;
    return exitCode == 0 ? text : null;
  } on ProcessException {
    return null;
  }
}

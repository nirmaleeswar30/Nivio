import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_qjs_next/flutter_qjs.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:nivio/core/constants.dart';

import 'extension_anime_mapping.dart';
import 'extension_repository.dart';

Future<List<Map<String, dynamic>>> runNuvioScript(
  String code,
  List<Object?> arguments,
  Map<String, dynamic> settings, {
  Duration timeout = const Duration(seconds: 24),
  NuvioAnimeMapping? animeMapping,
}) => Isolate.run(
  () => _execute(code, arguments, settings, timeout, animeMapping),
);

final _publicTmdbPath = RegExp(
  r'^/3/(?:movie/\d+(?:/external_ids)?|tv/\d+(?:/external_ids|/season/\d+(?:/episode/\d+)?)?|find/tt\d+)$',
);

/// Shares Nivio's metadata connection for the public title lookups used by plugins.
Uri? nuvioTmdbMetadataUrl(String method, Uri url) {
  if (method != 'GET' ||
      url.scheme != 'https' ||
      url.host != 'api.themoviedb.org' ||
      url.port != 443 ||
      url.userInfo.isNotEmpty ||
      !_publicTmdbPath.hasMatch(url.path)) {
    return null;
  }
  return Uri.parse(tmdbBaseUrl).replace(
    path: url.path,
    queryParameters: {
      'api_key': tmdbApiKey,
      for (final field in [
        'language',
        'append_to_response',
        'include_image_language',
        'external_source',
      ])
        if (url.queryParameters[field] case final String value) field: value,
    },
  );
}

Future<List<Map<String, dynamic>>> _execute(
  String code,
  List<Object?> arguments,
  Map<String, dynamic> settings,
  Duration timeout,
  NuvioAnimeMapping? animeMapping,
) async {
  final client = extensionHttpClient();
  var requests = 0;
  final runtime = getJavascriptRuntime(
    // The Windows default runs out of stack inside the web URL parser.
    stackSize: Platform.isWindows ? 512 * 1024 : null,
    timeout: 2000,
    memoryLimit: 48 * 1024 * 1024,
    webApis: JsWebApis.standard(
      fetch: JsFetchOptions(
        allowUrl: isExtensionWebUrl,
        connectionTimeout: const Duration(seconds: 8),
        maxResponseBytes: 5 * 1024 * 1024,
        maxRedirects: 5,
        handler: (request) async {
          if (++requests > 60)
            throw StateError('Provider request limit reached.');
          final mapped = animeMapping == null
              ? null
              : nuvioAnimeMappingResponse(
                  request.method,
                  request.url,
                  animeMapping,
                );
          if (mapped != null) {
            return JsFetchResponse(
              status: 200,
              headers: const [MapEntry('content-type', 'application/json')],
              body: Stream.value(utf8.encode(jsonEncode(mapped))),
            );
          }
          final metadata = nuvioTmdbMetadataUrl(request.method, request.url);
          final outgoing = await client.openUrl(
            request.method,
            metadata ?? request.url,
          );
          outgoing.followRedirects = false;
          // Metadata lookups use app credentials. Never copy plugin headers to them.
          for (final header
              in metadata == null
                  ? request.headers
                  : const <MapEntry<String, String>>[]) {
            final name = header.key.toLowerCase();
            if (name == HttpHeaders.acceptEncodingHeader) {
              // dart:io can decode gzip, but not Brotli or deflate.
              if (header.value.trim().toLowerCase() == 'identity') {
                outgoing.headers.set(name, 'identity');
              }
            } else if (!const {
              'host',
              'content-length',
              'connection',
            }.contains(name)) {
              outgoing.headers.add(header.key, header.value);
            }
          }
          final body = metadata == null ? request.body : null;
          if (body != null) {
            if (body.length > 1024 * 1024)
              throw StateError('Provider request is too large.');
            outgoing.contentLength = body.length;
            outgoing.add(body);
          }
          unawaited(request.onAbort.then((_) => outgoing.abort()));
          final response = await outgoing.close();
          final headers = <MapEntry<String, String>>[];
          response.headers.forEach((name, values) {
            headers.addAll(values.map((value) => MapEntry(name, value)));
          });
          return JsFetchResponse(
            status: response.statusCode,
            headers: headers,
            body: response,
          );
        },
      ),
    ),
  );
  final nodes = <Node>[];
  int record(Node node) {
    if (nodes.length >= 25000) throw StateError('Provider HTML is too large.');
    nodes.add(node);
    return nodes.length - 1;
  }

  runtime.onMessage('nivioDom', (dynamic args) {
    final input = args as List;
    final op = input[0];
    if (op == 'load') return record(html.parse(input[1] as String));
    if (op == 'fragment')
      return html
          .parseFragment(input[1] as String)
          .children
          .map(record)
          .toList();
    final node = nodes[input[1] as int];
    if (op == 'find') {
      final selector = input[2] as String;
      final contains = RegExp(
        r'''^(.*):contains\(["']?(.*?)["']?\)$''',
      ).firstMatch(selector);
      final css = contains == null
          ? selector
          : contains.group(1)!.isEmpty
          ? '*'
          : contains.group(1)!;
      final found = switch (node) {
        Document document => document.querySelectorAll(css),
        Element element => element.querySelectorAll(css),
        _ => const <Element>[],
      };
      return found
          .where(
            (element) =>
                contains == null || element.text.contains(contains.group(2)!),
          )
          .take(3000)
          .map(record)
          .toList();
    }
    if (op == 'text') return node.text;
    if (op == 'children') return node.children.take(3000).map(record).toList();
    if (op == 'parent')
      return node.parentNode == null ? null : record(node.parentNode!);
    if (op == 'attr' && node is Element) return node.attributes[input[2]];
    if (op == 'html' && node is Element) return node.innerHtml;
    if (op == 'outer' && node is Element) return node.outerHtml;
    if (op == 'tag' && node is Element) return node.localName;
    if (op == 'next' && node is Element)
      return node.nextElementSibling == null
          ? null
          : record(node.nextElementSibling!);
    if (op == 'prev' && node is Element)
      return node.previousElementSibling == null
          ? null
          : record(node.previousElementSibling!);
    return null;
  });
  runtime.onMessage('nivioHash', (dynamic args) {
    final values = args as List;
    final hash = switch (values[0]) {
      'MD5' => md5,
      'SHA1' => sha1,
      'SHA256' => sha256,
      'SHA512' => sha512,
      _ => throw ArgumentError('Unsupported digest'),
    };
    final bytes = (values[1] as List).cast<int>();
    final key = values[2] as List?;
    return (key == null
            ? hash.convert(bytes)
            : Hmac(hash, key.cast<int>()).convert(bytes))
        .bytes;
  });

  final completed = Completer<String>();
  runtime.onMessage('nivioResult', (dynamic args) {
    if (!completed.isCompleted && args is String) completed.complete(args);
  });
  Timer? pump;
  try {
    final setup = runtime.evaluate(_compatibility);
    if (setup.isError) throw FormatException(setup.stringResult);
    final result = runtime.evaluate('''
      globalThis.SCRAPER_SETTINGS = ${jsonEncode(settings)};
      (async () => {
        const resolver = (() => {
          let module = { exports: {} };
          let exports = module.exports;
          ${code.replaceFirst(RegExp(r'^#![^\n]*\n'), '')}
          return module.exports.getStreams ||
            (typeof module.exports === 'function' ? module.exports : null) ||
            (typeof getStreams === 'function' ? getStreams : globalThis.getStreams?.getStreams);
        })();
        if (typeof resolver !== 'function') throw new Error('Missing getStreams export');
        const args = ${jsonEncode(arguments)}.map(value => value ?? undefined);
        const result = await resolver(...args);
        const streams = Array.isArray(result) ? result : result?.streams;
        sendMessage('nivioResult', JSON.stringify(JSON.stringify({streams: (streams || []).slice(0, 100)})));
      })().catch(error => sendMessage('nivioResult', JSON.stringify(JSON.stringify({error: String(error)}))));
      void 0;
    ''');
    if (result.isError) throw FormatException(result.stringResult);
    pump = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => runtime.executePendingJob(),
    );
    final response = jsonDecode(await completed.future.timeout(timeout)) as Map;
    if (response['error'] case final String error) throw FormatException(error);
    return (response['streams'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
  } finally {
    pump?.cancel();
    client.close(force: true);
    runtime.dispose();
  }
}

const _compatibility = r'''
globalThis.global = globalThis;
// Build the native Request after the provider's current call stack unwinds.
const hostFetch = globalThis.fetch;
globalThis.fetch = (...args) => Promise.resolve().then(() => hostFetch(...args));
const callDom = (...args) => sendMessage('nivioDom', JSON.stringify(args));
function selection(ids) {
  const first = ids[0];
  const api = {
    length: ids.length,
    _ids: ids,
    get: index => index === undefined ? ids.map(node) : node(ids.at(index)),
    toArray: () => ids.map(node),
    each: fn => { ids.some((id, i) => fn.call(node(id), i, node(id)) === false); return api; },
    map: fn => { const results = ids.flatMap((id, i) => fn.call(node(id), i, node(id)) ?? []);
      return {get: i => i === undefined ? results : results.at(i), toArray: () => results}; },
    first: () => selection(ids.slice(0, 1)),
    last: () => selection(ids.slice(-1)),
    eq: i => selection(ids.at(i) === undefined ? [] : [ids.at(i)]),
    text: () => ids.map(id => callDom('text', id) || '').join(''),
    attr: name => first === undefined ? undefined : callDom('attr', first, name) ?? undefined,
    html: () => first === undefined ? null : callDom('html', first),
    find: css => selection(ids.flatMap(id => callDom('find', id, css))),
    children: () => selection(ids.flatMap(id => callDom('children', id))),
    filter: fn => selection(ids.filter((id, i) => fn.call(node(id), i, node(id)))),
    parent: () => traverse('parent'), next: () => traverse('next'), prev: () => traverse('prev'),
  };
  const traverse = op => selection(ids.map(id => callDom(op, id)).filter(id => id != null));
  ids.forEach((id, i) => api[i] = node(id));
  return api;
}
function node(id) {
  if (id == null) return undefined;
  return {__nivioNode: id, get tagName() { return callDom('tag', id); },
    get name() { return callDom('tag', id); },
    get parent() { return node(callDom('parent', id)); }};
}
const cheerio = { load(source) {
  const doc = callDom('load', String(source));
  const $ = value => {
    if (value == null) return selection([]);
    if (typeof value !== 'string') return selection(value._ids || (value.__nivioNode == null ? [] : [value.__nivioNode]));
    return selection(value.trimStart().startsWith('<') ? callDom('fragment', value) : callDom('find', doc, value));
  };
  $.root = () => selection([doc]);
  $.html = target => target ? $(target)._ids.map(id => callDom('outer', id)).join('') : source;
  return $;
}};
const bytesOf = value => typeof value === 'string' ? Array.from(new TextEncoder().encode(value)) : value.bytes;
const wordArray = bytes => ({ bytes: Array.from(bytes), sigBytes: bytes.length,
  toString(encoder) { return (encoder || CryptoJS.enc.Hex).stringify(this); } });
const CryptoJS = { enc: {
  Hex: { stringify: w => w.bytes.map(b => b.toString(16).padStart(2, '0')).join(''),
    parse: hex => wordArray((hex.match(/../g) || []).map(byte => parseInt(byte,16))) },
  Utf8: { stringify: w => new TextDecoder().decode(Uint8Array.from(w.bytes)), parse: s => wordArray(bytesOf(s)) },
  Base64: { stringify: w => btoa(w.bytes.map(b => String.fromCharCode(b)).join('')),
    parse: s => wordArray(Array.from(atob(s), c => c.charCodeAt(0))) },
}};
for (const name of ['MD5', 'SHA1', 'SHA256', 'SHA512']) {
  const digest = (message, key) => wordArray(sendMessage('nivioHash', JSON.stringify([name, bytesOf(message), key == null ? null : bytesOf(key)])));
  CryptoJS[name] = digest;
  CryptoJS['Hmac' + name] = digest;
}
globalThis.CryptoJS = CryptoJS;
globalThis.require = name => {
  if (['cheerio', 'cheerio-without-node-native', 'react-native-cheerio'].includes(name)) return cheerio;
  if (name === 'crypto-js') return CryptoJS;
  throw new Error('Unsupported module: ' + name);
};
''';

library cloud_firestore;

import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class FirebaseFirestore {
  static final FirebaseFirestore instance = FirebaseFirestore._();
  FirebaseFirestore._();

  CollectionReference collection(String path) {
    return CollectionReference(path);
  }

  WriteBatch batch() => WriteBatch();
}

class CollectionReference {
  final String path;
  CollectionReference(this.path);

  DocumentReference doc([String? docPath]) {
    return DocumentReference('$path${docPath != null ? '/$docPath' : ''}');
  }

  Future<QuerySnapshot> get() async {
    final projectId = Firebase.options?.projectId;
    if (projectId == null) throw StateError('Firebase has not been initialized.');

    final apiKey = Firebase.options?.apiKey;
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path?key=$apiKey',
    );

    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    print('🔑 Firestore REST Target URL: $url');
    print('🔑 Firestore REST ID Token: ${token != null ? "${token.substring(0, 10)}..." : "null"}');
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    print('🔑 Firestore REST Headers: $headers');

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 404) {
      return QuerySnapshot([]);
    }
    if (response.statusCode != 200) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'Failed to fetch collection: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final documents = data['documents'] as List? ?? [];
    final docsList = documents.map((docData) {
      if (docData is Map<String, dynamic>) {
        final name = docData['name'] as String;
        final id = name.split('/').last;
        final docPath = name.split('/documents/').last;
        final fields = docData['fields'] as Map<String, dynamic>? ?? {};
        final mapData = _decodeFirestoreFields(fields);
        return QueryDocumentSnapshot(id, mapData, docPath);
      }
      return null;
    }).whereType<QueryDocumentSnapshot>().toList();

    return QuerySnapshot(docsList);
  }
}

class DocumentReference {
  final String path;
  DocumentReference(this.path);

  CollectionReference collection(String colPath) {
    return CollectionReference('$path/$colPath');
  }

  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    final projectId = Firebase.options?.projectId;
    if (projectId == null) throw StateError('Firebase has not been initialized.');
    final apiKey = Firebase.options?.apiKey;
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path?key=$apiKey',
    );

    final token = await FirebaseAuth.instance.getIdToken();
    final headers = <String, String>{
      'content-type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final encoded = _encodeFirestoreFields(data);
    final response = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(encoded),
    );

    if (response.statusCode != 200) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'Failed to set document: ${response.body}',
      );
    }
  }

  Future<void> delete() async {
    final projectId = Firebase.options?.projectId;
    if (projectId == null) throw StateError('Firebase has not been initialized.');
    final apiKey = Firebase.options?.apiKey;
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path?key=$apiKey',
    );

    final token = await FirebaseAuth.instance.getIdToken();
    final headers = <String, String>{};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 200 && response.statusCode != 404) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'Failed to delete document: ${response.body}',
      );
    }
  }

  Future<DocumentSnapshot> get() async {
    final projectId = Firebase.options?.projectId;
    if (projectId == null) throw StateError('Firebase has not been initialized.');
    final apiKey = Firebase.options?.apiKey;
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$path?key=$apiKey',
    );

    final token = await FirebaseAuth.instance.getIdToken();
    final headers = <String, String>{};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 404) {
      return DocumentSnapshot(path.split('/').last, null, false, path);
    }
    if (response.statusCode != 200) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        message: 'Failed to get document: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final fields = data['fields'] as Map<String, dynamic>? ?? {};
    final mapData = _decodeFirestoreFields(fields);
    return DocumentSnapshot(path.split('/').last, mapData, true, path);
  }
}

class WriteBatch {
  final List<Future<void> Function()> _operations = [];

  void set(DocumentReference ref, Map<String, dynamic> data, [SetOptions? options]) {
    _operations.add(() => ref.set(data, options));
  }

  void delete(DocumentReference ref) {
    _operations.add(() => ref.delete());
  }

  Future<void> commit() async {
    await Future.wait(_operations.map((op) => op()));
  }
}

class SetOptions {
  final bool merge;
  const SetOptions({this.merge = false});
}

class DocumentSnapshot {
  final String id;
  final Map<String, dynamic>? _data;
  final bool _exists;
  final String _path;

  DocumentSnapshot(this.id, this._data, this._exists, this._path);

  bool get exists => _exists;
  Map<String, dynamic>? data() => _data;
  DocumentReference get reference => DocumentReference(_path);
}

class QuerySnapshot {
  final List<QueryDocumentSnapshot> docs;
  QuerySnapshot(this.docs);
}

class QueryDocumentSnapshot extends DocumentSnapshot {
  QueryDocumentSnapshot(String id, Map<String, dynamic> data, String path)
      : super(id, data, true, path);

  @override
  Map<String, dynamic> data() => super.data()!;
}

class FirebaseException implements Exception {
  final String plugin;
  final String message;

  FirebaseException({required this.plugin, required this.message});

  @override
  String toString() => 'FirebaseException: [$plugin] $message';
}

// ─── Firestore REST Formatting Helpers ───────────────────────────────────────

Map<String, dynamic> _encodeFirestoreFields(Map<String, dynamic> data) {
  final fields = <String, dynamic>{};
  data.forEach((key, val) {
    fields[key] = _encodeFirestoreValue(val);
  });
  return {'fields': fields};
}

Map<String, dynamic> _encodeFirestoreValue(dynamic value) {
  if (value == null) return {'nullValue': null};
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'booleanValue': value};
  if (value is int) return {'integerValue': value.toString()};
  if (value is double) return {'doubleValue': value};
  if (value is Map) {
    final mapFields = <String, dynamic>{};
    value.forEach((k, v) {
      mapFields[k.toString()] = _encodeFirestoreValue(v);
    });
    return {'mapValue': {'fields': mapFields}};
  }
  if (value is List) {
    final listValues = value.map((v) => _encodeFirestoreValue(v)).toList();
    return {'arrayValue': {'values': listValues}};
  }
  if (value is DateTime) return {'timestampValue': value.toUtc().toIso8601String()};
  return {'stringValue': value.toString()};
}

Map<String, dynamic> _decodeFirestoreFields(Map<String, dynamic> fields) {
  final result = <String, dynamic>{};
  fields.forEach((key, val) {
    if (val is Map<String, dynamic>) {
      var decoded = _decodeFirestoreValue(val);
      if ((key == 'voteAverage' || key == 'vote_average') && decoded is num) {
        decoded = decoded.toDouble();
      }
      result[key] = decoded;
    }
  });
  return result;
}

dynamic _decodeFirestoreValue(Map<String, dynamic> valueObj) {
  if (valueObj.containsKey('nullValue')) return null;
  if (valueObj.containsKey('stringValue')) return valueObj['stringValue'];
  if (valueObj.containsKey('booleanValue')) return valueObj['booleanValue'];
  if (valueObj.containsKey('integerValue')) return int.tryParse(valueObj['integerValue']) ?? valueObj['integerValue'];
  if (valueObj.containsKey('doubleValue')) {
    final val = valueObj['doubleValue'];
    if (val is num) return val.toDouble();
    return val;
  }
  if (valueObj.containsKey('timestampValue')) return DateTime.tryParse(valueObj['timestampValue']) ?? valueObj['timestampValue'];
  if (valueObj.containsKey('mapValue')) {
    final mapObj = valueObj['mapValue'] as Map<String, dynamic>? ?? {};
    final fields = mapObj['fields'] as Map<String, dynamic>? ?? {};
    return _decodeFirestoreFields(fields);
  }
  if (valueObj.containsKey('arrayValue')) {
    final arrayObj = valueObj['arrayValue'] as Map<String, dynamic>? ?? {};
    final valuesList = arrayObj['values'] as List? ?? [];
    return valuesList.map((v) {
      if (v is Map<String, dynamic>) {
        return _decodeFirestoreValue(v);
      }
      return null;
    }).toList();
  }
  return null;
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() after SharedPreferences is loaded.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

const _kServerUrl = 'server_url';
const _kToken = 'auth_token';
/// Phones reach the backend over Wi-Fi at the office PC's address; the PC
/// itself uses localhost. Change anytime from "Server settings".
/// A release APK bakes in the hosted server:
/// `flutter build apk --release --dart-define=SERVER_URL=https://YOUR-APP.onrender.com`
const _builtInServer = String.fromEnvironment('SERVER_URL');

String get defaultServerUrl => _builtInServer.isNotEmpty
    ? _builtInServer
    : (Platform.isAndroid ? 'http://192.168.100.7:8000' : 'http://localhost:8000');

/// "192.168.100.7:8000/" -> "http://192.168.100.7:8000". Removes spaces, a
/// trailing slash, and a pasted "/health" or "/docs".
String normalizeServerUrl(String raw) {
  var u = raw.trim().replaceAll(' ', '');
  if (!u.startsWith(RegExp(r'https?://', caseSensitive: false))) u = 'http://$u';
  u = u.replaceAll(RegExp(r'/(health|docs|api/v1)/?$'), '');
  return u.replaceAll(RegExp(r'/+$'), '');
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Local settings: backend address and saved login token.
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  // Normalised on read too, so an address saved earlier in a bad format still works.
  String get serverUrl => normalizeServerUrl(_prefs.getString(_kServerUrl) ?? defaultServerUrl);
  Future<void> setServerUrl(String url) => _prefs.setString(_kServerUrl, normalizeServerUrl(url));

  String? get token => _prefs.getString(_kToken);
  Future<void> setToken(String? t) =>
      t == null ? _prefs.remove(_kToken) : _prefs.setString(_kToken, t);
}

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore(ref.watch(prefsProvider)));

/// Thin wrapper over Dio that turns server errors into readable messages.
class ApiClient {
  ApiClient(this._store, {this.onUnauthorized});
  final LocalStore _store;
  final void Function()? onUnauthorized;

  Dio get _dio => Dio(
        BaseOptions(
          baseUrl: '${_store.serverUrl}/api/v1',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            if (_store.token != null) 'Authorization': 'Bearer ${_store.token}',
          },
        ),
      );

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)));

  /// Downloads binary content (e.g. a PDF).
  Future<List<int>> getBytes(String path) async {
    final data = await _send(() => _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes)));
    return data as List<int>;
  }

  Future<dynamic> post(String path, Object? body) => _send(() => _dio.post(path, data: body));

  Future<dynamic> patch(String path, Object? body) => _send(() => _dio.patch(path, data: body));

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) =>
      q == null ? null : (Map.of(q)..removeWhere((_, v) => v == null || v == ''));

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return r.data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) onUnauthorized?.call();
      throw ApiException(_message(e), statusCode: code);
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      final d = data['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) {
        // FastAPI validation errors: [{loc: [...], msg: ...}]
        return d.map((x) {
          final loc = (x['loc'] as List?)?.where((p) => p != 'body').join('.') ?? '';
          return loc.isEmpty ? '${x['msg']}' : '$loc: ${x['msg']}';
        }).join('\n');
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Cannot reach server at ${_store.serverUrl}. Check that the backend is running.';
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond.';
      default:
        return 'Request failed${e.response?.statusCode != null ? ' (${e.response!.statusCode})' : ''}.';
    }
  }
}

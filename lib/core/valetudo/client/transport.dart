import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Where and how to reach a Valetudo instance.
class ValetudoEndpoint {
  ValetudoEndpoint({required Uri baseUri, this.username, this.password})
    : baseUri = normalizeBaseUri(baseUri);

  /// Accepts user input like `192.168.1.10`, `robot.local:8080` or
  /// `https://proxy.example/valetudo` and returns a normalized base URI that
  /// always ends with a slash (so reverse-proxy sub paths are preserved).
  static Uri? tryParse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return normalizeBaseUri(uri);
  }

  static Uri normalizeBaseUri(Uri uri) {
    var path = uri.path;
    if (!path.endsWith('/')) path = '$path/';
    return uri.replace(path: path, query: null, fragment: null);
  }

  final Uri baseUri;
  final String? username;
  final String? password;

  bool get hasCredentials =>
      (username ?? '').isNotEmpty || (password ?? '').isNotEmpty;

  /// Resolves an API path such as `/robot/state` against `<base>/api/v2`.
  Uri api(String path) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    return baseUri.resolve('api/v2/$relative');
  }

  Map<String, String> get authHeaders => hasCredentials
      ? {
          'authorization':
              'Basic ${base64Encode(utf8.encode('${username ?? ''}:${password ?? ''}'))}',
        }
      : const {};

  String get displayHost =>
      baseUri.hasPort && baseUri.port != 80 && baseUri.port != 443
      ? '${baseUri.host}:${baseUri.port}${baseUri.path == '/' ? '' : baseUri.path}'
      : '${baseUri.host}${baseUri.path == '/' ? '' : baseUri.path}';
}

/// Base class of all errors produced while talking to Valetudo.
sealed class ValetudoException implements Exception {
  const ValetudoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The robot could not be reached (offline, wrong address, timeout, TLS).
class ValetudoConnectionException extends ValetudoException {
  const ValetudoConnectionException(super.message, {this.cause});

  final Object? cause;
}

/// HTTP Basic Auth is enabled and the credentials are missing or wrong.
class ValetudoUnauthorizedException extends ValetudoException {
  const ValetudoUnauthorizedException([
    super.message = 'Authentication required',
  ]);
}

/// The request reached Valetudo but was rejected.
class ValetudoApiException extends ValetudoException {
  const ValetudoApiException(this.statusCode, super.message, {this.path});

  final int statusCode;
  final String? path;

  bool get isNotFound => statusCode == 404;
}

/// The address answered, but not like a Valetudo instance.
class NotValetudoException extends ValetudoException {
  const NotValetudoException([
    super.message = 'This address does not appear to be running Valetudo',
  ]);
}

/// Thin HTTP layer used by [ValetudoClient] and the SSE/stream consumers.
class ValetudoTransport {
  ValetudoTransport(
    this.endpoint, {
    http.Client? client,
    http.Client? streamClient,
  }) : _client =
           client ?? _createClient(idleTimeout: const Duration(seconds: 3)),
       _streamClient =
           streamClient ??
           _createClient(idleTimeout: const Duration(seconds: 1));

  static http.Client _createClient({required Duration idleTimeout}) {
    final inner = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      // Valetudo closes idle keep-alive sockets after 5s. Reusing a socket the
      // server already closed produces spurious "connection closed" errors, so
      // drop idle sockets before the server does.
      ..idleTimeout = idleTimeout
      ..autoUncompress = true
      ..userAgent = 'Valrove (Valetudo client)';
    return IOClient(inner);
  }

  final ValetudoEndpoint endpoint;
  final http.Client _client;
  final http.Client _streamClient;
  final _commitIdController = StreamController<String>.broadcast();
  String? _commitId;
  String? _version;
  bool _closed = false;

  static const defaultTimeout = Duration(seconds: 12);

  /// Emits when the backend's commit id changes (i.e. Valetudo was updated
  /// or replaced) so that cached capabilities and state can be refreshed.
  Stream<String> get commitIdChanges => _commitIdController.stream;

  String? get commitId => _commitId;

  /// `X-Valetudo-Version` header of the last response.
  String? get reportedVersion => _version;

  Map<String, String> _headers({bool json = false}) => {
    ...endpoint.authHeaders,
    'accept': 'application/json, text/plain, */*',
    if (json) 'content-type': 'application/json',
  };

  void _observe(http.BaseResponse response) {
    final version = response.headers['x-valetudo-version'];
    if (version != null) _version = version;
    final commit = response.headers['x-valetudo-commit-id'];
    if (commit == null) return;
    if (_commitId == null) {
      _commitId = commit;
    } else if (_commitId != commit) {
      _commitId = commit;
      if (!_commitIdController.isClosed) _commitIdController.add(commit);
    }
  }

  Future<Object?> get(String path, {Duration? timeout}) =>
      _send('GET', path, timeout: timeout);

  Future<Object?> put(String path, [Object? body, Duration? timeout]) =>
      _send('PUT', path, body: body, timeout: timeout);

  Future<Object?> post(String path, [Object? body, Duration? timeout]) =>
      _send('POST', path, body: body, timeout: timeout);

  Future<Object?> delete(String path, {Duration? timeout}) =>
      _send('DELETE', path, timeout: timeout);

  Future<List<int>> getBytes(String path, {Duration? timeout}) async {
    final response = await _execute('GET', path, timeout: timeout);
    return response.bodyBytes;
  }

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    final response = await _execute(method, path, body: body, timeout: timeout);
    return _decode(response);
  }

  Future<http.Response> _execute(
    String method,
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    if (_closed) throw const ValetudoConnectionException('Connection closed');
    final uri = endpoint.api(path);
    final request = http.Request(method, uri)
      ..headers.addAll(_headers(json: body != null));
    if (body != null) request.body = body is String ? body : jsonEncode(body);

    http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(timeout ?? defaultTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(timeout ?? defaultTimeout);
    } on TimeoutException catch (e) {
      throw ValetudoConnectionException(
        'The robot did not respond in time',
        cause: e,
      );
    } on SocketException catch (e) {
      throw ValetudoConnectionException(_describeSocketError(e), cause: e);
    } on HandshakeException catch (e) {
      throw ValetudoConnectionException(
        'Secure connection failed: ${e.message}',
        cause: e,
      );
    } on HttpException catch (e) {
      throw ValetudoConnectionException(
        'Connection error: ${e.message}',
        cause: e,
      );
    } on http.ClientException catch (e) {
      throw ValetudoConnectionException(
        'Connection error: ${e.message}',
        cause: e,
      );
    }

    _observe(response);
    _check(response, path);
    return response;
  }

  /// Opens a long-lived streaming GET (SSE, camera stream). The caller owns
  /// the returned response stream and must cancel its subscription.
  Future<http.StreamedResponse> openStream(
    String path, {
    Map<String, String>? headers,
  }) async {
    if (_closed) throw const ValetudoConnectionException('Connection closed');
    final request = http.Request('GET', endpoint.api(path))
      ..headers.addAll({
        ...endpoint.authHeaders,
        'cache-control': 'no-cache',
        ...?headers,
      });
    http.StreamedResponse response;
    try {
      response = await _streamClient
          .send(request)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e) {
      throw ValetudoConnectionException(
        'The robot did not respond in time',
        cause: e,
      );
    } on SocketException catch (e) {
      throw ValetudoConnectionException(_describeSocketError(e), cause: e);
    } on IOException catch (e) {
      throw ValetudoConnectionException('Connection error: $e', cause: e);
    } on http.ClientException catch (e) {
      throw ValetudoConnectionException(
        'Connection error: ${e.message}',
        cause: e,
      );
    }
    _observe(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain so the socket can be reused/closed cleanly.
      final body = await response.stream.bytesToString().catchError((_) => '');
      _throwForStatus(response.statusCode, body, path);
    }
    return response;
  }

  void _check(http.Response response, String path) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    _throwForStatus(response.statusCode, _safeBody(response), path);
  }

  Never _throwForStatus(int status, String body, String path) {
    if (status == 401) {
      throw ValetudoUnauthorizedException(
        body.trim().isEmpty ? 'Authentication required' : body.trim(),
      );
    }
    final text = body.trim();
    throw ValetudoApiException(
      status,
      text.isEmpty || text.startsWith('<')
          ? 'Request failed (HTTP $status)'
          : text,
      path: path,
    );
  }

  static String _safeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static Object? _decode(http.Response response) {
    final text = _safeBody(response);
    if (text.isEmpty) return null;
    final type = response.headers['content-type'] ?? '';
    if (type.contains('json')) {
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    }
    return text;
  }

  static String _describeSocketError(SocketException e) {
    final os = e.osError?.message;
    if (os != null && os.isNotEmpty) return 'Robot unreachable ($os)';
    return 'Robot unreachable';
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
    _streamClient.close();
    _commitIdController.close();
  }
}

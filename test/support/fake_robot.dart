import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:valrove/core/cleanup/history_store.dart';
import 'package:valrove/core/cleanup/robot_files.dart';
import 'package:valrove/core/persistence/robot_profile.dart';
import 'package:valrove/core/persistence/stores.dart';
import 'package:valrove/core/valetudo/client/valetudo_client.dart';
import 'package:valrove/state/app_state.dart';
import 'package:valrove/state/cleanup.dart';
import 'package:valrove/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves recorded API responses from `test/fixtures/<robot>/` and records
/// every request. SSE endpoints stay open without emitting events.
class FixtureHttpClient extends http.BaseClient {
  FixtureHttpClient({this.robot = 'l40', this.overrides = const {}});

  final String robot;

  /// Path (without `/api/v2/`) → JSON body overriding the fixture file.
  final Map<String, Object?> overrides;
  final List<http.BaseRequest> requests = [];
  final List<StreamController<List<int>>> _open = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final path = request.url.path.replaceFirst(RegExp(r'^.*?/api/v2/'), '');
    if (path.endsWith('/sse') || path.endsWith('/stream')) {
      final controller = StreamController<List<int>>();
      _open.add(controller);
      return http.StreamedResponse(
        controller.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    if (request.method != 'GET') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('OK')),
        200,
        headers: {'content-type': 'text/plain'},
      );
    }
    String? body;
    if (overrides.containsKey(path)) {
      body = jsonEncode(overrides[path]);
    } else {
      final file = File(
        'test/fixtures/$robot/${path.replaceAll('/', '__')}.json',
      );
      if (file.existsSync()) body = file.readAsStringSync();
    }
    if (body == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('Not Found')),
        404,
        headers: {'content-type': 'text/plain'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'x-valetudo-commit-id': 'test',
        'x-valetudo-version': '0.6.0',
      },
    );
  }

  @override
  void close() {
    for (final c in _open) {
      c.close();
    }
    _open.clear();
  }
}

final testProfile = RobotProfile(
  id: 'test',
  name: 'L40 Ultra',
  url: 'http://192.168.1.122/',
  model: 'L40 Ultra',
  manufacturer: 'Dreame',
  addedAt: DateTime(2026),
);

Future<List<Override>> fakeRobotOverrides(
  FixtureHttpClient http, {
  List<RobotProfile>? profiles,
  Map<String, Object> prefs = const {},
  Directory? historyDir,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(sp),
    secretStoreProvider.overrideWithValue(MemorySecretStore()),
    initialProfilesProvider.overrideWithValue(profiles ?? [testProfile]),
    ...(() {
      final dir =
          historyDir ?? Directory.systemTemp.createTempSync('valrove_history');
      return [
        historyStoreProvider.overrideWith((ref) async => HistoryStore(dir)),
        robotFilesProvider.overrideWith((ref) async => RobotFiles(dir)),
      ];
    })(),
    clientFactoryProvider.overrideWithValue(
      (endpoint) => ValetudoClient(
        ValetudoTransport(endpoint, client: http, streamClient: http),
      ),
    ),
  ];
}

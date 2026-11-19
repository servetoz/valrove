import 'dart:convert';
import 'dart:io';

import 'cleanup_record.dart';

/// Recorded cleanups, one JSON file per robot. Written by the background
/// service and the app, so every change re-reads the file first.
class HistoryStore {
  HistoryStore(this.directory);

  final Directory directory;

  /// Older cleanups are dropped beyond this.
  static const maxRecords = 300;

  File _file(String robotId) {
    final safe = robotId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
    return File('${directory.path}/cleanups_$safe.json');
  }

  /// Newest first.
  Future<List<CleanupRecord>> load(String robotId) async {
    final file = _file(robotId);
    try {
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      return [for (final r in json as List) CleanupRecord.fromJson(r)]
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> add(CleanupRecord record) async {
    final records = await load(record.robotId)
      ..removeWhere((r) => r.id == record.id)
      ..add(record)
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    await _write(record.robotId, records.take(maxRecords).toList());
  }

  Future<void> delete(String robotId, String id) async {
    final records = await load(robotId)
      ..removeWhere((r) => r.id == id);
    await _write(robotId, records);
  }

  Future<void> clear(String robotId) async {
    final file = _file(robotId);
    if (await file.exists()) await file.delete();
  }

  Future<void> _write(String robotId, List<CleanupRecord> records) async {
    await directory.create(recursive: true);
    final file = _file(robotId);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final r in records) r.toJson()]),
      flush: true,
    );
    await temp.rename(file.path);
  }
}

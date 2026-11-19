import 'dart:convert';
import 'dart:io';

/// JSON files (and folders) kept per robot. Written by the app and by the
/// background service, so callers read before every change.
class RobotFiles {
  RobotFiles(this.root);

  final Directory root;

  static String _safe(String id) =>
      id.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');

  File file(String robotId, String name) =>
      File('${root.path}/${_safe(robotId)}_$name.json');

  Directory folder(String robotId, String name) =>
      Directory('${root.path}/${_safe(robotId)}_$name');

  Future<Object?> read(String robotId, String name) async {
    try {
      final f = file(robotId, name);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String robotId, String name, Object? json) async {
    await root.create(recursive: true);
    final f = file(robotId, name);
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(f.path);
  }

  Future<void> delete(String robotId, String name) async {
    final f = file(robotId, name);
    if (await f.exists()) await f.delete();
  }
}

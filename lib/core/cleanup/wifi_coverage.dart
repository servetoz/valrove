import '../valetudo/json_utils.dart';
import 'robot_files.dart';

/// How good a Wi-Fi signal is.
enum SignalQuality {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  weak('Weak'),
  poor('Poor');

  const SignalQuality(this.label);

  final String label;

  static SignalQuality of(double dbm) => dbm >= -55
      ? excellent
      : dbm >= -65
      ? good
      : dbm >= -72
      ? fair
      : dbm >= -80
      ? weak
      : poor;
}

/// One square of the coverage grid.
class WifiCell {
  WifiCell(this.x, this.y, this.average, this.count, this.lastSeen);

  /// Grid position (cell index, not centimetres).
  final int x;
  final int y;
  double average;
  int count;
  DateTime lastSeen;
}

/// Wi-Fi signal strength measured where the robot was, on a grid.
class WifiCoverage {
  WifiCoverage({this.cellCm = defaultCellCm, Map<(int, int), WifiCell>? cells})
    : cells = cells ?? {};

  factory WifiCoverage.fromJson(Object? json) {
    final j = asJson(json);
    final coverage = WifiCoverage(cellCm: asInt(j['cellCm'], defaultCellCm));
    for (final c in asList(j['cells'])) {
      final v = asList(c);
      if (v.length < 5) continue;
      final cell = WifiCell(
        asInt(v[0]),
        asInt(v[1]),
        asDouble(v[2]),
        asInt(v[3]),
        DateTime.fromMillisecondsSinceEpoch(asInt(v[4])),
      );
      coverage.cells[(cell.x, cell.y)] = cell;
    }
    return coverage;
  }

  static const defaultCellCm = 50;

  /// Newer readings count as much as this many older ones together, so the
  /// map follows a router that was moved.
  static const memory = 20;

  final int cellCm;
  final Map<(int, int), WifiCell> cells;

  bool get isEmpty => cells.isEmpty;

  /// A reading of [dbm] with the robot at [x], [y] (centimetres).
  void add(int x, int y, double dbm, DateTime at) {
    final key = (x ~/ cellCm, y ~/ cellCm);
    final cell = cells[key];
    if (cell == null) {
      cells[key] = WifiCell(key.$1, key.$2, dbm, 1, at);
      return;
    }
    final n = cell.count < memory ? cell.count : memory - 1;
    cell
      ..average = (cell.average * n + dbm) / (n + 1)
      ..count = cell.count + 1
      ..lastSeen = at;
  }

  double? get average => cells.isEmpty
      ? null
      : cells.values.fold(0.0, (s, c) => s + c.average) / cells.length;

  WifiCell? get weakest => cells.isEmpty
      ? null
      : cells.values.reduce((a, b) => a.average <= b.average ? a : b);

  /// Centre of [cell] in centimetres.
  (int, int) centreOf(WifiCell cell) =>
      (cell.x * cellCm + cellCm ~/ 2, cell.y * cellCm + cellCm ~/ 2);

  Json toJson() => {
    'cellCm': cellCm,
    'cells': [
      for (final c in cells.values)
        [
          c.x,
          c.y,
          double.parse(c.average.toStringAsFixed(1)),
          c.count,
          c.lastSeen.millisecondsSinceEpoch,
        ],
    ],
  };
}

class WifiCoverageStore {
  WifiCoverageStore(this.files);

  final RobotFiles files;
  static const _name = 'wifi';

  Future<WifiCoverage> load(String robotId) async {
    final json = await files.read(robotId, _name);
    return json == null ? WifiCoverage() : WifiCoverage.fromJson(json);
  }

  Future<void> add(
    String robotId,
    int x,
    int y,
    double dbm,
    DateTime at,
  ) async {
    final coverage = await load(robotId)
      ..add(x, y, dbm, at);
    await files.write(robotId, _name, coverage.toJson());
  }

  Future<void> clear(String robotId) => files.delete(robotId, _name);
}

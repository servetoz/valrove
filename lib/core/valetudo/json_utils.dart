/// Tolerant JSON accessors.
///
/// Valetudo is developed independently of this app and forks add fields, so
/// every model is parsed defensively: unknown fields are ignored and missing or
/// mistyped fields fall back to sensible defaults instead of throwing.
library;

typedef Json = Map<String, dynamic>;

Json asJson(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return const {};
}

List<dynamic> asList(Object? value) => value is List ? value : const [];

List<Json> asJsonList(Object? value) => asList(value).map(asJson).toList();

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

String asString(Object? value, [String fallback = '']) =>
    asStringOrNull(value) ?? fallback;

num? asNumOrNull(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

double asDouble(Object? value, [double fallback = 0]) =>
    asNumOrNull(value)?.toDouble() ?? fallback;

int asInt(Object? value, [int fallback = 0]) =>
    asNumOrNull(value)?.round() ?? fallback;

int? asIntOrNull(Object? value) => asNumOrNull(value)?.round();

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return fallback;
}

List<String> asStringList(Object? value) =>
    asList(value).map((e) => asString(e)).where((e) => e.isNotEmpty).toList();

DateTime? asDateTime(Object? value) {
  final s = asStringOrNull(value);
  if (s == null) return null;
  return DateTime.tryParse(s);
}

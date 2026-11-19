import '../valetudo/client/transport.dart';
import '../valetudo/json_utils.dart';

/// A saved robot connection.
class RobotProfile {
  const RobotProfile({
    required this.id,
    required this.name,
    required this.url,
    this.username,
    this.password,
    this.model,
    this.manufacturer,
    this.systemId,
    required this.addedAt,
  });

  factory RobotProfile.fromJson(Json json) => RobotProfile(
    id: asString(json['id']),
    name: asString(json['name'], 'Robot'),
    url: asString(json['url']),
    username: asStringOrNull(json['username']),
    model: asStringOrNull(json['model']),
    manufacturer: asStringOrNull(json['manufacturer']),
    systemId: asStringOrNull(json['systemId']),
    addedAt: asDateTime(json['addedAt']) ?? DateTime.now(),
  );

  final String id;
  final String name;

  /// Normalized base URL (always ends with `/`).
  final String url;
  final String? username;

  /// Kept in secure storage; never serialized by [toJson].
  final String? password;
  final String? model;
  final String? manufacturer;
  final String? systemId;
  final DateTime addedAt;

  ValetudoEndpoint get endpoint => ValetudoEndpoint(
    baseUri: Uri.parse(url),
    username: username,
    password: password,
  );

  /// Changes whenever the connection parameters change.
  String get connectionKey => '$url|${username ?? ''}|${password ?? ''}';

  String get subtitle {
    final parts = [
      if (manufacturer != null && model != null)
        '$manufacturer $model'
      else
        ?model,
      endpoint.displayHost,
    ];
    return parts.join(' · ');
  }

  RobotProfile copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    bool clearCredentials = false,
    String? model,
    String? manufacturer,
    String? systemId,
  }) => RobotProfile(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    username: clearCredentials ? null : (username ?? this.username),
    password: clearCredentials ? null : (password ?? this.password),
    model: model ?? this.model,
    manufacturer: manufacturer ?? this.manufacturer,
    systemId: systemId ?? this.systemId,
    addedAt: addedAt,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'url': url,
    if (username != null) 'username': username,
    if (model != null) 'model': model,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (systemId != null) 'systemId': systemId,
    'addedAt': addedAt.toIso8601String(),
  };
}

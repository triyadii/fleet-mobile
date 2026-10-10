/// Lenient JSON readers.
///
/// The backend is a Laravel API whose numeric columns may be serialised either
/// as numbers or as strings (e.g. `"lat": "-6.2"`), and whose list endpoints
/// may or may not be wrapped in `data` / paginated `data.data` envelopes.
/// These helpers keep model parsing tolerant of those variations.
library;

typedef JsonMap = Map<String, dynamic>;

/// Parses [value] into a `double`, accepting numbers and numeric strings.
double? asDouble(Object? value) => switch (value) {
  num v => v.toDouble(),
  String v => double.tryParse(v),
  _ => null,
};

/// Parses [value] into an `int`, accepting numbers and numeric strings.
int? asInt(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v),
  _ => null,
};

/// Returns a non-empty string representation of [value], or `null`.
String? asString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Returns [value] as a map when it is one, otherwise `null`.
JsonMap? asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : null;

/// Extracts a list of objects from common API envelope shapes:
/// `[...]`, `{data: [...]}`, `{data: {data: [...]}}` or `{data: {<key>: [...]}}`.
List<JsonMap> extractList(Object? body, {String? key}) {
  Object? node = body;
  for (var depth = 0; depth < 3; depth++) {
    if (node is List) {
      return node
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    final map = asMap(node);
    if (map == null) break;
    node = (key != null && map[key] != null) ? map[key] : map['data'];
  }
  return const [];
}

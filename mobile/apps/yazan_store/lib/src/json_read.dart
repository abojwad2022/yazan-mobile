/// Tolerant readers for server JSON: a wrong or missing field becomes an empty value, never a crash.

Map<String, dynamic> asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map<String, dynamic>((k, val) => MapEntry('$k', val));
  return const <String, dynamic>{};
}

List<dynamic> asList(Object? v) => v is List ? v : const <dynamic>[];

String asStr(Object? v, [String fallback = '']) => v is String ? v : fallback;

int? asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

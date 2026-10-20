/// True when a database-open error means "this file is not readable with the key we have"
/// (SQLite error 26, SQLITE_NOTADB: wrong key, damaged file, or a plain-SQLite file).
///
/// Message based on purpose: the driver surfaces the native error as text. Anything that does not
/// match is treated as a real failure and is NOT answered by deleting the file.
bool looksLikeWrongKey(Object error) {
  final m = error.toString().toLowerCase();
  return m.contains('file is not a database') ||
      m.contains('file is encrypted or is not a database') ||
      m.contains('sqlite_notadb') ||
      RegExp(r'code 26\b').hasMatch(m);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_storage/yazan_storage.dart';

void main() {
  test('recognises the SQLCipher wrong-key / not-a-database errors', () {
    expect(looksLikeWrongKey(Exception('file is not a database (code 26 SQLITE_NOTADB)')), isTrue);
    expect(looksLikeWrongKey('DatabaseException(file is encrypted or is not a database)'), isTrue);
    expect(looksLikeWrongKey('open_failed ... (code 26)'), isTrue);
  });

  test('does not treat other failures as a wrong key', () {
    expect(looksLikeWrongKey(Exception('database or disk is full (code 13)')), isFalse);
    expect(looksLikeWrongKey(Exception('unable to open database file (code 14)')), isFalse);
    expect(looksLikeWrongKey(Exception('error code 267')), isFalse);
    expect(looksLikeWrongKey(StateError('boom')), isFalse);
  });
}

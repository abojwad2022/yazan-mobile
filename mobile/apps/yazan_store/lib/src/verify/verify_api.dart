import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import 'serial.dart';
import 'verify_models.dart';

/// The public ring lookup (`GET /yazan-mobile/v1/verify/{serial}`). It needs no account.
///
/// Throws `ApiError` for a server answer (404 = no such ring, 429 = too many checks from this
/// address) and any other exception for a network problem.
abstract class VerifyApi {
  Future<RingCertificate> lookup(String serial);
}

class ClientVerifyApi implements VerifyApi {
  ClientVerifyApi(this._client);

  final YazanApiClient _client;

  @override
  Future<RingCertificate> lookup(String serial) async {
    // Cleaned again here so nothing but letters, digits and hyphens ever reaches the path.
    final clean = cleanSerial(serial);
    if (clean.length < serialMinLength) {
      throw const ApiError(status: 404, code: 'yazan_mobile_no_ring');
    }
    // A session, when there is one, is sent but never required.
    final body = await _client.getJson('/yazan-mobile/v1/verify/$clean', optionalAuth: true);
    return RingCertificate.fromJson(body);
  }
}

import 'package:yazan_api_client/yazan_api_client.dart';

import 'product_detail_controller.dart';
import 'product_permissions.dart';

// Production wiring of the product screen's injected functions. Routes and bodies are the web
// dashboard's (`dashboard-app/src/api/endpoints.js` -> `Yazan_REST_Products`).

/// `GET /yazan/v1/products/{id}`; a phone admin session gets the version token as the ETag.
VersionedProductLoader productLoader(YazanApiClient client) =>
    (id) => client.getJsonWithVersion('/yazan/v1/products/$id');

/// `PUT /yazan/v1/products/{id}` with only the fields being changed, `If-Match` and `Idempotency-Key`.
/// The bulk and quick-edit routes are refused to phone sessions, so this is the only write.
ProductWriter productWriter(YazanApiClient client) => (
      int id,
      Map<String, dynamic> fields, {
      required String version,
      required String idempotencyKey,
    }) =>
        client.sendJson(
          'PUT',
          '/yazan/v1/products/$id',
          data: fields,
          idempotencyKey: idempotencyKey,
          ifMatch: version,
        );

/// `GET /yazan-mobile/v1/me`: the account and its permission map.
PermissionsLoader permissionsLoader(YazanApiClient client) =>
    () => client.getJson('/yazan-mobile/v1/me');

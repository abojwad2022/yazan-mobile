import 'package:yazan_api_client/yazan_api_client.dart';

// Production wiring of the staff screens' injected functions. Routes are the web dashboard's
// (`Yazan_REST_Users`, `Yazan_REST_Roles`, namespace `yazan/v1`), all inside the admin scope's
// `/yazan/v1/` fence. Permissions: `users.view` (list, detail), `roles.view` (role permissions),
// `users.force_logout` (sign out everywhere).

/// One page of `GET /yazan/v1/users` (`items`, `total_pages`, ...).
typedef StaffFetch = Future<Map<String, dynamic>> Function(int page);

/// `GET /yazan/v1/roles`: every role with its granted permission slugs (`items[].permissions`).
typedef StaffRolesLoader = Future<Map<String, dynamic>> Function();

/// `POST /yazan/v1/users/{id}/force-logout` with an `Idempotency-Key`. Throws [ApiError] for a
/// server answer; any other exception means "no network".
typedef StaffSignOutEverywhere = Future<Map<String, dynamic>> Function(
  int id, {
  required String idempotencyKey,
});

/// How many accounts one page asks for (the route caps it at 100).
const int staffPerPage = 100;

StaffFetch staffFetch(YazanApiClient client) => (page) =>
    client.getJson('/yazan/v1/users', query: {'page': page, 'per_page': staffPerPage});

StaffRolesLoader staffRolesLoader(YazanApiClient client) =>
    () => client.getJson('/yazan/v1/roles', query: {'with_counts': 0});

StaffSignOutEverywhere staffSignOutEverywhere(YazanApiClient client) => (
      int id, {
      required String idempotencyKey,
    }) =>
        client.sendJson('POST', '/yazan/v1/users/$id/force-logout',
            data: const <String, dynamic>{}, idempotencyKey: idempotencyKey);

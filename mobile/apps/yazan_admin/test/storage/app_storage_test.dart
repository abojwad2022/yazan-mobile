import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/app.dart';
import 'package:yazan_admin/src/session_events.dart';
import 'package:yazan_admin/src/storage/account_id_store.dart';
import 'package:yazan_admin/src/storage/account_lifecycle.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../customers/fakes.dart' show customerRows;
import 'fakes.dart';

// The whole shell with the real client, repositories and home screen, over an in-memory durable
// store and a scripted server. What is checked: whose data is shown, and when it is wiped.

/// The server the app talks to.
class Server {
  Map<String, dynamic> me = {
    'id': 7,
    'scope': 'admin',
    'permissions': {'orders.view': true, 'customers.view': true, 'products.view': true},
  };
  int meStatus = 200;
  int ordersStatus = 200;
  int logouts = 0;

  (int, Object?) route(RequestOptions o) {
    final p = o.path;
    if (p.endsWith('/yazan-mobile/v1/me')) {
      return (meStatus, meStatus == 200 ? me : {'code': 'yazan_forbidden', 'message': 'no'});
    }
    if (p.endsWith('/sync/orders')) {
      return ordersStatus == 200
          ? (200, emptyPage)
          : (ordersStatus, {'code': 'yazan_mobile_bad_token', 'message': 'expired'});
    }
    if (p.endsWith('/sync/catalog')) return (200, emptyPage);
    if (p.endsWith('/yazan/v1/customers')) return (200, {'items': customerRows, 'total_pages': 1});
    if (p.endsWith('/auth/refresh')) {
      return (401, {'code': 'yazan_mobile_bad_refresh', 'message': 'revoked'});
    }
    if (p.endsWith('/auth/logout')) {
      logouts++;
      return (200, {'ok': true});
    }
    return (404, {'code': 'not_found', 'message': 'x'});
  }
}

class Rig {
  Rig({this.recreated = false, bool signedIn = true}) : storage = FakeAccountStorage() {
    server = Server();
    tokens = MemoryTokenStore();
    client = scriptedClient(tokens, ScriptedAdapter(server.route), onSignedOut: events.sessionEnded);
    accounts = AccountLifecycle(
      storage: storage,
      ids: ids,
      loadMe: () => client.getJson('/yazan-mobile/v1/me'),
      namespace: 'shop.test',
      storageRecreated: recreated,
    );
    _signedIn = signedIn;
  }

  final bool recreated;
  final FakeAccountStorage storage;
  final MemoryAccountIdStore ids = MemoryAccountIdStore();
  final SessionEvents events = SessionEvents();
  late final Server server;
  late final MemoryTokenStore tokens;
  late final YazanApiClient client;
  late final AccountLifecycle accounts;
  late final bool _signedIn;

  Future<void> pump(WidgetTester tester) async {
    if (_signedIn) {
      await tokens.write(Session.fromJson(
          {'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900}));
    }
    await tester.pumpWidget(YazanApp(
      client: client,
      tokens: tokens,
      accounts: accounts,
      events: events,
    ));
    await tester.pumpAndSettle();
  }
}

Map<String, dynamic> _order(int id, String name) => {
      'id': id,
      'number': '$id',
      'status': 'processing',
      'total': '10.00',
      'currency': 'USD',
      'items': 1,
      'name': name,
      'created': '2026-10-01 10:00:00',
      'modified': '2026-10-01 10:00:00',
      'version': 'v1',
    };

void main() {
  testWidgets('shows the cache of the signed-in account and never another account\'s', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'));
    await rig.storage.seed('shop.test:3', order: _order(99, 'Omar Three'));
    await rig.ids.write('shop.test:7');

    await rig.pump(t);
    await t.tap(find.byKey(const ValueKey('tab-orders')));
    await t.pumpAndSettle();

    expect(find.text('Sara Seven'), findsOneWidget);
    expect(find.text('Omar Three'), findsNothing);
    expect(rig.storage.rowCount('shop.test:3'), 2, reason: 'not this phone user\'s data, left alone');
  });

  testWidgets('sign-out asks about unsent notes, then wipes the whole account', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'));
    await rig.ids.write('shop.test:7');
    await rig.pump(t);

    // Cancel keeps everything.
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(find.text('Notes saved on this phone and not sent yet: 1. Signing out deletes them.'),
        findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sign-out-cancel')));
    await t.pumpAndSettle();
    expect(rig.storage.rowCount('shop.test:7'), greaterThan(0));
    expect(await rig.storage.outbox.all('shop.test:7'), hasLength(1));
    expect(find.text('Sign out'), findsOneWidget);

    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('sign-out-anyway')));
    await t.pumpAndSettle();

    expect(rig.storage.rowCount('shop.test:7'), 0);
    expect(await rig.storage.outbox.all('shop.test:7'), isEmpty);
    expect(await rig.ids.read(), isNull);
    expect(rig.server.logouts, 1);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sara Seven'), findsNothing);
  });

  testWidgets('a revoked session (refresh refused) wipes the account and shows sign-in', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'));
    await rig.ids.write('shop.test:7');
    rig.server.ordersStatus = 401; // access token rejected, and /auth/refresh answers bad_refresh

    await rig.pump(t);
    expect(rig.storage.rowCount('shop.test:7'), greaterThan(0));
    await t.tap(find.byKey(const ValueKey('tab-orders'))); // the first orders pull finds it out
    await t.pumpAndSettle();

    expect(rig.storage.rowCount('shop.test:7'), 0);
    expect(await rig.storage.outbox.all('shop.test:7'), isEmpty);
    expect(await rig.ids.read(), isNull);
    expect(await rig.tokens.read(), isNull);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sara Seven'), findsNothing);
  });

  testWidgets('losing the customers permission deletes the cached customers only', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'), customers: customerRows);
    await rig.ids.write('shop.test:7');
    rig.server.me = {
      'id': 7,
      'scope': 'admin',
      'permissions': {'orders.view': true, 'products.view': true},
    };
    await rig.pump(t);
    expect(rig.storage.raw('shop.test:7', 'customers').rows, isNotEmpty);

    await t.tap(find.byKey(const ValueKey('tab-customers')));
    await t.pumpAndSettle();

    expect(rig.storage.raw('shop.test:7', 'customers').rows, isEmpty);
    expect(rig.storage.raw('shop.test:7', 'customers').cursor, '');
    expect(rig.storage.raw('shop.test:7', 'orders').rows, hasLength(1));
    expect(await rig.storage.outbox.all('shop.test:7'), hasLength(1));
  });

  testWidgets('the server naming a different account wipes the old cache', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:3', order: _order(99, 'Omar Three'));
    await rig.ids.write('shop.test:3');
    // /me says this session belongs to staff member 7.

    await rig.pump(t);
    await t.tap(find.byKey(const ValueKey('tab-orders')));
    await t.pumpAndSettle();

    expect(rig.storage.rowCount('shop.test:3'), 0);
    expect(await rig.storage.outbox.all('shop.test:3'), isEmpty);
    expect(await rig.ids.read(), 'shop.test:7');
    expect(find.text('Omar Three'), findsNothing);
  });

  testWidgets('an account the server no longer admits is wiped and signed out', (t) async {
    final rig = Rig();
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'));
    await rig.ids.write('shop.test:7');
    rig.server.meStatus = 403;

    await rig.pump(t);

    expect(rig.storage.rowCount('shop.test:7'), 0);
    expect(await rig.ids.read(), isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('starting with no session removes whatever an unfinished sign-out left', (t) async {
    final rig = Rig(signedIn: false);
    await rig.storage.seed('shop.test:7', order: _order(5, 'Sara Seven'));
    await rig.ids.write('shop.test:7');

    await rig.pump(t);

    expect(rig.storage.rowCount('shop.test:7'), 0);
    expect(await rig.storage.outbox.all('shop.test:7'), isEmpty);
    expect(await rig.ids.read(), isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a reset database is announced once', (t) async {
    final rig = Rig(recreated: true);
    await rig.ids.write('shop.test:7');

    await rig.pump(t);
    expect(find.byKey(const ValueKey('storage-reset-notice')), findsOneWidget);
    expect(find.text('Saved data was reset'), findsOneWidget);

    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('storage-reset-notice')), findsNothing);

    // Moving around the app does not bring it back.
    await t.tap(find.byKey(const ValueKey('tab-products')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('storage-reset-notice')), findsNothing);
  });

  testWidgets('no notice when the database was fine', (t) async {
    final rig = Rig();
    await rig.ids.write('shop.test:7');
    await rig.pump(t);
    expect(find.byKey(const ValueKey('storage-reset-notice')), findsNothing);
  });
}

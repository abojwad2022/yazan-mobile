import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_api_client/yazan_api_client.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_store/src/app.dart';
import 'package:yazan_store/src/cart/store_api.dart';
import 'package:yazan_store/src/storage/local_data.dart';

import 'fixtures/account_fakes.dart';
import 'fixtures/catalogue_fixtures.dart';
import 'fixtures/local_data_fakes.dart';
import 'fixtures/store_cart.dart';

/// Opens the app over [data]. No repository is injected, so the catalogue comes from [client]
/// through the durable cache, exactly as `main` wires it.
Future<FakeAccountApi> _open(
  WidgetTester tester, {
  required CatalogueClient client,
  required MemoryTokenStore tokens,
  required MemoryLocalData data,
}) async {
  final account = FakeAccountApi();
  await tester.pumpWidget(YazanApp(
    client: client,
    tokens: tokens,
    storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
    accountApi: account,
    wishlistApi: FakeWishlistApi([ring(1, 'Alpha ring')]),
    localData: data,
  ));
  await tester.pumpAndSettle();
  return account;
}

void main() {
  group('DurableLocalData', () {
    test('keeps the catalogue under the guest account and forgets only the signed-in one', () async {
      final storage = FakeYazanStorage(recreated: true);
      final data = DurableLocalData(storage);

      expect(data.recreated, isTrue);
      expect(data.catalogue(), same(storage.store));
      expect(storage.feedCalls, ['${SqlFeedStore.guestAccountId}/$catalogueFeedName']);

      await data.forgetAccount();
      expect(storage.wipeCalls, [signedInAccountId]);
      expect(storage.wipeCalls, isNot(contains(SqlFeedStore.guestAccountId)));
    });

    test('the public categories are a separate feed under the guest account', () {
      final storage = FakeYazanStorage();
      DurableLocalData(storage).categories();
      expect(storage.feedCalls, ['${SqlFeedStore.guestAccountId}/$categoriesFeedName']);
      expect(categoriesFeedName, isNot(catalogueFeedName));
    });

    test('the signed-in key is never the guest key', () {
      expect(signedInAccountId, isNot(SqlFeedStore.guestAccountId));
    });
  });

  group('catalogue cache', () {
    testWidgets('a pull is saved to the guest feed and shown again after a restart offline',
        (tester) async {
      final data = MemoryLocalData();
      final tokens = MemoryTokenStore();
      final online = CatalogueClient(tokens, records: [simpleRecord()]);
      await _open(tester, client: online, tokens: tokens, data: data);
      expect(find.text('Carnelian ring'), findsOneWidget);
      final saved = data.feedFor(SqlFeedStore.guestAccountId, catalogueFeedName);
      expect(saved.rows.keys.toList(), [13]);
      expect(saved.cursor, 'c1');

      // A new run of the app, no connection: the saved catalogue is what the customer sees.
      await tester.pumpWidget(const SizedBox.shrink());
      final offline = CatalogueClient(tokens, offline: true);
      await _open(tester, client: offline, tokens: tokens, data: data);
      expect(find.text('Carnelian ring'), findsOneWidget);
      expect(find.text('Offline - showing saved items'), findsOneWidget);
      // The saved cursor is what the next pull resumes from.
      expect(offline.cursors, ['c1']);
    });

    testWidgets('without local data the catalogue still works from memory', (tester) async {
      final tokens = MemoryTokenStore();
      final client = CatalogueClient(tokens, records: [simpleRecord()]);
      await tester.pumpWidget(YazanApp(
        client: client,
        tokens: tokens,
        storeApi: StoreApi(FakeTransport((r) => ok(storeCart(images: false))).call),
        accountApi: FakeAccountApi(),
        wishlistApi: FakeWishlistApi(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Carnelian ring'), findsOneWidget);
    });
  });

  group('account data', () {
    testWidgets('a guest start clears anything a cut-short sign-out left behind', (tester) async {
      final data = MemoryLocalData();
      data.feedFor(signedInAccountId, 'orders').rows[1] = {'id': 1};
      final tokens = MemoryTokenStore();
      await _open(tester,
          client: CatalogueClient(tokens, records: [simpleRecord()]), tokens: tokens, data: data);
      expect(data.wiped, [signedInAccountId]);
      expect(data.hasFeed(signedInAccountId, 'orders'), isFalse);
      expect(find.text('Carnelian ring'), findsOneWidget);
    });

    testWidgets('a signed-in start keeps the account data', (tester) async {
      final data = MemoryLocalData();
      data.feedFor(signedInAccountId, 'orders').rows[1] = {'id': 1};
      final tokens = MemoryTokenStore();
      await tokens.write(testSession());
      await _open(tester,
          client: CatalogueClient(tokens, records: [simpleRecord()]), tokens: tokens, data: data);
      expect(data.wiped, isEmpty);
      expect(data.feedFor(signedInAccountId, 'orders').rows, isNotEmpty);
    });

    testWidgets('sign-out wipes the account but keeps the catalogue copy', (tester) async {
      final data = MemoryLocalData();
      data.feedFor(signedInAccountId, 'orders').rows[1] = {'id': 1};
      final tokens = MemoryTokenStore();
      await tokens.write(testSession());
      final client = CatalogueClient(tokens, records: [simpleRecord()]);
      await _open(tester, client: client, tokens: tokens, data: data);
      expect(data.wiped, isEmpty);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(client.loggedOut, isTrue);
      expect(data.wiped, [signedInAccountId]);
      expect(data.hasFeed(signedInAccountId, 'orders'), isFalse);
      final catalogue = data.feedFor(SqlFeedStore.guestAccountId, catalogueFeedName);
      expect(catalogue.rows.keys.toList(), [13]);
      expect(find.text('Carnelian ring'), findsOneWidget);
    });

    testWidgets('a session the server ended wipes the account but keeps the catalogue copy',
        (tester) async {
      final data = MemoryLocalData();
      data.feedFor(signedInAccountId, 'orders').rows[1] = {'id': 1};
      final tokens = MemoryTokenStore();
      await tokens.write(testSession());
      final client = CatalogueClient(tokens, records: [simpleRecord()]);
      final account = await _open(tester, client: client, tokens: tokens, data: data);
      account.failure = const ApiError(status: 401, code: 'yazan_mobile_bad_refresh');

      await tester.tap(find.byTooltip('My orders'));
      await tester.pumpAndSettle();

      expect(data.wiped, [signedInAccountId]);
      expect(data.hasFeed(signedInAccountId, 'orders'), isFalse);
      expect(data.feedFor(SqlFeedStore.guestAccountId, catalogueFeedName).rows.keys.toList(), [13]);
    });

    testWidgets('a wipe that fails does not stop the sign-out', (tester) async {
      final data = MemoryLocalData()..wipeFailure = StateError('disk');
      final tokens = MemoryTokenStore();
      await tokens.write(testSession());
      final client = CatalogueClient(tokens, records: [simpleRecord()]);
      await _open(tester, client: client, tokens: tokens, data: data);

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(client.loggedOut, isTrue);
      expect(await tokens.read(), isNull);
      expect(find.text('Carnelian ring'), findsOneWidget);
    });
  });

  group('recreated database', () {
    const message = 'Saved data on this phone could not be read, so it was reset. '
        'The shop will download again.';

    testWidgets('tells the customer once', (tester) async {
      final tokens = MemoryTokenStore();
      await _open(tester,
          client: CatalogueClient(tokens, records: [simpleRecord()]),
          tokens: tokens,
          data: MemoryLocalData(recreated: true));
      expect(find.text(message), findsOneWidget);

      // It goes away on its own and does not come back when the customer moves around.
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text(message), findsNothing);
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      // A guest gets the sign-in sheet, which closes with its close button (no back arrow).
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing);
    });

    testWidgets('says nothing when the database was fine', (tester) async {
      final tokens = MemoryTokenStore();
      await _open(tester,
          client: CatalogueClient(tokens, records: [simpleRecord()]),
          tokens: tokens,
          data: MemoryLocalData());
      expect(find.text(message), findsNothing);
    });
  });
}

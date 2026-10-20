import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_admin/src/products/product_detail_controller.dart';
import 'package:yazan_admin/src/products/product_permissions.dart';
import 'package:yazan_domain/yazan_domain.dart';

import '../orders/fakes.dart' show KeySeq;
import 'fakes.dart';

ProductDetailController _controller(
  FakeProductServer server, {
  ProductPermissions? permissions,
  PermissionsLoader? loadPermissions,
  KeySeq? keys,
}) {
  return ProductDetailController(
    productId: 7,
    load: server.load,
    write: server.write,
    permissions: permissions ?? ProductPermissions.of(allProductPermissions),
    loadPermissions: loadPermissions,
    newKey: (keys ?? KeySeq()).next,
  );
}

const ApiError _stale = ApiError(status: 412, code: 'yazan_precondition_failed', current: 'v2');

void main() {
  group('reading', () {
    test('load reads the record and its version', () async {
      final server = FakeProductServer();
      final c = _controller(server);
      await c.load();
      expect(c.loading, isFalse);
      expect(c.failed, isFalse);
      expect(c.regularPrice, '120.00');
      expect(c.salePrice, '');
      expect(c.stockQuantity, 3);
      expect(c.version, 'v1');
      expect(c.canEditPrice, isTrue);
      expect(c.canEditStock, isTrue);
    });

    test('a 403 on the read is no access', () async {
      final server = FakeProductServer()..loadError = const ApiError(status: 403, code: 'yazan_forbidden');
      final c = _controller(server);
      await c.load();
      expect(c.noAccess, isTrue);
      expect(c.failed, isTrue);
    });

    test('a network failure on the read is a failure, not no access', () async {
      final server = FakeProductServer()..loadError = Exception('offline');
      final c = _controller(server);
      await c.load();
      expect(c.noAccess, isFalse);
      expect(c.failed, isTrue);
    });
  });

  group('permissions', () {
    test('unknown permissions keep every edit off until /me answers', () async {
      final server = FakeProductServer();
      final c = _controller(
        server,
        permissions: const ProductPermissions.unknown(),
        loadPermissions: () async => FakeProductServer.me(allProductPermissions),
      );
      await c.load();
      expect(c.permissions.known, isTrue);
      expect(c.canEditPrice, isTrue);
      expect(c.canEditStock, isTrue);
    });

    test('permissions that cannot be read leave edits off', () async {
      final server = FakeProductServer();
      final c = _controller(
        server,
        permissions: const ProductPermissions.unknown(),
        loadPermissions: () async => throw Exception('offline'),
      );
      await c.load();
      expect(c.permissions.known, isFalse);
      expect(c.canEditPrice, isFalse);
      expect(c.canEditStock, isFalse);
    });

    test('without change_price the price is not editable and nothing is sent', () async {
      final server = FakeProductServer();
      final c = _controller(
        server,
        permissions: ProductPermissions.of(['products.view', 'products.edit', 'products.change_stock']),
      );
      await c.load();
      expect(c.canEditPrice, isFalse);
      expect(c.canEditStock, isTrue);
      expect(await c.savePrice(regular: '130.00', sale: ''), ProductEditResult.noAccess);
      expect(server.writes, isEmpty);
    });

    test('without products.edit neither edit is allowed', () async {
      final server = FakeProductServer();
      final c = _controller(
        server,
        permissions: ProductPermissions.of(['products.view', 'products.change_price', 'products.change_stock']),
      );
      await c.load();
      expect(c.canEditPrice, isFalse);
      expect(c.canEditStock, isFalse);
      expect(await c.saveStock(1), ProductEditResult.noAccess);
      expect(server.writes, isEmpty);
    });

    test('a map with products.view only is read-only; an empty list means nothing is granted', () {
      expect(ProductPermissions.fromMe(FakeProductServer.me(['products.view'])).canEditStock, isFalse);
      final none = ProductPermissions.fromMe({'permissions': <Object?>[]});
      expect(none.known, isTrue);
      expect(none.canView, isFalse);
      expect(ProductPermissions.fromMe({'id': 1}).known, isFalse);
    });
  });

  group('what can be edited', () {
    test('a variable product is not editable here', () async {
      final server = FakeProductServer()..type = 'variable';
      final c = _controller(server);
      await c.load();
      expect(c.isVariable, isTrue);
      expect(c.canEditPrice, isFalse);
      expect(c.canEditStock, isFalse);
      expect(await c.savePrice(regular: '130.00', sale: ''), ProductEditResult.noAccess);
      expect(server.writes, isEmpty);
    });

    test('stock that is not counted by quantity is not editable', () async {
      final server = FakeProductServer()
        ..manageStock = false
        ..stock = null;
      final c = _controller(server);
      await c.load();
      expect(c.canEditPrice, isTrue);
      expect(c.canEditStock, isFalse);
    });
  });

  group('price', () {
    test('saves with the version read, a fresh key, and shows the new price', () async {
      final server = FakeProductServer();
      final c = _controller(server);
      await c.load();
      final result = await c.savePrice(regular: '150.00', sale: '99.00');
      expect(result, ProductEditResult.done);
      expect(server.writes.single.fields, {'regular_price': '150.00', 'sale_price': '99.00'});
      expect(server.writes.single.version, 'v1');
      expect(server.writes.single.key, 'key-1');
      expect(c.regularPrice, '150.00');
      expect(c.salePrice, '99.00');
      expect(c.version, isNot('v1'));
      expect(c.canRetry, isFalse);
    });

    test('an empty sale price clears it', () async {
      final server = FakeProductServer()..sale = '99.00';
      final c = _controller(server);
      await c.load();
      expect(await c.savePrice(regular: '120.00', sale: ''), ProductEditResult.done);
      expect(server.writes.single.fields['sale_price'], '');
      expect(c.salePrice, '');
    });

    test('a 200 that did not take the value is reported, not shown as success', () async {
      final server = FakeProductServer()..ignorePrice = true;
      final c = _controller(server);
      await c.load();
      expect(await c.savePrice(regular: '150.00', sale: ''), ProductEditResult.notApplied);
      expect(c.regularPrice, '120.00');
      expect(c.lastResult, ProductEditResult.notApplied);
    });
  });

  group('stock', () {
    test('sends the quantity and the quantity this screen read', () async {
      final server = FakeProductServer();
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(5), ProductEditResult.done);
      expect(server.writes.single.fields, {'stock_quantity': 5, 'original_stock_quantity': 3});
      expect(server.writes.single.version, 'v1');
      expect(c.stockQuantity, 5);
    });

    test('zero is a valid quantity and marks the product out of stock', () async {
      final server = FakeProductServer();
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(0), ProductEditResult.done);
      expect(c.stockQuantity, 0);
      expect(c.stockStatus, 'outofstock');
    });
  });

  group('failures', () {
    test('offline is never queued; the retry reuses the same key and version', () async {
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(5), ProductEditResult.offline);
      expect(c.canRetry, isTrue);
      expect(c.lastResult, ProductEditResult.offline);
      expect(await c.retry(), ProductEditResult.done);
      expect(server.writes.length, 2);
      expect(server.writes[1].key, server.writes[0].key);
      expect(server.writes[1].version, 'v1');
      expect(server.writes[1].fields, server.writes[0].fields);
      expect(c.canRetry, isFalse);
    });

    test('saving the same request again after a failure reuses the key', () async {
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      final c = _controller(server);
      await c.load();
      await c.saveStock(5);
      await c.saveStock(5);
      expect(server.writes.map((w) => w.key).toSet().length, 1);
    });

    test('a different request after a failure gets a new key', () async {
      final server = FakeProductServer()..writeFailures.addAll([Exception('offline'), null]);
      final c = _controller(server);
      await c.load();
      await c.saveStock(5);
      await c.saveStock(6);
      expect(server.writes[0].key, 'key-1');
      expect(server.writes[1].key, 'key-2');
    });

    test('409 busy keeps the attempt for a retry with the same key', () async {
      final server = FakeProductServer()
        ..writeFailures.addAll([
          const ApiError(status: 409, code: 'yazan_idempotency_busy', retryAfter: 2),
          null,
        ]);
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(5), ProductEditResult.busy);
      expect(await c.retry(), ProductEditResult.done);
      expect(server.writes[1].key, server.writes[0].key);
    });

    test('403 on the write is no access and the attempt is dropped', () async {
      final server = FakeProductServer()
        ..writeFailures.add(const ApiError(status: 403, code: 'yazan_forbidden'));
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(5), ProductEditResult.noAccess);
      expect(c.canRetry, isFalse);
    });

    test('428 (a client bug) and validation errors show the server message', () async {
      final server = FakeProductServer()
        ..writeFailures.addAll([
          const ApiError(status: 428, code: 'yazan_precondition_required', message: 'Send If-Match'),
          const ApiError(status: 400, code: 'yazan_invalid_price', message: 'Price too low'),
        ]);
      final c = _controller(server);
      await c.load();
      expect(await c.saveStock(5), ProductEditResult.failed);
      expect(c.lastMessage, 'Send If-Match');
      expect(await c.savePrice(regular: '1.00', sale: ''), ProductEditResult.failed);
      expect(c.lastMessage, 'Price too low');
    });

    test('dismiss forgets the attempt', () async {
      final server = FakeProductServer()..writeFailures.add(Exception('offline'));
      final c = _controller(server);
      await c.load();
      await c.saveStock(5);
      c.dismiss();
      expect(c.canRetry, isFalse);
      expect(c.lastResult, isNull);
    });
  });

  group('conflict (412)', () {
    test('a stock change against a stale version opens the conflict, writing nothing', () async {
      final server = FakeProductServer()..writeFailures.add(_stale);
      final c = _controller(server);
      await c.load();
      // Someone sells the ring on the website meanwhile.
      server
        ..stock = 1
        ..version = 'v2';
      expect(await c.saveStock(5), ProductEditResult.conflict);
      final conflict = c.conflict!;
      expect(conflict.kind, ProductEditKind.stock);
      expect(conflict.mineStock, 5);
      expect(conflict.serverStock, 1);
      expect(conflict.serverVersion, 'v2');
      expect(server.stock, 1);
      expect(c.lastResult, isNull);
    });

    test('overwrite sends again against the server version, from the server stock, with a new key', () async {
      final server = FakeProductServer()..writeFailures.add(_stale);
      final c = _controller(server);
      await c.load();
      server
        ..stock = 1
        ..version = 'v2';
      await c.saveStock(5);
      expect(await c.overwrite(), ProductEditResult.done);
      expect(server.writes.map((w) => w.version), ['v1', 'v2']);
      expect(server.writes[1].key, isNot(server.writes[0].key));
      expect(server.writes[1].fields, {'stock_quantity': 5, 'original_stock_quantity': 1});
      expect(server.stock, 5);
      expect(c.conflict, isNull);
    });

    test('a price conflict carries both versions; overwrite resends the price', () async {
      final server = FakeProductServer()..writeFailures.add(_stale);
      final c = _controller(server);
      await c.load();
      server
        ..regular = '200.00'
        ..version = 'v2';
      expect(await c.savePrice(regular: '150.00', sale: ''), ProductEditResult.conflict);
      expect(c.conflict!.mineRegular, '150.00');
      expect(c.conflict!.serverRegular, '200.00');
      expect(await c.overwrite(), ProductEditResult.done);
      expect(server.writes[1].version, 'v2');
      expect(server.regular, '150.00');
    });

    test('keep server drops the choice and shows the server copy', () async {
      final server = FakeProductServer()..writeFailures.add(_stale);
      final c = _controller(server);
      await c.load();
      server
        ..stock = 1
        ..version = 'v2';
      await c.saveStock(5);
      await c.keepServer();
      expect(c.conflict, isNull);
      expect(c.canRetry, isFalse);
      expect(c.stockQuantity, 1);
      expect(c.version, 'v2');
      expect(server.writes.length, 1);
    });

    test('a conflict whose re-read fails is reported as offline and can be retried', () async {
      final server = FakeProductServer()..writeFailures.add(_stale);
      final c = _controller(server);
      await c.load();
      server.loadError = Exception('offline');
      expect(await c.saveStock(5), ProductEditResult.offline);
      expect(c.canRetry, isTrue);
    });

    test('overwrite without a conflict does nothing', () async {
      final server = FakeProductServer();
      final c = _controller(server);
      await c.load();
      expect(await c.overwrite(), ProductEditResult.failed);
      expect(server.writes, isEmpty);
    });
  });
}

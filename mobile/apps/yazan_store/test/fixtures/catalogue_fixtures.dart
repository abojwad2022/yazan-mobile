import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_store/src/catalogue/catalogue_repository.dart';

/// A `/sync/catalog` record for a simple product (id 13 is the one in the cart fixture).
Map<String, dynamic> simpleRecord({int id = 13, String name = 'Carnelian ring'}) => {
      'id': id,
      'type': 'simple',
      'name': name,
      'price': '120.00',
      'regular_price': '120.00',
      'sale_price': '',
      'on_sale': false,
      'stock_status': 'instock',
      'stock': null,
      'summary': 'Yemeni agate in sterling silver.',
      'currency': 'USD',
      'version': null,
      'categories': <int>[],
      'images': <Object>[],
    };

/// A variable product the way the PUBLIC feed sends it (stock is always null, `variation_attributes`
/// carries the labels, the size "7.5" is the slug `7-5`): `variations` with the attribute map the server's
/// `get_variation_attributes(false)` gives (key without the `attribute_` prefix, value as a slug).
Map<String, dynamic> sizedRecord({int id = 21, String name = 'Aqeeq Signet'}) => {
      'id': id,
      'type': 'variable',
      'name': name,
      'price': '120.00',
      'regular_price': '',
      'sale_price': '',
      'on_sale': false,
      'stock_status': 'instock',
      'stock': null,
      'summary': '',
      'currency': 'USD',
      'version': null,
      'categories': <int>[],
      'images': <Object>[],
      'variation_attributes': [
        {
          'key': 'pa_size',
          'label': 'Size',
          'options': [
            {'value': '7', 'label': '7'},
            {'value': '7-5', 'label': '7.5'},
            {'value': '9', 'label': '9'},
          ],
        },
      ],
      'variations': [
        {
          'id': 211,
          'attributes': {'pa_size': '7'},
          'price': '120.00',
          'stock_status': 'instock',
          'stock': null,
        },
        {
          'id': 212,
          'attributes': {'pa_size': '7-5'},
          'price': '130.00',
          'stock_status': 'instock',
          'stock': null,
        },
        {
          'id': 213,
          'attributes': {'pa_size': '9'},
          'price': '130.00',
          'stock_status': 'outofstock',
          'stock': null,
        },
      ],
    };

/// A repository that "downloads" the given records on its first refresh.
CatalogueRepository catalogueOf(List<Map<String, dynamic>> records) => CatalogueRepository(
      fetch: (cursor) async =>
          DeltaPage(items: records, cursor: 'c1', hasMore: false, initial: true),
    );

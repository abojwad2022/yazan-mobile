/// One page of a delta feed (`/sync/catalog`, `/sync/orders`).
class DeltaPage {
  const DeltaPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
    required this.initial,
  });

  factory DeltaPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List || json['cursor'] is! String) {
      throw const FormatException('Malformed delta page');
    }
    return DeltaPage(
      items: [for (final i in raw) Map<String, dynamic>.from(i as Map)],
      cursor: json['cursor'] as String,
      hasMore: json['has_more'] == true,
      initial: json['initial'] == true,
    );
  }

  final List<Map<String, dynamic>> items;
  final String cursor;
  final bool hasMore;
  final bool initial;

  /// Ids the server says are gone (tombstones) — remove them from the local copy.
  List<int> get deletedIds => [
        for (final i in items)
          if (i['deleted'] == true) i['id'] as int,
      ];

  /// Live records to upsert.
  List<Map<String, dynamic>> get upserts =>
      [for (final i in items) if (i['deleted'] != true) i];
}

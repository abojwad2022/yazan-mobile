import 'package:flutter_test/flutter_test.dart';
import 'package:yazan_domain/yazan_domain.dart';
import 'package:yazan_offline_sync/yazan_offline_sync.dart';
import 'package:yazan_store/src/storage/local_data.dart';

import 'scripted_client.dart';

/// In-memory [StoreLocalData] that behaves like the durable one: feeds are kept per account and
/// feed name, and [forgetAccount] removes the signed-in account's feeds and nothing else.
class MemoryLocalData implements StoreLocalData {
  MemoryLocalData({this.recreated = false});

  @override
  final bool recreated;

  final Map<String, MemoryFeedStore> _feeds = {};

  /// The account ids [forgetAccount] was called for, in order.
  final List<String> wiped = [];

  /// Set to make [forgetAccount] fail.
  Object? wipeFailure;

  /// The cache of [feed] for [accountId], created on first use.
  MemoryFeedStore feedFor(String accountId, String feed) =>
      _feeds.putIfAbsent('$accountId/$feed', MemoryFeedStore.new);

  bool hasFeed(String accountId, String feed) => _feeds.containsKey('$accountId/$feed');

  @override
  FeedStore catalogue() => feedFor(SqlFeedStore.guestAccountId, catalogueFeedName);

  @override
  FeedStore categories() => feedFor(SqlFeedStore.guestAccountId, categoriesFeedName);

  @override
  Future<void> forgetAccount() async {
    final failure = wipeFailure;
    if (failure != null) throw failure;
    wiped.add(signedInAccountId);
    _feeds.removeWhere((key, _) => key.startsWith('$signedInAccountId/'));
  }
}

/// A [YazanStorage] that only records what it was asked, for testing [DurableLocalData].
class FakeYazanStorage extends Fake implements YazanStorage {
  FakeYazanStorage({this.recreated = false});

  @override
  final bool recreated;

  final List<String> feedCalls = [];
  final List<String> wipeCalls = [];
  final MemoryFeedStore store = MemoryFeedStore();

  @override
  FeedStore feed(String accountId, String name) {
    feedCalls.add('$accountId/$name');
    return store;
  }

  @override
  Future<void> wipe(String accountId) async => wipeCalls.add(accountId);
}

/// A client whose catalogue feed is served from [records] or fails like a missing connection.
class CatalogueClient extends ScriptedClient {
  CatalogueClient(super.t, {this.records = const [], this.offline = false});

  List<Map<String, dynamic>> records;
  bool offline;
  final List<String> cursors = [];

  /// The `sync/terms` rows served to the (public) category request.
  List<Map<String, dynamic>> categories = const [];

  @override
  Future<Map<String, dynamic>> getJson(String path,
      {Map<String, dynamic>? query, bool optionalAuth = false}) async {
    if (!path.endsWith('/sync/terms')) {
      return super.getJson(path, query: query, optionalAuth: optionalAuth);
    }
    if (offline) throw Exception('offline');
    return {'categories': categories};
  }

  @override
  Future<DeltaPage> syncCatalog({String cursor = '', int limit = 50}) async {
    cursors.add(cursor);
    if (offline) throw Exception('offline');
    return DeltaPage(items: records, cursor: 'c1', hasMore: false, initial: cursor.isEmpty);
  }
}

/// A session as the login screen would leave it in the token store.
Session testSession() =>
    Session.fromJson({'access_token': 'yzm_a', 'refresh_token': 'yzr_b', 'expires_in': 900});

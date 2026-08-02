import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/settings/settings_repository.dart';
import 'package:deepread/features/sync/retention_service.dart';
import 'package:deepread/features/sync/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

LocalArticle _local({
  required String id,
  String? renderedAt,
  String? localPath,
  bool isRead = false,
}) {
  return LocalArticle(
    id: id,
    feedId: 'feed-1',
    title: 'Title',
    downloadedAt: DateTime(2020),
    isRead: isRead,
    localPath: localPath,
    renderedAt: renderedAt,
    evicted: false,
  );
}

RemoteArticleRow _remote({
  required String id,
  String? renderedAt,
  String? storagePath,
}) {
  return RemoteArticleRow.fromRow({
    'id': id,
    'feed_id': 'feed-1',
    'title': 'Title',
    'byline': null,
    'summary': storagePath == null ? 'a summary' : null,
    'published_at': null,
    'rendered_at': renderedAt,
    'storage_path': storagePath,
  });
}

/// Raw PostgREST-shaped row, for tests that exercise `fetchReadyArticles`
/// directly (as opposed to `_remote`, which builds an already-parsed
/// `RemoteArticleRow` for `decideArticleSyncAction` tests).
Map<String, dynamic> _articleRow({
  required String id,
  required String renderedAt,
  String? storagePath,
}) {
  return {
    'id': id,
    'feed_id': 'feed-1',
    'title': 'Title $id',
    'byline': null,
    'summary': storagePath == null ? 'a summary' : null,
    'published_at': null,
    'rendered_at': renderedAt,
    'storage_path': storagePath,
  };
}

/// Builds a `fetchReadyArticles`-shaped function backed by an in-memory
/// list, mimicking the real backend's `.gt('rendered_at', since)`
/// filter + `.order('rendered_at').limit(limit)` — so pagination tests can
/// express intent as "here's the full backlog" without manually slicing
/// pages themselves.
Future<List<Map<String, dynamic>>> Function({String? since, required int limit}) _fakeBackend(
  List<Map<String, dynamic>> allRows,
) {
  return ({String? since, required int limit}) async {
    final filtered = (since == null
            ? allRows
            : allRows.where((r) => (r['rendered_at'] as String).compareTo(since) > 0))
        .toList()
      ..sort((a, b) => (a['rendered_at'] as String).compareTo(b['rendered_at'] as String));
    return filtered.take(limit).toList();
  };
}

Uint8List _fakeZip({String indexHtml = '<html></html>'}) {
  final archive = Archive();
  final data = utf8.encode(indexHtml);
  archive.addFile(ArchiveFile('index.html', data.length, data));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('decideArticleSyncAction', () {
    test('brand-new article with storage_path -> download', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'a.zip'),
        local: null,
      );
      expect(action, ArticleSyncAction.download);
    });

    test('brand-new paywalled article -> insertPaywalled', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-01-01T00:00:00Z'),
        local: null,
      );
      expect(action, ArticleSyncAction.insertPaywalled);
    });

    test('local already at remote renderedAt -> skip', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'a.zip'),
        local: _local(id: 'a', renderedAt: '2026-01-01T00:00:00Z', localPath: 'articles/a'),
      );
      expect(action, ArticleSyncAction.skip);
    });

    test('remote renderedAt newer than local -> download (re-render)', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-02-01T00:00:00Z', storagePath: 'a.zip'),
        local: _local(id: 'a', renderedAt: '2026-01-01T00:00:00Z', localPath: 'articles/a'),
      );
      expect(action, ArticleSyncAction.download);
    });

    test('legacy fully-downloaded row with no renderedAt -> backfillRenderedAt, no redownload', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'a.zip'),
        local: _local(id: 'a', localPath: 'articles/a'),
      );
      expect(action, ArticleSyncAction.backfillRenderedAt);
    });

    test('legacy paywalled row with no renderedAt, remote now has storage_path -> download (upgrade)', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'a.zip'),
        local: _local(id: 'a'),
      );
      expect(action, ArticleSyncAction.download);
    });

    test('local has renderedAt but remote renderedAt is unexpectedly null -> skip (defensive)', () {
      final action = decideArticleSyncAction(
        remote: _remote(id: 'a', storagePath: 'a.zip'),
        local: _local(id: 'a', renderedAt: '2026-01-01T00:00:00Z', localPath: 'articles/a'),
      );
      expect(action, ArticleSyncAction.skip);
    });
  });

  group('pending full fetch signal', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('hasPendingFullFetch is false before anything marks it', () async {
      expect(await hasPendingFullFetch(db), isFalse);
    });

    test('markPendingFullFetch then hasPendingFullFetch reads true', () async {
      await markPendingFullFetch(db);

      expect(await hasPendingFullFetch(db), isTrue);
    });

    test('clearPendingFullFetch resets the flag to false', () async {
      await markPendingFullFetch(db);

      await clearPendingFullFetch(db);

      expect(await hasPendingFullFetch(db), isFalse);
    });

    test('marking preserves an existing watermark', () async {
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const Value(0),
              articlesRenderedThrough: const Value('2026-06-01T00:00:00Z'),
            ),
          );

      await markPendingFullFetch(db);

      final row = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingle();
      expect(row.articlesRenderedThrough, '2026-06-01T00:00:00Z');
      expect(row.needsFullFetch, isTrue);
    });
  });

  group('syncFeedRows', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('inserts the local row and marks pendingFullFetch for a feed not seen before', () async {
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': 'Example'},
      ]);

      expect(await hasPendingFullFetch(db), isTrue);
      final stored = await (db.select(db.localFeeds)..where((f) => f.id.equals('feed-1'))).getSingle();
      expect(stored.url, 'https://example.com/feed');
      expect(stored.title, 'Example');
    });

    test('updates an already-known feed row without marking pendingFullFetch', () async {
      await db.into(db.localFeeds).insert(
            LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
          );

      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': 'New Title'},
      ]);

      expect(await hasPendingFullFetch(db), isFalse);
      final stored = await (db.select(db.localFeeds)..where((f) => f.id.equals('feed-1'))).getSingle();
      expect(stored.title, 'New Title');
    });
  });

  group('SyncService.syncArticles', () {
    late AppDatabase db;
    late Directory docsDir;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      docsDir = await Directory.systemTemp.createTemp('deepread_sync_test_');
      await db.into(db.localFeeds).insert(
            LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
          );

      TestWidgetsFlutterBinding.ensureInitialized();
      // Tests below that don't inject `recordLastSynced` fall through to the
      // real default, which resolves a SettingsRepository via
      // SharedPreferences.getInstance() — needs mock initial values or it
      // throws MissingPluginException in a test environment.
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getApplicationDocumentsDirectory' ? docsDir.path : null,
      );
    });

    tearDown(() async {
      await db.close();
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('first sync (no watermark) requests since:null and advances the watermark', () async {
      String? requestedSince = 'not called';
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSince = since;
          return [
            {
              'id': 'a',
              'feed_id': 'feed-1',
              'title': 'A',
              'byline': null,
              'summary': 'sum',
              'published_at': null,
              'rendered_at': '2026-01-01T00:00:00Z',
              'storage_path': null,
            },
          ];
        },
        downloadArticleZip: (_) async => throw StateError('should not download a paywalled article'),
      );

      await service.syncArticles();

      expect(requestedSince, isNull);
      final watermark =
          await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingle();
      expect(watermark.articlesRenderedThrough, '2026-01-01T00:00:00Z');
      final stored = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingle();
      expect(stored.summary, 'sum');
      expect(stored.localPath, isNull);
    });

    test('steady-state sync sends the stored watermark as since', () async {
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const Value(0),
              articlesRenderedThrough: const Value('2026-01-01T00:00:00Z'),
            ),
          );
      String? requestedSince;
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSince = since;
          return [];
        },
        downloadArticleZip: (_) async => throw StateError('unused'),
      );

      await service.syncArticles();

      expect(requestedSince, '2026-01-01T00:00:00Z');
    });

    test('forceFullFetch ignores an existing watermark, so a newly-subscribed '
        "feed's older back catalog isn't permanently stranded", () async {
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const Value(0),
              articlesRenderedThrough: const Value('2026-06-01T00:00:00Z'),
            ),
          );
      String? requestedSince = 'not called';
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSince = since;
          return [];
        },
        downloadArticleZip: (_) async => throw StateError('unused'),
      );

      await service.syncArticles(forceFullFetch: true);

      expect(requestedSince, isNull);
    });

    test('a pass spanning exactly 2 pages fetches twice and advances the watermark '
        'to the true max across both pages', () async {
      final allRows = [
        _articleRow(id: 'a', renderedAt: '2026-01-01T00:00:00Z'),
        _articleRow(id: 'b', renderedAt: '2026-01-02T00:00:00Z'),
        _articleRow(id: 'c', renderedAt: '2026-01-03T00:00:00Z'),
      ];
      final backend = _fakeBackend(allRows);
      var fetchCallCount = 0;
      final service = SyncService(
        db,
        pageSize: 2,
        fetchReadyArticles: ({String? since, required int limit}) async {
          fetchCallCount++;
          return backend(since: since, limit: limit);
        },
        downloadArticleZip: (_) async => throw StateError('should not download a paywalled article'),
      );

      await service.syncArticles();

      expect(fetchCallCount, 2);
      final watermark =
          await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingle();
      expect(watermark.articlesRenderedThrough, '2026-01-03T00:00:00Z');
      for (final id in ['a', 'b', 'c']) {
        final stored =
            await (db.select(db.localArticles)..where((a) => a.id.equals(id))).getSingleOrNull();
        expect(stored, isNotNull, reason: 'article $id should have synced');
      }
    });

    test('a failure on the last row of page 1 still advances the fetch cursor past it '
        'to reach page 2, but the watermark does not advance at all', () async {
      final allRows = [
        _articleRow(id: 'a', renderedAt: '2026-01-01T00:00:00Z'),
        _articleRow(id: 'b', renderedAt: '2026-01-02T00:00:00Z', storagePath: 'b.zip'),
        _articleRow(id: 'c', renderedAt: '2026-01-03T00:00:00Z'),
      ];
      final backend = _fakeBackend(allRows);
      final requestedSinceValues = <String?>[];
      final service = SyncService(
        db,
        pageSize: 2,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSinceValues.add(since);
          return backend(since: since, limit: limit);
        },
        downloadArticleZip: (storagePath) async {
          if (storagePath == 'b.zip') throw StateError('network failure');
          return _fakeZip();
        },
      );

      await expectLater(service.syncArticles(), throwsStateError);

      // Proves the fetch cursor advanced to b's rendered_at (the last
      // *fetched* row of page 1) rather than staying at a's rendered_at
      // (the watermark, which only tracks the last *successful* row) —
      // a buggy implementation that used the watermark as the next page's
      // cursor would re-fetch page 1 forever instead of reaching page 2.
      expect(requestedSinceValues, [null, '2026-01-02T00:00:00Z']);
      final storedC =
          await (db.select(db.localArticles)..where((a) => a.id.equals('c'))).getSingleOrNull();
      expect(storedC, isNotNull, reason: 'article c on page 2 should still have synced');
      final watermark =
          await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
      expect(watermark, isNull);
    });

    test('a failure on page 2 after page 1 succeeded still leaves the watermark unadvanced', () async {
      final allRows = [
        _articleRow(id: 'a', renderedAt: '2026-01-01T00:00:00Z'),
        _articleRow(id: 'b', renderedAt: '2026-01-02T00:00:00Z'),
        _articleRow(id: 'c', renderedAt: '2026-01-03T00:00:00Z', storagePath: 'c.zip'),
      ];
      final backend = _fakeBackend(allRows);
      final service = SyncService(
        db,
        pageSize: 2,
        fetchReadyArticles: ({String? since, required int limit}) => backend(since: since, limit: limit),
        downloadArticleZip: (_) async => throw StateError('network failure'),
      );

      await expectLater(service.syncArticles(), throwsStateError);

      final storedA =
          await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingleOrNull();
      expect(storedA, isNotNull, reason: 'page 1 rows should still have synced locally');
      final watermark =
          await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
      expect(watermark, isNull);
    });

    test('a page returning fewer rows than pageSize stops the loop with no extra fetch call', () async {
      var fetchCallCount = 0;
      final service = SyncService(
        db,
        pageSize: 5,
        fetchReadyArticles: ({String? since, required int limit}) async {
          fetchCallCount++;
          return [
            {
              'id': 'a',
              'feed_id': 'feed-1',
              'title': 'A',
              'byline': null,
              'summary': 'sum',
              'published_at': null,
              'rendered_at': '2026-01-01T00:00:00Z',
              'storage_path': null,
            },
          ];
        },
        downloadArticleZip: (_) async => throw StateError('should not download a paywalled article'),
      );

      await service.syncArticles();

      expect(fetchCallCount, 1);
    });

    test('watermark does not advance if a row throws mid-pass', () async {
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-01T00:00:00Z',
            'storage_path': 'a.zip',
          },
        ],
        downloadArticleZip: (_) async => throw StateError('network failure'),
      );

      // The failure is isolated internally but still surfaces at the end
      // (so callers like the background task know to retry sooner), and
      // the watermark still must not advance.
      await expectLater(service.syncArticles(), throwsStateError);

      final watermark = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
      expect(watermark, isNull);
    });

    test('one failing article does not block others in the same pass, but the failure still surfaces', () async {
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-01T00:00:00Z',
            'storage_path': 'a.zip',
          },
          {
            'id': 'b',
            'feed_id': 'feed-1',
            'title': 'B',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-02T00:00:00Z',
            'storage_path': 'b.zip',
          },
        ],
        downloadArticleZip: (storagePath) async {
          if (storagePath == 'a.zip') throw StateError('network failure');
          return _fakeZip(indexHtml: '<html>b</html>');
        },
      );

      await expectLater(service.syncArticles(), throwsStateError);

      final storedB = await (db.select(db.localArticles)..where((a) => a.id.equals('b'))).getSingle();
      expect(storedB.localPath, 'articles/b');
      expect(
        await File('${docsDir.path}/articles/b/index.html').readAsString(),
        '<html>b</html>',
      );

      final storedA = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingleOrNull();
      expect(storedA, isNull);

      // The batch had a failure (article a), so the watermark must not
      // advance even though article b succeeded.
      final watermark = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
      expect(watermark, isNull);
    });

    test('a failed re-render leaves the previous good download in place', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'a',
              feedId: 'feed-1',
              title: 'A',
              downloadedAt: DateTime.now(),
              localPath: const Value('articles/a'),
              renderedAt: const Value('2026-01-01T00:00:00Z'),
            ),
          );
      final articleDir = Directory(p.join(docsDir.path, 'articles', 'a'));
      await articleDir.create(recursive: true);
      await File(p.join(articleDir.path, 'index.html')).writeAsString('<html>v1</html>');

      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-02-01T00:00:00Z',
            'storage_path': 'a-v2.zip',
          },
        ],
        // A corrupt zip (valid EOCD signature, bogus central-directory
        // size) — ZipDecoder.decodeBytes throws partway through instead of
        // silently producing an empty archive.
        downloadArticleZip: (_) async => Uint8List.fromList(
          [0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99, 0, 0, 0],
        ),
      );

      await expectLater(service.syncArticles(), throwsA(anything));

      expect(
        await File('${docsDir.path}/articles/a/index.html').readAsString(),
        '<html>v1</html>',
      );
      final stored = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingle();
      expect(stored.renderedAt, '2026-01-01T00:00:00Z');
      expect(stored.localPath, 'articles/a');
    });

    test('paywall to full upgrade downloads and sets localPath', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'a',
              feedId: 'feed-1',
              title: 'A',
              downloadedAt: DateTime.now(),
              summary: const Value('old summary'),
            ),
          );

      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-01T00:00:00Z',
            'storage_path': 'a.zip',
          },
        ],
        downloadArticleZip: (_) async => _fakeZip(),
      );

      await service.syncArticles();

      final stored = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingle();
      expect(stored.localPath, 'articles/a');
      expect(stored.renderedAt, '2026-01-01T00:00:00Z');
    });

    test('re-render of a downloaded article redownloads and preserves isRead', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'a',
              feedId: 'feed-1',
              title: 'A',
              downloadedAt: DateTime.now(),
              localPath: const Value('articles/a'),
              isRead: const Value(true),
              renderedAt: const Value('2026-01-01T00:00:00Z'),
            ),
          );

      var downloadCalls = 0;
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-02-01T00:00:00Z',
            'storage_path': 'a-v2.zip',
          },
        ],
        downloadArticleZip: (_) async {
          downloadCalls++;
          return _fakeZip(indexHtml: '<html>v2</html>');
        },
      );

      await service.syncArticles();

      expect(downloadCalls, 1);
      final stored = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingle();
      expect(stored.isRead, isTrue);
      expect(stored.renderedAt, '2026-02-01T00:00:00Z');
      expect(
        await File('${docsDir.path}/articles/a/index.html').readAsString(),
        '<html>v2</html>',
      );
    });

    test('records last-synced time via the injected settings repository after a successful pass', () async {
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [],
        downloadArticleZip: (_) async => throw StateError('unused'),
        recordLastSynced: settings.setLastSyncedAt,
      );

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await service.syncArticles();
      final after = DateTime.now().add(const Duration(seconds: 1));

      final recorded = settings.lastSyncedAt;
      expect(recorded, isNotNull);
      expect(recorded!.isAfter(before) && recorded.isBefore(after), isTrue);
    });

    test('records last-synced time even when a row fails mid-pass', () async {
      final settings = SettingsRepository(await SharedPreferences.getInstance());
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-01T00:00:00Z',
            'storage_path': 'a.zip',
          },
        ],
        downloadArticleZip: (_) async => throw StateError('network failure'),
        recordLastSynced: settings.setLastSyncedAt,
      );

      await expectLater(service.syncArticles(), throwsStateError);

      expect(settings.lastSyncedAt, isNotNull);
    });

    test('applies the injected retention policy after a pass completes', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'old-read',
              feedId: 'feed-1',
              title: 'Old read article',
              downloadedAt: DateTime(2020, 1, 1),
              isRead: const Value(true),
              localPath: const Value('articles/old-read'),
            ),
          );
      final articleDir = Directory(p.join(docsDir.path, 'articles', 'old-read'));
      await articleDir.create(recursive: true);
      await File(p.join(articleDir.path, 'index.html')).writeAsString('<html></html>');

      final retention = RetentionService(db, articlesDir: Directory(p.join(docsDir.path, 'articles')));
      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [],
        downloadArticleZip: (_) async => throw StateError('unused'),
        applyRetentionPolicy: (_) => retention.applyAutoPolicy(expireReadAfterDays: 1),
      );

      await service.syncArticles();

      final row = await (db.select(db.localArticles)..where((a) => a.id.equals('old-read'))).getSingle();
      expect(row.evicted, isTrue);
      expect(row.localPath, isNull);
      expect(await articleDir.exists(), isFalse);
    });

    test('legacy backfill path updates renderedAt without downloading', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'a',
              feedId: 'feed-1',
              title: 'A',
              downloadedAt: DateTime.now(),
              localPath: const Value('articles/a'),
            ),
          );

      final service = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          {
            'id': 'a',
            'feed_id': 'feed-1',
            'title': 'A',
            'byline': null,
            'summary': null,
            'published_at': null,
            'rendered_at': '2026-01-01T00:00:00Z',
            'storage_path': 'a.zip',
          },
        ],
        downloadArticleZip: (_) async => throw StateError('should not redownload a legacy row'),
      );

      await service.syncArticles();

      final stored = await (db.select(db.localArticles)..where((a) => a.id.equals('a'))).getSingle();
      expect(stored.renderedAt, '2026-01-01T00:00:00Z');
      expect(stored.localPath, 'articles/a');
    });

    test('a feed first detected via syncFeedRows survives a failed forced pass and still '
        'forces a full fetch on retry, instead of being stranded once the local row exists',
        () async {
      // Clear the feed that was inserted by setUp, so we can test the
      // "first detection" scenario with a fresh feed.
      await (db.delete(db.localFeeds)..where((f) => f.id.equals('feed-1'))).go();

      // Other feeds' prior successful syncs already advanced the watermark
      // well past this (about to be newly-subscribed-elsewhere) feed's
      // already-rendered back catalog.
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(
              id: const Value(0),
              articlesRenderedThrough: const Value('2026-06-01T00:00:00Z'),
            ),
          );

      // Pass 1 — mirrors syncNow: _syncFeeds sees a feed not yet known
      // locally and marks the flag via syncFeedRows.
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': null},
      ]);
      expect(await hasPendingFullFetch(db), isTrue);

      final failingService = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async => [
          _articleRow(id: 'old-a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'old-a.zip'),
        ],
        downloadArticleZip: (_) async => throw StateError('network failure'),
      );
      // Mirrors syncNow: forceFullFetch is read from the persisted flag,
      // and clearPendingFullFetch is only reached on the line after this
      // call — which never runs here, since syncArticles throws.
      await expectLater(
        failingService.syncArticles(forceFullFetch: await hasPendingFullFetch(db)),
        throwsStateError,
      );

      // Pass 2 — the feed row now exists locally (syncFeedRows upserted it
      // in pass 1 regardless of the article download failure), so a fresh
      // "is this feed new" comparison would no longer see it as new. That
      // was the bug: the persisted flag from pass 1 must be what survives
      // here instead.
      await syncFeedRows(db, [
        {'id': 'feed-1', 'url': 'https://example.com/feed', 'title': null},
      ]);
      final pendingFullFetch = await hasPendingFullFetch(db);
      expect(pendingFullFetch, isTrue, reason: 'the failed pass must not have lost the retry signal');

      String? requestedSince = 'not called';
      final retryService = SyncService(
        db,
        fetchReadyArticles: ({String? since, required int limit}) async {
          requestedSince = since;
          return [];
        },
        downloadArticleZip: (_) async => throw StateError('unused'),
      );
      await retryService.syncArticles(forceFullFetch: pendingFullFetch);

      expect(requestedSince, isNull,
          reason: 'the back catalog must still be retried with an unwatermarked fetch, not '
              'silently scoped to the pre-existing watermark');
    });
  });
}

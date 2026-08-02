# Sync Pagination Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SyncService.syncArticles` traverse its entire matching backlog across multiple
pages instead of silently truncating at Supabase's PostgREST `max_rows` cap (1000), which today
causes the local watermark to advance past rows that were never actually fetched — permanently
stranding them.

**Architecture:** Wrap the existing single-fetch-then-process body of `syncArticles` in an outer
`while` loop, paging with `.order('rendered_at').limit(pageSize)`. Two variables are kept
distinct: `fetchCursor` (drives the next page's `since`, always advances) and `newWatermark` (the
value actually persisted, gated on zero failures across the *whole* multi-page pass).

**Tech Stack:** Flutter/Dart, `drift` (SQLite), `supabase_flutter` (PostgREST query builder),
`flutter_test`.

## Global Constraints

- Page size defaults to `1000`, matching `supabase/config.toml`'s `max_rows`.
- The `fetchReadyArticles` injectable field type changes from
  `Future<List<Map<String, dynamic>>> Function({String? since})` to
  `Future<List<Map<String, dynamic>>> Function({String? since, required int limit})` — every
  existing test closure assigned to this field must be updated to match or the file won't compile.
- Out of scope: `forceFullFetch`'s retry-signal gap (a different, separately-tracked TODO item).
  Do not touch `_syncFeeds`, `hasPendingFullFetch`, `markPendingFullFetch`,
  `clearPendingFullFetch`, or `syncNow`.
- Design reference: `docs/superpowers/specs/2026-08-02-sync-pagination-fix-design.md`.

---

### Task 1: Paginate `syncArticles` across the PostgREST row cap

**Files:**
- Modify: `mobile/lib/features/sync/sync_service.dart`
- Modify: `mobile/test/sync_service_test.dart`

**Interfaces:**
- Consumes: nothing new — this task is self-contained within `sync_service.dart` and its test.
- Produces:
  - `SyncService({..., int pageSize = 1000})` — new constructor field, `SyncService.pageSize`.
  - `fetchReadyArticles` field type becomes
    `Future<List<Map<String, dynamic>>> Function({String? since, required int limit})`.
  - Behavior: `syncArticles()` now issues as many `fetchReadyArticles` calls as needed (each
    capped at `pageSize`) until a page comes back shorter than `pageSize`, and only persists the
    watermark once the entire multi-page pass completed with zero row failures.

- [ ] **Step 1: Replace the test file with the updated version below (RED — won't compile yet)**

This updates every existing closure assigned to `fetchReadyArticles` to accept the new
`required int limit` parameter (all but the new tests ignore it), and appends four new tests
covering multi-page behavior. Every other existing test is otherwise unchanged — a single page
under `pageSize` is the same code path as before, not a special case.

Replace the full contents of `mobile/test/sync_service_test.dart` with:

```dart
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

    test('a failure on page 1 still lets page 2 get fetched, but the watermark '
        'does not advance at all', () async {
      final allRows = [
        _articleRow(id: 'a', renderedAt: '2026-01-01T00:00:00Z', storagePath: 'a.zip'),
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
        downloadArticleZip: (storagePath) async {
          if (storagePath == 'a.zip') throw StateError('network failure');
          return _fakeZip();
        },
      );

      await expectLater(service.syncArticles(), throwsStateError);

      expect(fetchCallCount, 2, reason: 'page 2 must still be fetched despite page 1 having a failure');
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
  });
}
```

- [ ] **Step 2: Run the test file and confirm it fails to compile**

Run: `cd mobile && flutter test test/sync_service_test.dart`
Expected: compile error — `pageSize` is not a named parameter of `SyncService`, and the closures'
`limit` parameter doesn't match `fetchReadyArticles`'s old signature (`{String? since}`). This
compile failure is the RED state for this change (a strongly-typed interface change can't produce
a runnable-but-failing test the way dynamically-typed code would).

- [ ] **Step 3: Replace the production file with the updated version below (GREEN)**

Replace the full contents of `mobile/lib/features/sync/sync_service.dart` with:

```dart
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';
import '../settings/settings_repository.dart';
import 'retention_service.dart';

/// A remote `articles` row as returned by the `fetchReadyArticles` query,
/// parsed out of the raw PostgREST JSON map once so downstream logic
/// doesn't repeat `as String?` casts.
class RemoteArticleRow {
  RemoteArticleRow.fromRow(Map<String, dynamic> row)
      : id = row['id'] as String,
        feedId = row['feed_id'] as String,
        title = row['title'] as String?,
        byline = row['byline'] as String?,
        summary = row['summary'] as String?,
        publishedAt = row['published_at'] as String?,
        renderedAt = row['rendered_at'] as String?,
        storagePath = row['storage_path'] as String?;

  final String id;
  final String feedId;
  final String? title;
  final String? byline;
  final String? summary;
  final String? publishedAt;
  final String? renderedAt;
  final String? storagePath;
}

/// What to do with one remote article row, given what (if anything) is
/// already stored locally for it.
enum ArticleSyncAction {
  /// Nothing downloadable yet — insert/update a summary-only row.
  insertPaywalled,

  /// Download and unzip the rendered content (new article, paywall→full
  /// upgrade, or a genuine re-render of an already-downloaded article).
  download,

  /// A pre-migration row already has this article fully downloaded but
  /// has no recorded [LocalArticle.renderedAt] to compare against. There's
  /// no reliable "did it change" signal for it, so don't redownload —
  /// just backfill the column so future passes can version-check it.
  backfillRenderedAt,

  /// Local copy is already at least as new as the remote row.
  skip,
}

/// Pure decision logic for one article, given the matching local row (or
/// null if never seen before). Kept separate from I/O so it's directly
/// unit-testable without a database or network.
ArticleSyncAction decideArticleSyncAction({
  required RemoteArticleRow remote,
  required LocalArticle? local,
}) {
  if (local == null) {
    return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
  }

  final localRenderedAt = local.renderedAt;
  if (localRenderedAt != null) {
    // Defensive: the backend always sets rendered_at on a ready article,
    // so remote.renderedAt should never be null here in practice. If it
    // somehow is, there's nothing newer to act on — skip rather than risk
    // redownloading on every pass.
    final remoteRenderedAt = remote.renderedAt;
    final remoteIsNewer =
        remoteRenderedAt != null && DateTime.parse(remoteRenderedAt).isAfter(DateTime.parse(localRenderedAt));
    if (!remoteIsNewer) return ArticleSyncAction.skip;
    return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
  }

  // local.renderedAt == null: a pre-migration row.
  if (local.localPath != null && remote.storagePath != null) {
    return ArticleSyncAction.backfillRenderedAt;
  }
  // Otherwise: still paywalled pre-migration (no reliable version to
  // compare, but nothing downloaded to lose either — fall through and
  // treat like new), or the existing paywall→full upgrade case.
  return remote.storagePath == null ? ArticleSyncAction.insertPaywalled : ArticleSyncAction.download;
}

Future<List<Map<String, dynamic>>> _defaultFetchReadyArticles({String? since, required int limit}) async {
  // RLS on `articles` already scopes this to feeds the current user is
  // subscribed to — see supabase/migrations/0001_init.sql.
  var query = AppSupabase.client
      .from('articles')
      .select('id, feed_id, title, byline, summary, published_at, rendered_at, storage_path')
      .eq('status', 'ready');
  if (since != null) query = query.gt('rendered_at', since);
  final rows = await query.order('rendered_at', ascending: true).limit(limit);
  return (rows as List).cast<Map<String, dynamic>>();
}

Future<Uint8List> _defaultDownloadArticleZip(String storagePath) {
  return AppSupabase.client.storage.from('articles').download(storagePath);
}

/// Whether this device has a pending full-catalog fetch to do, set by
/// [FeedRepository.subscribe] whenever it (re)subscribes to a feed on this
/// device. See [SyncState.needsFullFetch] for why this exists as a
/// separate signal from [SyncService]'s own newly-subscribed-elsewhere
/// detection.
Future<bool> hasPendingFullFetch(AppDatabase db) async {
  final state = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
  return state?.needsFullFetch ?? false;
}

/// Sets the pending-full-fetch signal read by [hasPendingFullFetch].
/// Preserves any existing watermark — only `needsFullFetch` is written.
Future<void> markPendingFullFetch(AppDatabase db) async {
  await db.into(db.syncState).insertOnConflictUpdate(
        const SyncStateCompanion(id: Value(0), needsFullFetch: Value(true)),
      );
}

/// Clears the pending-full-fetch signal. Called by [SyncService.syncNow]
/// only after a full fetch has completed without any row failing, so a
/// failed pass safely retries with the signal still set next time.
Future<void> clearPendingFullFetch(AppDatabase db) async {
  await (db.update(db.syncState)..where((s) => s.id.equals(0)))
      .write(const SyncStateCompanion(needsFullFetch: Value(false)));
}

Future<void> _defaultRecordLastSynced(DateTime time) async {
  final settings = await SettingsRepository.load();
  await settings.setLastSyncedAt(time);
}

Future<void> _defaultApplyRetentionPolicy(AppDatabase db) async {
  final settings = await SettingsRepository.load();
  final expireDays = settings.retentionExpireReadAfterDays;
  final capPerFeed = settings.retentionCapPerFeed;
  if (expireDays == null && capPerFeed == null) return;

  final docsDir = await getApplicationDocumentsDirectory();
  final retention = RetentionService(db, articlesDir: Directory(p.join(docsDir.path, 'articles')));
  await retention.applyAutoPolicy(expireReadAfterDays: expireDays, capPerFeed: capPerFeed);
}

/// Pulls down anything the backend worker has rendered for this user's
/// subscribed feeds: refreshes local feed metadata, then downloads and
/// unzips any newly-`ready` or newly-re-rendered articles this device
/// doesn't already have the latest copy of.
///
/// This is deliberately lightweight (a Postgres query + a few file
/// downloads) — no rendering happens on-device, which is the whole reason
/// the cloud pipeline exists in the first place. Safe to call from a
/// background fetch callback under OS time limits.
class SyncService {
  const SyncService(
    this.db, {
    this.fetchReadyArticles = _defaultFetchReadyArticles,
    this.downloadArticleZip = _defaultDownloadArticleZip,
    this.recordLastSynced = _defaultRecordLastSynced,
    this.applyRetentionPolicy = _defaultApplyRetentionPolicy,
    this.pageSize = 1000,
  });

  final AppDatabase db;
  final Future<List<Map<String, dynamic>>> Function({String? since, required int limit}) fetchReadyArticles;
  final Future<Uint8List> Function(String storagePath) downloadArticleZip;
  final Future<void> Function(DateTime time) recordLastSynced;
  final Future<void> Function(AppDatabase db) applyRetentionPolicy;

  /// Max rows requested per `fetchReadyArticles` call. Defaults to
  /// Supabase's own PostgREST `max_rows` cap (`supabase/config.toml`) so a
  /// single page request is never silently truncated below what we asked
  /// for. `syncArticles` pages through as many calls as it takes to reach
  /// a page shorter than this, so raising/lowering it only changes the
  /// number of round trips per pass, not correctness. Overridable in tests
  /// to exercise multi-page behavior without huge fixtures.
  final int pageSize;

  Future<void> syncNow() async {
    final userId = AppSupabase.client.auth.currentUser?.id;
    if (userId == null) return;

    final hasNewSubscription = await _syncFeeds(userId);
    final pendingFullFetch = await hasPendingFullFetch(db);
    // A newly-subscribed feed's already-rendered back catalog predates the
    // current watermark (this is a *shared* rendering cache — a feed's
    // articles can have been rendered long before this user subscribed),
    // so a plain `.gt('rendered_at', since)` pass would permanently skip
    // them. Fall back to a full fetch when either a subscription made on
    // another device just showed up here for the first time
    // (hasNewSubscription — caught by comparing against local feed rows),
    // or this device itself just (re)subscribed via FeedRepository.subscribe
    // (pendingFullFetch — that write happens before local feed rows can be
    // compared, so hasNewSubscription alone never catches it). The old rows
    // either pass has to re-examine all hit ArticleSyncAction.skip cheaply,
    // so this is just a network-cost trade-off, not a correctness one.
    await syncArticles(forceFullFetch: hasNewSubscription || pendingFullFetch);

    // Only clear once the full fetch above has actually completed — if it
    // threw, this line is never reached, so the signal survives for the
    // next pass to retry rather than being silently lost.
    if (pendingFullFetch) await clearPendingFullFetch(db);
  }

  /// Returns true if any feed in the response wasn't already present
  /// locally (a new subscription this pass), so [syncNow] can decide
  /// whether the article watermark is still safe to trust.
  Future<bool> _syncFeeds(String userId) async {
    final rows = await AppSupabase.client
        .from('user_feed_subscriptions')
        .select('feeds(id, url, title)')
        .eq('user_id', userId);

    final existingIds = (await db.select(db.localFeeds).get()).map((f) => f.id).toSet();
    var hasNewSubscription = false;

    for (final row in rows as List) {
      final feed = row['feeds'] as Map<String, dynamic>;
      final feedId = feed['id'] as String;
      if (!existingIds.contains(feedId)) hasNewSubscription = true;
      await db.into(db.localFeeds).insertOnConflictUpdate(
            LocalFeedsCompanion.insert(
              id: feedId,
              url: feed['url'] as String,
              title: Value(feed['title'] as String?),
            ),
          );
    }
    return hasNewSubscription;
  }

  /// Fetches and applies newly-`ready`/newly-re-rendered articles. Public
  /// (rather than the `_syncFeeds`-style private convention) so it's
  /// directly callable from tests without also exercising `_syncFeeds`'s
  /// live Supabase call — see `sync_service_test.dart`.
  ///
  /// [forceFullFetch] ignores the stored watermark for this pass (still
  /// updating it from whatever's fetched) — see the call site in
  /// [syncNow] for why a new feed subscription requires this.
  ///
  /// Pages through `fetchReadyArticles` (each call capped at [pageSize])
  /// until a page comes back shorter than [pageSize], so this traverses
  /// the entire backlog matching `since` regardless of how many rows that
  /// is — not just whatever PostgREST's own row cap would return from a
  /// single unpaginated query.
  Future<void> syncArticles({bool forceFullFetch = false}) async {
    final watermarkRow = forceFullFetch
        ? null
        : await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingleOrNull();
    final since = watermarkRow?.articlesRenderedThrough;

    // `fetchCursor` drives `since` for the *next page fetch only* and
    // always advances to the last fetched row's rendered_at, even if some
    // rows in that page failed to process below — otherwise a mid-page
    // failure would leave this pass re-fetching the same page forever
    // instead of reaching the rest of the backlog. `newWatermark` (the
    // value actually persisted, see below) is the one gated on
    // failureCount across the WHOLE multi-page pass.
    //
    // Accepted edge case: if two different articles shared the exact same
    // rendered_at (a Postgres timestamptz set once via now() at render
    // completion), one landing exactly on a page boundary could in theory
    // be skipped by the next page's `.gt('rendered_at', fetchCursor)`.
    // Not guarded against — considered practically unobservable given
    // real-world render timing, even under render_concurrency > 1 — see
    // docs/superpowers/specs/2026-08-02-sync-pagination-fix-design.md.
    String? fetchCursor = since;

    // Newest rendered_at observed this pass across every page — becomes
    // the new watermark, but only once every row across every page has
    // been handled without throwing. Each row's I/O is isolated (a bad
    // zip/network/disk failure on one article doesn't stop the rest of the
    // batch — or the rest of the backlog's pages — from syncing), but if
    // *any* row failed, the watermark must still NOT advance: the next
    // pass re-fetches the same `since` window and retries. That's safe and
    // cheap, since already-handled rows in that window will just hit
    // ArticleSyncAction.skip again on retry — don't "optimize" this into
    // per-row watermark advancement, or a failed row's rendered_at could
    // fall below the new watermark and be permanently skipped.
    String? newWatermark = since;
    var failureCount = 0;

    while (true) {
      final rawRows = await fetchReadyArticles(since: fetchCursor, limit: pageSize);
      final rows = rawRows.map(RemoteArticleRow.fromRow).toList();

      for (final remote in rows) {
        final local = await (db.select(db.localArticles)..where((a) => a.id.equals(remote.id)))
            .getSingleOrNull();

        try {
          switch (decideArticleSyncAction(remote: remote, local: local)) {
            case ArticleSyncAction.skip:
              break;
            case ArticleSyncAction.backfillRenderedAt:
              await (db.update(db.localArticles)..where((a) => a.id.equals(remote.id)))
                  .write(LocalArticlesCompanion(renderedAt: Value(remote.renderedAt)));
            case ArticleSyncAction.insertPaywalled:
              await _insertPaywalledArticle(remote);
            case ArticleSyncAction.download:
              await _downloadAndStore(remote);
          }
        } catch (e) {
          log('Failed to sync article ${remote.id}: $e', name: 'SyncService');
          failureCount++;
          continue;
        }

        final rowRenderedAt = remote.renderedAt;
        if (rowRenderedAt != null &&
            (newWatermark == null || DateTime.parse(rowRenderedAt).isAfter(DateTime.parse(newWatermark)))) {
          newWatermark = rowRenderedAt;
        }
      }

      // Advance the pagination cursor regardless of any failures above —
      // see the comment on `fetchCursor` above. The backend always sets
      // rendered_at on a ready article (same invariant
      // decideArticleSyncAction leans on), so rows.last.renderedAt is
      // reliably non-null here whenever rows is non-empty.
      if (rows.isNotEmpty) fetchCursor = rows.last.renderedAt;

      // A page shorter than pageSize means the backlog is exhausted.
      if (rows.length < pageSize) break;
    }

    if (failureCount == 0 && newWatermark != since) {
      // id must be explicit: SQLite's INTEGER PRIMARY KEY rowid-alias
      // behavior auto-assigns a new rowid whenever the column is omitted
      // from an INSERT, ignoring the column's SQL-level DEFAULT — so
      // omitting id here would silently insert a new row every sync pass
      // instead of upserting the singleton row this table reads (id=0).
      //
      // Only reached once every page in this pass processed cleanly, so
      // if the process is killed mid-pass (e.g. the background
      // WorkManager isolate hitting an OS execution time limit), this
      // line simply never runs — nothing here to corrupt. Rows already
      // downloaded stay on disk with their renderedAt already recorded
      // locally, so the next pass re-fetching from the same `since` just
      // skips them again cheaply via ArticleSyncAction.skip.
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(id: const Value(0), articlesRenderedThrough: Value(newWatermark)),
          );
    }

    // Recorded regardless of failureCount — a partially-failed pass still
    // "ran" (see the last-synced-time UI on the Settings screen), and this
    // must happen before the throw below so it's not skipped when rows fail.
    await recordLastSynced(DateTime.now());

    // Independent bookkeeping over existing local state, not tied to this
    // pass's own success — runs on every pass (manual and background).
    await applyRetentionPolicy(db);

    // Every row was attempted (isolation above), but callers still need to
    // know something went wrong: FeedListScreen's sync-button handler shows
    // this via a SnackBar, and the WorkManager background task uses it to
    // retry sooner with backoff instead of waiting the full 15-minute
    // periodic interval. Raised after the loop (and after any watermark
    // write) so it never short-circuits processing or persistence of the
    // rows that did succeed.
    if (failureCount > 0) {
      throw StateError('$failureCount article(s) failed to sync; will retry next pass');
    }
  }

  Future<void> _insertPaywalledArticle(RemoteArticleRow article) async {
    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: article.id,
            feedId: article.feedId,
            title: article.title ?? '(untitled)',
            byline: Value(article.byline),
            publishedAt: Value(_parseTimestamp(article.publishedAt)),
            downloadedAt: DateTime.now(),
            summary: Value(article.summary),
            renderedAt: Value(article.renderedAt),
          ),
        );
  }

  Future<void> _downloadAndStore(RemoteArticleRow article) async {
    final id = article.id;
    final bytes = await downloadArticleZip(article.storagePath!);

    final docsDir = await getApplicationDocumentsDirectory();
    final articleDir = Directory(p.join(docsDir.path, 'articles', id));

    // Unzip into a staging dir first, leaving any existing (working) render
    // in `articleDir` untouched until the new one is fully extracted. A
    // corrupt/truncated zip then throws without deleting a previously-good
    // article — it just leaves this pass's staging dir to be overwritten by
    // the next attempt, instead of the reader opening to an empty folder.
    final stagingDir = Directory(p.join(docsDir.path, 'articles', '$id.staging'));
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);
    await _unzipInto(bytes, stagingDir);

    // Only now, with the new render fully on disk, swap it in. Clear out a
    // previous render's files first so a re-render with fewer images than
    // the old one doesn't leave orphaned stale files.
    if (await articleDir.exists()) await articleDir.delete(recursive: true);
    await stagingDir.rename(articleDir.path);

    await db.into(db.localArticles).insertOnConflictUpdate(
          LocalArticlesCompanion.insert(
            id: id,
            feedId: article.feedId,
            title: article.title ?? '(untitled)',
            byline: Value(article.byline),
            publishedAt: Value(_parseTimestamp(article.publishedAt)),
            downloadedAt: DateTime.now(),
            localPath: Value(p.join('articles', id)),
            renderedAt: Value(article.renderedAt),
          ),
        );
  }

  Future<void> _unzipInto(Uint8List zipBytes, Directory targetDir) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (!file.isFile) continue;
      final outFile = File(p.join(targetDir.path, file.name));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    }
  }

  DateTime? _parseTimestamp(String? iso) => iso == null ? null : DateTime.tryParse(iso);
}
```

- [ ] **Step 4: Run the sync test file and confirm everything passes**

Run: `cd mobile && flutter test test/sync_service_test.dart`
Expected: PASS — all 12 original tests plus the 4 new pagination tests (16 total in the
`SyncService.syncArticles` group), plus the unrelated `decideArticleSyncAction` and
`pending full fetch signal` groups untouched.

- [ ] **Step 5: Run the full mobile test suite and analyzer to confirm no regressions elsewhere**

Run: `cd mobile && flutter test && flutter analyze`
Expected: PASS with no new analyzer warnings. (Equivalent to `make mobile-test` /
`make mobile-analyze` from the repo root.)

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/features/sync/sync_service.dart mobile/test/sync_service_test.dart
git commit -m "Paginate syncArticles across the PostgREST row cap

A single-page fetch silently truncated at Supabase's max_rows (1000),
and the watermark advanced past whatever didn't fit, permanently
stranding it. syncArticles now pages through fetchReadyArticles until a
page comes back shorter than pageSize, and only commits the watermark
once the entire multi-page pass completed with zero row failures."
```

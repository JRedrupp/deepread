import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/sync/sync_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
        fetchReadyArticles: ({since}) async {
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
        fetchReadyArticles: ({since}) async {
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
        fetchReadyArticles: ({since}) async {
          requestedSince = since;
          return [];
        },
        downloadArticleZip: (_) async => throw StateError('unused'),
      );

      await service.syncArticles(forceFullFetch: true);

      expect(requestedSince, isNull);
    });

    test('watermark does not advance if a row throws mid-pass', () async {
      final service = SyncService(
        db,
        fetchReadyArticles: ({since}) async => [
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
        fetchReadyArticles: ({since}) async => [
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
        fetchReadyArticles: ({since}) async => [
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
        fetchReadyArticles: ({since}) async => [
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
        fetchReadyArticles: ({since}) async => [
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
        fetchReadyArticles: ({since}) async => [
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

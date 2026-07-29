import 'dart:io';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/sync/retention_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory articlesDir;
  late RetentionService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    articlesDir = await Directory.systemTemp.createTemp('deepread_retention_test_');
    service = RetentionService(db, articlesDir: articlesDir);

    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
        );
  });

  tearDown(() async {
    await db.close();
    if (await articlesDir.exists()) await articlesDir.delete(recursive: true);
  });

  Future<void> seedDownloaded(
    String id, {
    bool isRead = false,
    required DateTime downloadedAt,
    DateTime? publishedAt,
    String feedId = 'feed-1',
  }) async {
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: id,
            feedId: feedId,
            title: 'Title $id',
            downloadedAt: downloadedAt,
            publishedAt: Value(publishedAt),
            isRead: Value(isRead),
            localPath: Value('articles/$id'),
            renderedAt: const Value('2026-01-01T00:00:00Z'),
          ),
        );
    final dir = Directory(p.join(articlesDir.path, id));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'index.html')).writeAsString('<html></html>');
  }

  Future<LocalArticle> reload(String id) =>
      (db.select(db.localArticles)..where((a) => a.id.equals(id))).getSingle();

  group('applyAutoPolicy expireReadAfterDays', () {
    test('evicts a read article older than the threshold', () async {
      await seedDownloaded('a', isRead: true, downloadedAt: DateTime(2026, 1, 1));

      await service.applyAutoPolicy(expireReadAfterDays: 30, now: DateTime(2026, 7, 1));

      final row = await reload('a');
      expect(row.localPath, isNull);
      expect(row.evicted, isTrue);
      expect(row.renderedAt, '2026-01-01T00:00:00Z');
      expect(await Directory(p.join(articlesDir.path, 'a')).exists(), isFalse);
    });

    test('does not evict an unread article, no matter how old', () async {
      await seedDownloaded('a', isRead: false, downloadedAt: DateTime(2026, 1, 1));

      await service.applyAutoPolicy(expireReadAfterDays: 30, now: DateTime(2026, 7, 1));

      final row = await reload('a');
      expect(row.localPath, isNotNull);
      expect(row.evicted, isFalse);
    });

    test('does not evict a read article younger than the threshold', () async {
      await seedDownloaded('a', isRead: true, downloadedAt: DateTime(2026, 6, 20));

      await service.applyAutoPolicy(expireReadAfterDays: 30, now: DateTime(2026, 7, 1));

      final row = await reload('a');
      expect(row.localPath, isNotNull);
      expect(row.evicted, isFalse);
    });

    test('does nothing when expireReadAfterDays is null', () async {
      await seedDownloaded('a', isRead: true, downloadedAt: DateTime(2020, 1, 1));

      await service.applyAutoPolicy(now: DateTime(2026, 7, 1));

      final row = await reload('a');
      expect(row.localPath, isNotNull);
    });
  });

  group('applyAutoPolicy capPerFeed', () {
    test('evicts the oldest articles in a feed beyond the cap', () async {
      await seedDownloaded('a', downloadedAt: DateTime(2026, 1, 1), publishedAt: DateTime(2026, 1, 1));
      await seedDownloaded('b', downloadedAt: DateTime(2026, 2, 1), publishedAt: DateTime(2026, 2, 1));
      await seedDownloaded('c', downloadedAt: DateTime(2026, 3, 1), publishedAt: DateTime(2026, 3, 1));

      await service.applyAutoPolicy(capPerFeed: 2);

      expect((await reload('a')).evicted, isTrue);
      expect((await reload('b')).evicted, isFalse);
      expect((await reload('c')).evicted, isFalse);
    });

    test('does not evict anything when a feed is at or under the cap', () async {
      await seedDownloaded('a', downloadedAt: DateTime(2026, 1, 1), publishedAt: DateTime(2026, 1, 1));
      await seedDownloaded('b', downloadedAt: DateTime(2026, 2, 1), publishedAt: DateTime(2026, 2, 1));

      await service.applyAutoPolicy(capPerFeed: 2);

      expect((await reload('a')).evicted, isFalse);
      expect((await reload('b')).evicted, isFalse);
    });

    test('caps are tracked independently per feed', () async {
      await db.into(db.localFeeds).insert(
            LocalFeedsCompanion.insert(id: 'feed-2', url: 'https://example.com/other-feed'),
          );
      await seedDownloaded('a', downloadedAt: DateTime(2026, 1, 1), publishedAt: DateTime(2026, 1, 1));
      await seedDownloaded('b', downloadedAt: DateTime(2026, 2, 1), publishedAt: DateTime(2026, 2, 1));
      await seedDownloaded('x', feedId: 'feed-2', downloadedAt: DateTime(2026, 1, 1), publishedAt: DateTime(2026, 1, 1));

      await service.applyAutoPolicy(capPerFeed: 1);

      expect((await reload('a')).evicted, isTrue);
      expect((await reload('b')).evicted, isFalse);
      expect((await reload('x')).evicted, isFalse);
    });
  });

  test('applyAutoPolicy skips rows already evicted', () async {
    await seedDownloaded('a', isRead: true, downloadedAt: DateTime(2020, 1, 1));
    await service.applyAutoPolicy(expireReadAfterDays: 1, now: DateTime(2026, 7, 1));
    expect((await reload('a')).evicted, isTrue);

    // Running again must not throw (e.g. trying to delete an already-gone
    // directory) and must leave the row as-is.
    await service.applyAutoPolicy(expireReadAfterDays: 1, now: DateTime(2026, 7, 2));
    expect((await reload('a')).evicted, isTrue);
  });

  group('clearAllDownloaded', () {
    test('evicts every downloaded article', () async {
      await seedDownloaded('a', downloadedAt: DateTime(2026, 1, 1));
      await seedDownloaded('b', downloadedAt: DateTime(2026, 1, 1));

      await service.clearAllDownloaded();

      expect((await reload('a')).evicted, isTrue);
      expect((await reload('b')).evicted, isTrue);
    });

    test('leaves paywalled (never-downloaded) rows untouched', () async {
      await db.into(db.localArticles).insert(
            LocalArticlesCompanion.insert(
              id: 'paywalled',
              feedId: 'feed-1',
              title: 'Paywalled',
              downloadedAt: DateTime(2026, 1, 1),
              summary: const Value('a summary'),
            ),
          );

      await service.clearAllDownloaded();

      final row = await reload('paywalled');
      expect(row.evicted, isFalse);
      expect(row.summary, 'a summary');
    });
  });

  group('computeStorageBytes', () {
    test('sums file sizes under the articles directory', () async {
      await seedDownloaded('a', downloadedAt: DateTime(2026, 1, 1));
      await seedDownloaded('b', downloadedAt: DateTime(2026, 1, 1));

      final bytes = await service.computeStorageBytes();

      // Each seeded article writes one 'index.html' with '<html></html>' (13 bytes).
      expect(bytes, 26);
    });

    test('is zero when the directory does not exist', () async {
      await articlesDir.delete(recursive: true);

      expect(await service.computeStorageBytes(), 0);
    });
  });
}

import 'dart:io';

import 'package:deepread/data/local/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('upgrading from schema v1 recreates local_articles instead of crashing', () async {
    final tempDir = await Directory.systemTemp.createTemp('deepread_migration_test_');
    final dbFile = File(p.join(tempDir.path, 'v1.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // Seed a v1 database on disk: local_path NOT NULL, no summary column.
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE local_feeds (
        id TEXT NOT NULL PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE local_articles (
        id TEXT NOT NULL PRIMARY KEY,
        feed_id TEXT NOT NULL REFERENCES local_feeds (id),
        title TEXT NOT NULL,
        byline TEXT,
        published_at INTEGER,
        downloaded_at INTEGER NOT NULL,
        local_path TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute("INSERT INTO local_feeds (id, url) VALUES ('feed-1', 'https://example.com/feed')");
    raw.execute('''
      INSERT INTO local_articles (id, feed_id, title, downloaded_at, local_path)
      VALUES ('article-old', 'feed-1', 'Old article', 0, 'articles/article-old')
    ''');
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Any query forces drift's ensureOpen(), which runs onUpgrade.
    final rowsAfterUpgrade = await db.select(db.localArticles).get();
    expect(rowsAfterUpgrade, isEmpty);

    // v1->v3 must also leave sync_state present (created unconditionally
    // alongside the localArticles recreate) and localArticles renderedAt-shaped.
    final syncStateRows = await db.select(db.syncState).get();
    expect(syncStateRows, isEmpty);

    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-new',
            feedId: 'feed-1',
            title: 'New paywalled article',
            downloadedAt: DateTime.now(),
            summary: const Value('a summary'),
            renderedAt: const Value('2026-07-27T00:00:00.000000+00:00'),
          ),
        );

    final row =
        await (db.select(db.localArticles)..where((a) => a.id.equals('article-new'))).getSingle();
    expect(row.localPath, isNull);
    expect(row.summary, 'a summary');
    expect(row.renderedAt, '2026-07-27T00:00:00.000000+00:00');
  });

  test('upgrading from schema v2 adds renderedAt column and sync_state table', () async {
    final tempDir = await Directory.systemTemp.createTemp('deepread_migration_test_');
    final dbFile = File(p.join(tempDir.path, 'v2.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // Seed a v2 database on disk: local_path nullable, summary present,
    // no rendered_at column, no sync_state table.
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE local_feeds (
        id TEXT NOT NULL PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE local_articles (
        id TEXT NOT NULL PRIMARY KEY,
        feed_id TEXT NOT NULL REFERENCES local_feeds (id),
        title TEXT NOT NULL,
        byline TEXT,
        published_at INTEGER,
        downloaded_at INTEGER NOT NULL,
        local_path TEXT,
        summary TEXT,
        is_read INTEGER NOT NULL DEFAULT 0
      );
    ''');
    raw.execute("INSERT INTO local_feeds (id, url) VALUES ('feed-1', 'https://example.com/feed')");
    raw.execute('''
      INSERT INTO local_articles (id, feed_id, title, downloaded_at, local_path)
      VALUES ('article-old', 'feed-1', 'Old article', 0, 'articles/article-old')
    ''');
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Existing row must survive the addColumn migration, with renderedAt
    // reading as null since it didn't exist pre-upgrade.
    final row =
        await (db.select(db.localArticles)..where((a) => a.id.equals('article-old'))).getSingle();
    expect(row.localPath, 'articles/article-old');
    expect(row.renderedAt, isNull);

    // sync_state must now exist (created unconditionally on any from<3 upgrade).
    final syncStateRows = await db.select(db.syncState).get();
    expect(syncStateRows, isEmpty);
  });

  test('upgrading from schema v3 adds sync_state.needs_full_fetch, defaulting to false', () async {
    final tempDir = await Directory.systemTemp.createTemp('deepread_migration_test_');
    final dbFile = File(p.join(tempDir.path, 'v3.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // Seed a v3 database on disk: sync_state exists, but with no
    // needs_full_fetch column yet.
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE local_feeds (
        id TEXT NOT NULL PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE local_articles (
        id TEXT NOT NULL PRIMARY KEY,
        feed_id TEXT NOT NULL REFERENCES local_feeds (id),
        title TEXT NOT NULL,
        byline TEXT,
        published_at INTEGER,
        downloaded_at INTEGER NOT NULL,
        local_path TEXT,
        summary TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        rendered_at TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE sync_state (
        id INTEGER NOT NULL PRIMARY KEY DEFAULT 0,
        articles_rendered_through TEXT
      );
    ''');
    raw.execute(
      "INSERT INTO sync_state (id, articles_rendered_through) VALUES (0, '2026-07-27T00:00:00Z')",
    );
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final row = await (db.select(db.syncState)..where((s) => s.id.equals(0))).getSingle();
    expect(row.articlesRenderedThrough, '2026-07-27T00:00:00Z');
    expect(row.needsFullFetch, isFalse);
  });

  test('upgrading from schema v3 adds the evicted column, defaulting to false', () async {
    final tempDir = await Directory.systemTemp.createTemp('deepread_migration_test_');
    final dbFile = File(p.join(tempDir.path, 'v3.sqlite'));
    addTearDown(() => tempDir.delete(recursive: true));

    // Seed a v3 database on disk: renderedAt present, sync_state present,
    // no evicted column yet.
    final raw = sqlite3.sqlite3.open(dbFile.path);
    raw.execute('''
      CREATE TABLE local_feeds (
        id TEXT NOT NULL PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE local_articles (
        id TEXT NOT NULL PRIMARY KEY,
        feed_id TEXT NOT NULL REFERENCES local_feeds (id),
        title TEXT NOT NULL,
        byline TEXT,
        published_at INTEGER,
        downloaded_at INTEGER NOT NULL,
        local_path TEXT,
        summary TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        rendered_at TEXT
      );
    ''');
    raw.execute('''
      CREATE TABLE sync_state (
        id INTEGER NOT NULL DEFAULT 0 PRIMARY KEY,
        articles_rendered_through TEXT
      );
    ''');
    raw.execute("INSERT INTO local_feeds (id, url) VALUES ('feed-1', 'https://example.com/feed')");
    raw.execute('''
      INSERT INTO local_articles (id, feed_id, title, downloaded_at, local_path, rendered_at)
      VALUES ('article-old', 'feed-1', 'Old article', 0, 'articles/article-old', '2026-01-01T00:00:00Z')
    ''');
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    addTearDown(db.close);

    final row =
        await (db.select(db.localArticles)..where((a) => a.id.equals('article-old'))).getSingle();
    expect(row.localPath, 'articles/article-old');
    expect(row.renderedAt, '2026-01-01T00:00:00Z');
    expect(row.evicted, isFalse);
  });
}

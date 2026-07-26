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

    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-new',
            feedId: 'feed-1',
            title: 'New paywalled article',
            downloadedAt: DateTime.now(),
            summary: const Value('a summary'),
          ),
        );

    final row =
        await (db.select(db.localArticles)..where((a) => a.id.equals('article-new'))).getSingle();
    expect(row.localPath, isNull);
    expect(row.summary, 'a summary');
  });
}

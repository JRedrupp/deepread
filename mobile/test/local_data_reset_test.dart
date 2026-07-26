import 'dart:io';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/auth/local_data_reset.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('deepread_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('deletes localFeeds/localArticles rows and the articles dir, including nested content', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Some article',
            downloadedAt: DateTime.now(),
            localPath: const Value('articles/article-1'),
          ),
        );

    final nestedDir = Directory(p.join(tempDir.path, 'article-1', 'nested'));
    await nestedDir.create(recursive: true);
    await File(p.join(tempDir.path, 'article-1', 'index.html')).writeAsString('<html></html>');
    await File(p.join(nestedDir.path, 'image.png')).writeAsBytes([0]);

    await resetLocalData(db: db, articlesDir: tempDir);

    expect(await db.select(db.localFeeds).get(), isEmpty);
    expect(await db.select(db.localArticles).get(), isEmpty);
    expect(await tempDir.exists(), isFalse);
  });

  test('is a no-op on the directory when it does not already exist', () async {
    await tempDir.delete();

    await resetLocalData(db: db, articlesDir: tempDir);

    expect(await db.select(db.localFeeds).get(), isEmpty);
  });
}

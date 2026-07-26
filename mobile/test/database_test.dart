import 'package:deepread/data/local/database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('stores a paywalled article with no localPath and a summary', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Paywalled article',
            downloadedAt: DateTime.now(),
            summary: const Value('An RSS-provided summary.'),
          ),
        );

    final row = await (db.select(db.localArticles)..where((a) => a.id.equals('article-1'))).getSingle();

    expect(row.localPath, isNull);
    expect(row.summary, 'An RSS-provided summary.');
  });
}

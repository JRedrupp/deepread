import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Mirrors the subset of the backend's `feeds` table this device cares
/// about, plus the user's subscription to it. Full feed/article metadata
/// lives in Supabase; this is the offline-first local cache the UI reads.
class LocalFeeds extends Table {
  TextColumn get id => text()(); // Supabase feed id (uuid)
  TextColumn get url => text()();
  TextColumn get title => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A downloaded, offline-ready article. Only rows that have actually been
/// unzipped onto this device belong here — this is not a mirror of every
/// remote `articles` row, just the ones this device has fetched.
class LocalArticles extends Table {
  TextColumn get id => text()(); // Supabase article id (uuid)
  TextColumn get feedId => text().references(LocalFeeds, #id)();
  TextColumn get title => text()();
  TextColumn get byline => text().nullable()();
  DateTimeColumn get publishedAt => dateTime().nullable()();
  DateTimeColumn get downloadedAt => dateTime()();

  /// Path (relative to app documents dir) to the unzipped folder
  /// containing index.html + images for this article.
  TextColumn get localPath => text()();

  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [LocalFeeds, LocalArticles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'deepread.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

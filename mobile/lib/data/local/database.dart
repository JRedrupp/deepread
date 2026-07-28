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
  /// containing index.html + images for this article. Null means this
  /// article is paywalled — no offline HTML was rendered, only [summary].
  TextColumn get localPath => text().nullable()();

  /// RSS-provided summary, used as the only offline-readable content for
  /// paywalled articles (where [localPath] is null).
  TextColumn get summary => text().nullable()();

  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  /// Verbatim copy of the remote `articles.rendered_at` value (an
  /// ISO-8601 string, exactly as PostgREST returned it) as of when this
  /// row's content was last fetched/verified. Null for rows downloaded
  /// before this column existed. Stored as text, not [DateTimeColumn]:
  /// this database has no `storeDateTimeAsText` option, so a
  /// [DateTimeColumn] round-trips through unix-*seconds*, which would
  /// truncate Supabase's microsecond-precision timestamps and make every
  /// row compare as "newer than local" forever.
  TextColumn get renderedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single-row table (always id=0) tracking sync progress: the max remote
/// `articles.rendered_at` observed across every successfully-completed
/// sync pass, used so later passes only fetch newly-ready/re-rendered
/// rows instead of the full `ready` set every time.
class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();

  /// Verbatim ISO-8601 string of the newest `rendered_at` seen so far, or
  /// null before the first successful sync.
  TextColumn get articlesRenderedThrough => text().nullable()();

  /// Set by [FeedRepository.subscribe] whenever this device (re)subscribes
  /// to a feed, since that write happens synchronously before the next
  /// sync pass — which means the feed is already present in [LocalFeeds]
  /// by the time [SyncService]'s own "is this a new subscription" check
  /// runs, so that check alone would never catch it. Consumed and cleared
  /// by [SyncService.syncNow] once a full-catalog fetch has completed.
  BoolColumn get needsFullFetch => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [LocalFeeds, LocalArticles, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // localPath became nullable and summary was added; SQLite can't
            // drop a NOT NULL constraint in place, and this is a rebuildable
            // offline cache, so just recreate the table and let the next
            // sync repopulate it.
            await m.deleteTable(localArticles.actualTableName);
            await m.createTable(localArticles);
            // createTable builds from the current Dart definition, so this
            // table is already renderedAt-shaped — don't also addColumn.
          } else if (from < 3) {
            // Unlike the v1->v2 change, this is a new nullable column with
            // no default, which SQLite supports via ALTER TABLE ADD COLUMN
            // directly — no need to wipe every user's downloaded library.
            await m.addColumn(localArticles, localArticles.renderedAt);
          }
          if (from < 3) {
            // Needed on both the from<2 and from<3 paths above. createTable
            // builds from the current Dart definition, so this table is
            // already needsFullFetch-shaped — don't also addColumn below.
            await m.createTable(syncState);
          } else if (from < 4) {
            // New non-null-with-default column — plain ALTER TABLE ADD
            // COLUMN, no data migration needed.
            await m.addColumn(syncState, syncState.needsFullFetch);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'deepread.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

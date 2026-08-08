# Combined All-Articles View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a combined "all articles" view spanning every subscribed feed, reachable via a new
bottom-navigation shell (`Feeds` | `All Articles`), so the user doesn't have to open each feed
individually to see what's new.

**Architecture:** A new `HomeShell` widget becomes the app's home screen, absorbing the
sync/sign-out/add-feed state that used to live on `FeedListScreen` (now a slimmed-down, body-only
tab). A new `AllArticlesScreen` tab is backed by a drift join query (`LocalArticles` ⋈
`LocalFeeds`) exposed as an injectable `Stream<List<ArticleWithFeed>>`. Both tabs' article rows
share one extracted `ArticleListTile` widget, parameterized by an optional feed-name badge.

**Tech Stack:** Flutter/Dart, `drift` (SQLite), `flutter_test`.

## Global Constraints

- Design reference: `docs/superpowers/specs/2026-08-03-all-articles-view-design.md`.
- Flat, chronological article order in the combined view — no grouping/sectioning by feed.
- Feed-name badge is a plain bracketed monospace tag (`StatusTag`), not a Material `Chip`, and is
  **not tappable**.
- Bottom nav bar must not use Material 3's default pill-indicator look: flat background, 1px top
  hairline border, accent-teal (not a filled indicator) for the active tab.
- No pagination/lazy-loading anywhere in this feature.
- No filter-by-specific-feed within the combined view.
- Every existing test that isn't explicitly called out as moving/changing below must still pass
  unmodified.

---

### Task 1: Joined article+feed query

**Files:**
- Create: `mobile/lib/data/local/article_with_feed.dart`
- Test: `mobile/test/article_with_feed_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `LocalFeeds`, `LocalArticles` (all existing, `mobile/lib/data/local/database.dart`).
- Produces:
  - `typedef ArticleWithFeed = ({LocalArticle article, String feedDisplayName})`
  - `extension AllArticlesQuery on AppDatabase { Stream<List<ArticleWithFeed>> watchAllArticlesWithFeed() }`

- [ ] **Step 1: Write the failing test**

Create `mobile/test/article_with_feed_test.dart`:

```dart
import 'package:deepread/data/local/article_with_feed.dart';
import 'package:deepread/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('joins each article with its feed\'s title', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(
            id: 'feed-1',
            url: 'https://example.com/feed',
            title: const Value('The Verge'),
          ),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Some article',
            downloadedAt: DateTime.now(),
          ),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows, hasLength(1));
    expect(rows.single.article.id, 'article-1');
    expect(rows.single.feedDisplayName, 'The Verge');
  });

  test('falls back to the feed url when title is null', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/feed'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(
            id: 'article-1',
            feedId: 'feed-1',
            title: 'Some article',
            downloadedAt: DateTime.now(),
          ),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows.single.feedDisplayName, 'https://example.com/feed');
  });

  test('includes articles from every feed, not just one', () async {
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-1', url: 'https://example.com/a'),
        );
    await db.into(db.localFeeds).insert(
          LocalFeedsCompanion.insert(id: 'feed-2', url: 'https://example.com/b'),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(id: 'a1', feedId: 'feed-1', title: 'A1', downloadedAt: DateTime.now()),
        );
    await db.into(db.localArticles).insert(
          LocalArticlesCompanion.insert(id: 'b1', feedId: 'feed-2', title: 'B1', downloadedAt: DateTime.now()),
        );

    final rows = await db.watchAllArticlesWithFeed().first;

    expect(rows.map((r) => r.article.id).toSet(), {'a1', 'b1'});
  });
}
```

Note: `db.watchAllArticlesWithFeed().first` inside a plain `test()` body (not `testWidgets`) is the
documented-safe drift `.watch()` pattern — see TECH_DEBT.md's note on drift streams inside
`testWidgets` fake-async zones. This file never uses `testWidgets`, so it's unaffected by that
constraint.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/article_with_feed_test.dart`
Expected: FAIL — `package:deepread/data/local/article_with_feed.dart` doesn't exist yet (import error).

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/data/local/article_with_feed.dart`:

```dart
import 'package:drift/drift.dart';

import 'database.dart';

/// One [LocalArticle] plus the display name of the feed it belongs to, for
/// the combined all-articles view — where the per-feed context an
/// `ArticleListScreen` gets for free (its own AppBar title) has to be
/// carried on each row instead.
typedef ArticleWithFeed = ({LocalArticle article, String feedDisplayName});

extension AllArticlesQuery on AppDatabase {
  /// Every downloaded article across every subscribed feed, joined against
  /// [LocalFeeds] for its display name (`title ?? url`, the same fallback
  /// `FeedListScreen` already uses) — a plain SQL join, not a denormalized
  /// column, so a later feed rename never needs a backfill pass.
  Stream<List<ArticleWithFeed>> watchAllArticlesWithFeed() {
    final query = select(localArticles).join([
      innerJoin(localFeeds, localFeeds.id.equalsExp(localArticles.feedId)),
    ]);
    return query.watch().map(
          (rows) => rows.map((row) {
            final article = row.readTable(localArticles);
            final feed = row.readTable(localFeeds);
            return (article: article, feedDisplayName: feed.title ?? feed.url);
          }).toList(),
        );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/article_with_feed_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/data/local/article_with_feed.dart mobile/test/article_with_feed_test.dart
git commit -m "Add joined article+feed query for the combined all-articles view"
```

---

### Task 2: Extract the shared article card widget

**Files:**
- Create: `mobile/lib/features/articles/article_list_tile.dart`
- Test: `mobile/test/article_list_tile_test.dart`
- Modify: `mobile/lib/features/articles/article_list_screen.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `LocalArticle` (existing), `StatusTag`/`AppTheme.metadataStyle`
  (existing, `mobile/lib/theme/app_theme.dart`), `ArticleReaderScreen` (existing).
- Produces: `ArticleListTile({required AppDatabase db, required LocalArticle article, String? feedLabel})`
  — a `StatelessWidget`. `feedLabel == null` omits the feed badge entirely.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/article_list_tile_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/article_list_tile.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  LocalArticle article() => LocalArticle(
        id: 'article-1',
        feedId: 'feed-1',
        title: 'Some article',
        downloadedAt: DateTime.now(),
        isRead: true,
        localPath: 'articles/article-1',
        evicted: false,
      );

  testWidgets('shows a bracketed feed label when feedLabel is provided', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArticleListTile(db: db, article: article(), feedLabel: 'The Verge'),
        ),
      ),
    );

    expect(find.text('[The Verge]'), findsOneWidget);
  });

  testWidgets('omits the feed label entirely when feedLabel is null', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArticleListTile(db: db, article: article()),
        ),
      ),
    );

    // article() is read, downloaded, not evicted — no NEW/SUMMARY ONLY/
    // REMOVED tags either, so no bracketed text at all should render.
    expect(find.textContaining('['), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/article_list_tile_test.dart`
Expected: FAIL — `package:deepread/features/articles/article_list_tile.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/features/articles/article_list_tile.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../theme/app_theme.dart';
import 'article_reader_screen.dart';

/// One article's card body, shared between `ArticleListScreen` (a single
/// feed, so the feed is already implied by that screen's own AppBar title)
/// and the combined all-articles view (many feeds, so each row needs its
/// own [feedLabel] to say which one it came from).
class ArticleListTile extends StatelessWidget {
  const ArticleListTile({super.key, required this.db, required this.article, this.feedLabel});

  final AppDatabase db;
  final LocalArticle article;

  /// Feed display name to show ahead of the status tags, or null to omit
  /// it (the per-feed screen doesn't need it).
  final String? feedLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(article.title),
        subtitle: Row(
          children: [
            if (feedLabel != null) StatusTag(feedLabel!, color: AppTheme.textSecondary),
            if (feedLabel != null) const SizedBox(width: 8),
            if (!article.isRead) const StatusTag('NEW'),
            if (!article.isRead) const SizedBox(width: 8),
            if (article.localPath == null) StatusTag(article.evicted ? 'REMOVED' : 'SUMMARY ONLY'),
            if (article.localPath == null) const SizedBox(width: 8),
            Text(
              article.publishedAt?.toIso8601String().split('T').first ?? '',
              style: AppTheme.metadataStyle(context),
            ),
          ],
        ),
        onTap: () async {
          await (db.update(db.localArticles)..where((a) => a.id.equals(article.id)))
              .write(const LocalArticlesCompanion(isRead: Value(true)));
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArticleReaderScreen(article: article),
              ),
            );
          }
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/article_list_tile_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Update `ArticleListScreen` to use the extracted widget**

Replace the full contents of `mobile/lib/features/articles/article_list_screen.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import 'article_list_tile.dart';

enum _SortOrder { newestFirst, oldestFirst }

class ArticleListScreen extends StatefulWidget {
  const ArticleListScreen({super.key, required this.db, required this.feed, this.articlesStream});

  final AppDatabase db;
  final LocalFeed feed;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — drift's reactive query streams don't reliably
  /// deliver events when subscribed to directly inside a testWidgets
  /// fake-async zone.
  final Stream<List<LocalArticle>>? articlesStream;

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen> {
  late final Stream<List<LocalArticle>> _articlesStream;

  _SortOrder _sortOrder = _SortOrder.newestFirst;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _articlesStream = widget.articlesStream ??
        (widget.db.select(widget.db.localArticles)..where((a) => a.feedId.equals(widget.feed.id))).watch();
  }

  List<LocalArticle> _applySortAndFilter(List<LocalArticle> articles) {
    var result = _unreadOnly ? articles.where((a) => !a.isRead).toList() : List.of(articles);
    result.sort((a, b) {
      final aDate = a.publishedAt ?? a.downloadedAt;
      final bDate = b.publishedAt ?? b.downloadedAt;
      return _sortOrder == _SortOrder.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.title ?? widget.feed.url),
        actions: [
          IconButton(
            icon: Icon(_unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
            tooltip: _unreadOnly ? 'Showing unread only' : 'Show all',
            onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
          ),
          PopupMenuButton<_SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sortOrder,
            onSelected: (order) => setState(() => _sortOrder = order),
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortOrder.newestFirst, child: Text('Newest first')),
              PopupMenuItem(value: _SortOrder.oldestFirst, child: Text('Oldest first')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<LocalArticle>>(
        stream: _articlesStream,
        builder: (context, snapshot) {
          final articles = _applySortAndFilter(snapshot.data ?? const []);
          if (articles.isEmpty) {
            return Center(
              child: Text(
                _unreadOnly ? 'No unread articles.' : 'No articles downloaded yet.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: articles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return ArticleListTile(db: widget.db, article: articles[index]);
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Run the existing article-list test and the new tile test together to confirm no regression**

Run: `cd mobile && flutter test test/article_list_screen_test.dart test/article_list_tile_test.dart`
Expected: PASS — both of `article_list_screen_test.dart`'s existing tests (`[SUMMARY ONLY]`/`[REMOVED]`
tags) still pass unmodified, since `ArticleListTile` renders byte-for-byte the same markup
`ArticleListScreen` used to build inline.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/features/articles/article_list_tile.dart mobile/test/article_list_tile_test.dart mobile/lib/features/articles/article_list_screen.dart
git commit -m "Extract ArticleListTile so the combined all-articles view can reuse it"
```

---

### Task 3: All Articles tab

**Files:**
- Create: `mobile/lib/features/articles/article_sort_order.dart`
- Create: `mobile/lib/features/articles/all_articles_screen.dart`
- Test: `mobile/test/all_articles_screen_test.dart`

**Interfaces:**
- Consumes: `ArticleWithFeed`/`AllArticlesQuery` (Task 1), `ArticleListTile` (Task 2).
- Produces:
  - `enum ArticleSortOrder { newestFirst, oldestFirst }`
  - `AllArticlesScreen({required AppDatabase db, required bool unreadOnly, required ArticleSortOrder sortOrder, Stream<List<ArticleWithFeed>>? articlesStream})`
    — a body-only widget (no own `Scaffold`/`AppBar`) with no internal filter/sort state; both are
    controlled externally so `HomeShell` (Task 4) can drive them from its shared AppBar.

- [ ] **Step 1: Write the failing test**

Create `mobile/test/all_articles_screen_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/article_with_feed.dart';
import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/articles/all_articles_screen.dart';
import 'package:deepread/features/articles/article_sort_order.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  LocalArticle article({
    required String id,
    required bool isRead,
    required DateTime publishedAt,
  }) =>
      LocalArticle(
        id: id,
        feedId: 'feed-1',
        title: 'Article $id',
        downloadedAt: publishedAt,
        publishedAt: publishedAt,
        isRead: isRead,
        localPath: 'articles/$id',
        evicted: false,
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<ArticleWithFeed> rows,
    bool unreadOnly = false,
    ArticleSortOrder sortOrder = ArticleSortOrder.newestFirst,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: AllArticlesScreen(
          db: db,
          unreadOnly: unreadOnly,
          sortOrder: sortOrder,
          articlesStream: Stream.value(rows),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows each article tagged with its own feed name', (tester) async {
    await pumpScreen(tester, rows: [
      (article: article(id: 'a', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'The Verge'),
      (article: article(id: 'b', isRead: true, publishedAt: DateTime(2026, 1, 2)), feedDisplayName: 'Ars Technica'),
    ]);

    expect(find.text('[The Verge]'), findsOneWidget);
    expect(find.text('[Ars Technica]'), findsOneWidget);
  });

  testWidgets('newestFirst sorts across feeds by date, not grouped by feed', (tester) async {
    await pumpScreen(
      tester,
      rows: [
        (article: article(id: 'old', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'Feed A'),
        (article: article(id: 'new', isRead: true, publishedAt: DateTime(2026, 1, 5)), feedDisplayName: 'Feed B'),
      ],
      sortOrder: ArticleSortOrder.newestFirst,
    );

    final titles = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(titles.indexOf('Article new') < titles.indexOf('Article old'), isTrue);
  });

  testWidgets('unreadOnly filters out read articles', (tester) async {
    await pumpScreen(
      tester,
      rows: [
        (article: article(id: 'read', isRead: true, publishedAt: DateTime(2026, 1, 1)), feedDisplayName: 'Feed A'),
        (article: article(id: 'unread', isRead: false, publishedAt: DateTime(2026, 1, 2)), feedDisplayName: 'Feed A'),
      ],
      unreadOnly: true,
    );

    expect(find.text('Article unread'), findsOneWidget);
    expect(find.text('Article read'), findsNothing);
  });

  testWidgets('shows empty-state text when there are no articles', (tester) async {
    await pumpScreen(tester, rows: []);

    expect(find.text('No articles downloaded yet.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/all_articles_screen_test.dart`
Expected: FAIL — neither `article_sort_order.dart` nor `all_articles_screen.dart` exist yet.

- [ ] **Step 3: Write the implementation**

Create `mobile/lib/features/articles/article_sort_order.dart`:

```dart
/// Sort direction for the combined all-articles view. A public enum
/// (rather than nested private in `AllArticlesScreen`, the way
/// `ArticleListScreen` keeps its own) because `HomeShell` needs the type
/// too, to build the AppBar's sort menu that drives this screen from
/// outside.
enum ArticleSortOrder { newestFirst, oldestFirst }
```

Create `mobile/lib/features/articles/all_articles_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../data/local/article_with_feed.dart';
import '../../data/local/database.dart';
import 'article_list_tile.dart';
import 'article_sort_order.dart';

/// Body-only widget (no own AppBar/Scaffold) embedded in `HomeShell`'s
/// bottom-nav shell. Sort/filter state is owned by `HomeShell`, not here,
/// since the icons that control it live in the shell's shared AppBar.
class AllArticlesScreen extends StatefulWidget {
  const AllArticlesScreen({
    super.key,
    required this.db,
    required this.unreadOnly,
    required this.sortOrder,
    this.articlesStream,
  });

  final AppDatabase db;
  final bool unreadOnly;
  final ArticleSortOrder sortOrder;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — see TECH_DEBT.md's note on drift .watch() streams
  /// inside testWidgets fake-async zones.
  final Stream<List<ArticleWithFeed>>? articlesStream;

  @override
  State<AllArticlesScreen> createState() => _AllArticlesScreenState();
}

class _AllArticlesScreenState extends State<AllArticlesScreen> {
  late final Stream<List<ArticleWithFeed>> _articlesStream;

  @override
  void initState() {
    super.initState();
    _articlesStream = widget.articlesStream ?? widget.db.watchAllArticlesWithFeed();
  }

  List<ArticleWithFeed> _applySortAndFilter(List<ArticleWithFeed> rows) {
    var result = widget.unreadOnly ? rows.where((r) => !r.article.isRead).toList() : List.of(rows);
    result.sort((a, b) {
      final aDate = a.article.publishedAt ?? a.article.downloadedAt;
      final bDate = b.article.publishedAt ?? b.article.downloadedAt;
      return widget.sortOrder == ArticleSortOrder.newestFirst
          ? bDate.compareTo(aDate)
          : aDate.compareTo(bDate);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ArticleWithFeed>>(
      stream: _articlesStream,
      builder: (context, snapshot) {
        final rows = _applySortAndFilter(snapshot.data ?? const []);
        if (rows.isEmpty) {
          return Center(
            child: Text(
              widget.unreadOnly ? 'No unread articles.' : 'No articles downloaded yet.',
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            return ArticleListTile(db: widget.db, article: row.article, feedLabel: row.feedDisplayName);
          },
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd mobile && flutter test test/all_articles_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/features/articles/article_sort_order.dart mobile/lib/features/articles/all_articles_screen.dart mobile/test/all_articles_screen_test.dart
git commit -m "Add the All Articles tab screen"
```

---

### Task 4: HomeShell nav bar and wiring

**Files:**
- Create: `mobile/lib/features/home/home_shell.dart`
- Test: `mobile/test/home_shell_test.dart`
- Modify: `mobile/lib/features/feeds/feed_list_screen.dart`
- Modify: `mobile/lib/features/auth/auth_gate.dart`
- Modify: `mobile/test/widget_test.dart`
- Modify: `mobile/lib/features/sync/sync_service.dart:394` (stale comment only)

**Interfaces:**
- Consumes: `AllArticlesScreen`/`ArticleSortOrder` (Task 3), `FeedListScreen` (this task narrows
  it), `SettingsScreen`, `AddFeedScreen`, `FeedRepository`, `SyncService`, `resetLocalData`
  (all existing).
- Produces:
  - `HomeShell({required AppDatabase db, Stream<List<LocalFeed>>? feedsStream, Stream<List<ArticleWithFeed>>? articlesStream, Future<void> Function(LocalFeed feed)? onUnsubscribe})`
  - `FeedListScreen`'s constructor changes: `onUnsubscribe` becomes **required** (was optional with
    an internal `FeedRepository`-backed default) — `FeedListScreen` no longer owns any
    sync/sign-out/unsubscribe-execution logic, only rendering + confirmation-dialog UI.

- [ ] **Step 1: Write the failing tests**

Create `mobile/test/home_shell_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/home/home_shell.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    List<LocalFeed> feeds = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // The Settings screen's list is taller than the default test viewport —
    // use a tall viewport so "Sign out" further down the list actually
    // gets built when a test navigates there.
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: HomeShell(
          db: db,
          feedsStream: Stream.value(feeds),
          articlesStream: Stream.value(const []),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('AppBar has a settings icon (not a standalone sign-out icon) that opens SettingsScreen',
      (tester) async {
    await pumpShell(tester);

    expect(find.byIcon(Icons.logout), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('Feeds tab is selected by default, showing the add-feed FAB and no filter/sort icons',
      (tester) async {
    await pumpShell(tester);

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.sort), findsNothing);
  });

  testWidgets('switching to the All Articles tab hides the FAB and shows filter/sort icons',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('All Articles'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsOneWidget);
  });

  testWidgets('switching tabs preserves the Feeds tab content instead of tearing it down',
      (tester) async {
    await pumpShell(tester, feeds: [
      const LocalFeed(id: 'feed-1', url: 'https://example.com/feed', title: 'Example Feed'),
    ]);

    expect(find.text('Example Feed'), findsOneWidget);

    await tester.tap(find.text('All Articles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feeds'));
    await tester.pumpAndSettle();

    expect(find.text('Example Feed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd mobile && flutter test test/home_shell_test.dart`
Expected: FAIL — `package:deepread/features/home/home_shell.dart` doesn't exist yet.

- [ ] **Step 3: Write `HomeShell`**

Create `mobile/lib/features/home/home_shell.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/article_with_feed.dart';
import '../../data/local/database.dart';
import '../../data/remote/feed_repository.dart';
import '../../data/remote/supabase_client.dart';
import '../../theme/app_theme.dart';
import '../articles/all_articles_screen.dart';
import '../articles/article_sort_order.dart';
import '../auth/local_data_reset.dart';
import '../feeds/add_feed_screen.dart';
import '../feeds/feed_list_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_service.dart';

/// The app's home screen: a shared AppBar (sync + settings, plus
/// filter/sort when the All Articles tab is active) and a bottom nav bar
/// switching between the Feeds tab ([FeedListScreen]) and the combined
/// All Articles tab ([AllArticlesScreen]). Owns state that's really
/// app-global rather than per-tab — sync-in-progress, sign-out, and
/// unsubscribe-execution — since all of it used to live on
/// [FeedListScreen] back when it was the app's only home screen.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    this.feedsStream,
    this.articlesStream,
    this.onUnsubscribe,
  });

  final AppDatabase db;
  final Stream<List<LocalFeed>>? feedsStream;
  final Stream<List<ArticleWithFeed>>? articlesStream;

  /// Overridable so widget tests can assert an unsubscribe was requested
  /// for the right feed without touching `FeedRepository`/Supabase. When
  /// null (the real app), [_unsubscribeFeed] is used.
  final Future<void> Function(LocalFeed feed)? onUnsubscribe;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _syncing = false;
  Future<void>? _syncFuture;
  bool _unreadOnly = false;
  ArticleSortOrder _sortOrder = ArticleSortOrder.newestFirst;

  @override
  void initState() {
    super.initState();
    unawaited(_syncNow());
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final future = SyncService(widget.db).syncNow();
    _syncFuture = future;
    try {
      await future;
    } catch (e) {
      // Sync failures (offline, expired session, Supabase unreachable)
      // shouldn't crash the screen — the user can already see and read
      // whatever was downloaded previously.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    final db = widget.db; // capture before any await — this widget may be
    // disposed once AuthGate reacts to the `signedOut` auth event.

    try {
      await AppSupabase.client.auth.signOut();
    } catch (_) {}

    try {
      await _syncFuture;
    } catch (_) {}

    final docsDir = await getApplicationDocumentsDirectory();
    await resetLocalData(
      db: db,
      articlesDir: Directory(p.join(docsDir.path, 'articles')),
    );
  }

  Future<void> _addFeed(String url) async {
    await FeedRepository(widget.db).subscribe(url);
    unawaited(_syncNow());
  }

  Future<void> _unsubscribeFeed(LocalFeed feed) async {
    try {
      // Drain any in-flight sync first — a sync mid-flight could
      // re-insert this feed's rows between local cleanup and its own
      // completion.
      await _syncFuture;
    } catch (_) {}

    try {
      await FeedRepository(widget.db).unsubscribe(feed.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove feed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAllArticles = _selectedIndex == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DeepRead'),
        actions: [
          if (isAllArticles) ...[
            IconButton(
              icon: Icon(_unreadOnly ? Icons.filter_alt : Icons.filter_alt_outlined),
              tooltip: _unreadOnly ? 'Showing unread only' : 'Show all',
              onPressed: () => setState(() => _unreadOnly = !_unreadOnly),
            ),
            PopupMenuButton<ArticleSortOrder>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              initialValue: _sortOrder,
              onSelected: (order) => setState(() => _sortOrder = order),
              itemBuilder: (context) => const [
                PopupMenuItem(value: ArticleSortOrder.newestFirst, child: Text('Newest first')),
                PopupMenuItem(value: ArticleSortOrder.oldestFirst, child: Text('Oldest first')),
              ],
            ),
          ],
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync now',
            onPressed: _syncing ? null : _syncNow,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(onSignOut: _signOut, db: widget.db),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FeedListScreen(
            db: widget.db,
            feedsStream: widget.feedsStream,
            onUnsubscribe: widget.onUnsubscribe ?? _unsubscribeFeed,
          ),
          AllArticlesScreen(
            db: widget.db,
            unreadOnly: _unreadOnly,
            sortOrder: _sortOrder,
            articlesStream: widget.articlesStream,
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddFeedScreen(onSubmit: _addFeed),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: DecoratedBox(
        // Flat, bordered look (matching the app's card language) instead
        // of Material 3's default pill-indicator NavigationBar.
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color ?? secondaryColor)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 12,
                color: states.contains(WidgetState.selected) ? AppTheme.accent : secondaryColor,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.rss_feed, color: secondaryColor),
                selectedIcon: const Icon(Icons.rss_feed, color: AppTheme.accent),
                label: 'Feeds',
              ),
              NavigationDestination(
                icon: Icon(Icons.dynamic_feed, color: secondaryColor),
                selectedIcon: const Icon(Icons.dynamic_feed, color: AppTheme.accent),
                label: 'All Articles',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Narrow `FeedListScreen` to a body-only widget**

Replace the full contents of `mobile/lib/features/feeds/feed_list_screen.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../articles/article_list_screen.dart';

/// Body-only widget (no own Scaffold/AppBar) — the Feeds tab inside
/// `HomeShell`'s bottom-nav shell. Sync-in-progress state, the AppBar's
/// sync/settings icons, the "add feed" FAB, and unsubscribe execution all
/// moved up to `HomeShell` when this stopped being the app's own home
/// screen; this widget only renders the list and its confirmation dialog.
class FeedListScreen extends StatefulWidget {
  const FeedListScreen({super.key, required this.db, this.feedsStream, required this.onUnsubscribe});

  final AppDatabase db;

  /// Overridable so widget tests can supply a plain [Stream] instead of a
  /// live drift query — drift's reactive query streams don't reliably
  /// deliver events when subscribed to directly inside a testWidgets
  /// fake-async zone.
  final Stream<List<LocalFeed>>? feedsStream;

  /// Called once the user confirms unsubscribing from a feed. Always
  /// supplied by `HomeShell` in the real app; tests inject their own to
  /// assert on the tapped feed without touching `FeedRepository`/Supabase.
  final Future<void> Function(LocalFeed feed) onUnsubscribe;

  @override
  State<FeedListScreen> createState() => _FeedListScreenState();
}

class _FeedListScreenState extends State<FeedListScreen> {
  late final Stream<List<LocalFeed>> _feedsStream;

  @override
  void initState() {
    super.initState();
    // Built once here, not in `build`, so a parent rebuild doesn't hand
    // StreamBuilder a new Stream identity (which would tear down and
    // resubscribe the underlying drift query on every rebuild).
    _feedsStream = widget.feedsStream ?? widget.db.select(widget.db.localFeeds).watch();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocalFeed>>(
      stream: _feedsStream,
      builder: (context, snapshot) {
        final feeds = snapshot.data ?? const [];
        if (feeds.isEmpty) {
          return const Center(child: Text('No feeds yet — add one to get started.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: feeds.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final feed = feeds[index];
            return Card(
              child: ListTile(
                title: Text(feed.title ?? feed.url),
                subtitle: Text(feed.url, style: Theme.of(context).textTheme.bodySmall),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArticleListScreen(db: widget.db, feed: feed),
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (_) => _confirmUnsubscribe(feed),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'unsubscribe', child: Text('Unsubscribe')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmUnsubscribe(LocalFeed feed) async {
    final articleCount = (await (widget.db.select(widget.db.localArticles)
              ..where((a) => a.feedId.equals(feed.id)))
            .get())
        .length;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe from feed?'),
        content: Text(
          'This removes $articleCount downloaded article${articleCount == 1 ? '' : 's'} '
          'from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.onUnsubscribe(feed);
    }
  }
}
```

- [ ] **Step 5: Wire `AuthGate` to `HomeShell`**

In `mobile/lib/features/auth/auth_gate.dart`, replace the `feed_list_screen.dart` import with the
`home_shell.dart` import, and replace `return FeedListScreen(db: db);` with `return HomeShell(db: db);`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/database.dart';
import '../../data/remote/supabase_client.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

/// Swaps between the login screen and the app itself based on Supabase
/// auth state — the single source of truth for "is someone signed in",
/// no separate local flag to keep in sync.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.db});

  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AppSupabase.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = AppSupabase.client.auth.currentSession;
        if (session == null) {
          return const LoginScreen();
        }
        return HomeShell(db: db);
      },
    );
  }
}
```

- [ ] **Step 6: Update `widget_test.dart`**

The "AppBar has a settings icon" test moved to `home_shell_test.dart` (Step 1 above, testing the
same behavior on `HomeShell` instead of `FeedListScreen`). `FeedListScreen`'s own `onUnsubscribe`
is now required, so the remaining empty-state test needs one passed in.

Replace the full contents of `mobile/test/widget_test.dart` with:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepread/data/local/database.dart';
import 'package:deepread/features/feeds/feed_list_screen.dart';
import 'package:deepread/theme/app_theme.dart';

void main() {
  testWidgets('Feed list shows empty state with no feeds', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: FeedListScreen(
          db: db,
          feedsStream: Stream.value(const []),
          onUnsubscribe: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No feeds yet — add one to get started.'), findsOneWidget);
  });
}
```

- [ ] **Step 7: Fix the stale comment in `sync_service.dart`**

In `mobile/lib/features/sync/sync_service.dart`, around line 394, update the comment that
currently reads:

```dart
    // know something went wrong: FeedListScreen's sync-button handler shows
```

to:

```dart
    // know something went wrong: HomeShell's sync-button handler shows
```

(The surrounding lines are unchanged — this is a one-line comment edit reflecting that the sync
button now lives on `HomeShell`, not `FeedListScreen`.)

- [ ] **Step 8: Run every test touched by this task**

Run: `cd mobile && flutter test test/home_shell_test.dart test/feed_list_screen_test.dart test/widget_test.dart`
Expected: PASS — all 4 new `home_shell_test.dart` tests, all 3 existing `feed_list_screen_test.dart`
tests (unmodified — its `onUnsubscribe` was already always supplied explicitly in every test case,
so making the field required doesn't change that file), and the 1 remaining `widget_test.dart` test.

- [ ] **Step 9: Run the full mobile test suite and analyzer to confirm no regressions elsewhere**

Run: `cd mobile && flutter test && flutter analyze`
Expected: PASS with no new analyzer warnings.

- [ ] **Step 10: Commit**

```bash
git add mobile/lib/features/home/home_shell.dart mobile/test/home_shell_test.dart mobile/lib/features/feeds/feed_list_screen.dart mobile/lib/features/auth/auth_gate.dart mobile/test/widget_test.dart mobile/lib/features/sync/sync_service.dart
git commit -m "Add HomeShell bottom-nav (Feeds | All Articles), narrowing FeedListScreen to a tab"
```

---

### Task 5: Housekeeping

**Files:**
- Modify: `TODO.md`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — documentation only.

- [ ] **Step 1: Remove the shipped TODO item**

In `TODO.md`, delete this line from the "Features" section (now implemented by Tasks 1–4 above):

```markdown
- [ ] Combined "all articles" view across every subscribed feed, so the user doesn't have to open each feed individually to see what's new.
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "Remove the combined all-articles-view TODO item now that it's shipped"
```

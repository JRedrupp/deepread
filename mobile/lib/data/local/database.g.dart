// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $LocalFeedsTable extends LocalFeeds
    with TableInfo<$LocalFeedsTable, LocalFeed> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalFeedsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, url, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_feeds';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalFeed> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalFeed map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalFeed(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
    );
  }

  @override
  $LocalFeedsTable createAlias(String alias) {
    return $LocalFeedsTable(attachedDatabase, alias);
  }
}

class LocalFeed extends DataClass implements Insertable<LocalFeed> {
  final String id;
  final String url;
  final String? title;
  const LocalFeed({required this.id, required this.url, this.title});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    return map;
  }

  LocalFeedsCompanion toCompanion(bool nullToAbsent) {
    return LocalFeedsCompanion(
      id: Value(id),
      url: Value(url),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
    );
  }

  factory LocalFeed.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalFeed(
      id: serializer.fromJson<String>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String?>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String?>(title),
    };
  }

  LocalFeed copyWith({
    String? id,
    String? url,
    Value<String?> title = const Value.absent(),
  }) => LocalFeed(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title.present ? title.value : this.title,
  );
  LocalFeed copyWithCompanion(LocalFeedsCompanion data) {
    return LocalFeed(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalFeed(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, url, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalFeed &&
          other.id == this.id &&
          other.url == this.url &&
          other.title == this.title);
}

class LocalFeedsCompanion extends UpdateCompanion<LocalFeed> {
  final Value<String> id;
  final Value<String> url;
  final Value<String?> title;
  final Value<int> rowid;
  const LocalFeedsCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalFeedsCompanion.insert({
    required String id,
    required String url,
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       url = Value(url);
  static Insertable<LocalFeed> custom({
    Expression<String>? id,
    Expression<String>? url,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalFeedsCompanion copyWith({
    Value<String>? id,
    Value<String>? url,
    Value<String?>? title,
    Value<int>? rowid,
  }) {
    return LocalFeedsCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalFeedsCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalArticlesTable extends LocalArticles
    with TableInfo<$LocalArticlesTable, LocalArticle> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalArticlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedIdMeta = const VerificationMeta('feedId');
  @override
  late final GeneratedColumn<String> feedId = GeneratedColumn<String>(
    'feed_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES local_feeds (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bylineMeta = const VerificationMeta('byline');
  @override
  late final GeneratedColumn<String> byline = GeneratedColumn<String>(
    'byline',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedAtMeta = const VerificationMeta(
    'publishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> publishedAt = GeneratedColumn<DateTime>(
    'published_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadedAtMeta = const VerificationMeta(
    'downloadedAt',
  );
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
    'downloaded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
    'is_read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    feedId,
    title,
    byline,
    publishedAt,
    downloadedAt,
    localPath,
    isRead,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_articles';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalArticle> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('feed_id')) {
      context.handle(
        _feedIdMeta,
        feedId.isAcceptableOrUnknown(data['feed_id']!, _feedIdMeta),
      );
    } else if (isInserting) {
      context.missing(_feedIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('byline')) {
      context.handle(
        _bylineMeta,
        byline.isAcceptableOrUnknown(data['byline']!, _bylineMeta),
      );
    }
    if (data.containsKey('published_at')) {
      context.handle(
        _publishedAtMeta,
        publishedAt.isAcceptableOrUnknown(
          data['published_at']!,
          _publishedAtMeta,
        ),
      );
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
        _downloadedAtMeta,
        downloadedAt.isAcceptableOrUnknown(
          data['downloaded_at']!,
          _downloadedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_downloadedAtMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('is_read')) {
      context.handle(
        _isReadMeta,
        isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalArticle map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalArticle(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      feedId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feed_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      byline: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}byline'],
      ),
      publishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published_at'],
      ),
      downloadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}downloaded_at'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      isRead: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_read'],
      )!,
    );
  }

  @override
  $LocalArticlesTable createAlias(String alias) {
    return $LocalArticlesTable(attachedDatabase, alias);
  }
}

class LocalArticle extends DataClass implements Insertable<LocalArticle> {
  final String id;
  final String feedId;
  final String title;
  final String? byline;
  final DateTime? publishedAt;
  final DateTime downloadedAt;

  /// Path (relative to app documents dir) to the unzipped folder
  /// containing index.html + images for this article.
  final String localPath;
  final bool isRead;
  const LocalArticle({
    required this.id,
    required this.feedId,
    required this.title,
    this.byline,
    this.publishedAt,
    required this.downloadedAt,
    required this.localPath,
    required this.isRead,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['feed_id'] = Variable<String>(feedId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || byline != null) {
      map['byline'] = Variable<String>(byline);
    }
    if (!nullToAbsent || publishedAt != null) {
      map['published_at'] = Variable<DateTime>(publishedAt);
    }
    map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    map['local_path'] = Variable<String>(localPath);
    map['is_read'] = Variable<bool>(isRead);
    return map;
  }

  LocalArticlesCompanion toCompanion(bool nullToAbsent) {
    return LocalArticlesCompanion(
      id: Value(id),
      feedId: Value(feedId),
      title: Value(title),
      byline: byline == null && nullToAbsent
          ? const Value.absent()
          : Value(byline),
      publishedAt: publishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedAt),
      downloadedAt: Value(downloadedAt),
      localPath: Value(localPath),
      isRead: Value(isRead),
    );
  }

  factory LocalArticle.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalArticle(
      id: serializer.fromJson<String>(json['id']),
      feedId: serializer.fromJson<String>(json['feedId']),
      title: serializer.fromJson<String>(json['title']),
      byline: serializer.fromJson<String?>(json['byline']),
      publishedAt: serializer.fromJson<DateTime?>(json['publishedAt']),
      downloadedAt: serializer.fromJson<DateTime>(json['downloadedAt']),
      localPath: serializer.fromJson<String>(json['localPath']),
      isRead: serializer.fromJson<bool>(json['isRead']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'feedId': serializer.toJson<String>(feedId),
      'title': serializer.toJson<String>(title),
      'byline': serializer.toJson<String?>(byline),
      'publishedAt': serializer.toJson<DateTime?>(publishedAt),
      'downloadedAt': serializer.toJson<DateTime>(downloadedAt),
      'localPath': serializer.toJson<String>(localPath),
      'isRead': serializer.toJson<bool>(isRead),
    };
  }

  LocalArticle copyWith({
    String? id,
    String? feedId,
    String? title,
    Value<String?> byline = const Value.absent(),
    Value<DateTime?> publishedAt = const Value.absent(),
    DateTime? downloadedAt,
    String? localPath,
    bool? isRead,
  }) => LocalArticle(
    id: id ?? this.id,
    feedId: feedId ?? this.feedId,
    title: title ?? this.title,
    byline: byline.present ? byline.value : this.byline,
    publishedAt: publishedAt.present ? publishedAt.value : this.publishedAt,
    downloadedAt: downloadedAt ?? this.downloadedAt,
    localPath: localPath ?? this.localPath,
    isRead: isRead ?? this.isRead,
  );
  LocalArticle copyWithCompanion(LocalArticlesCompanion data) {
    return LocalArticle(
      id: data.id.present ? data.id.value : this.id,
      feedId: data.feedId.present ? data.feedId.value : this.feedId,
      title: data.title.present ? data.title.value : this.title,
      byline: data.byline.present ? data.byline.value : this.byline,
      publishedAt: data.publishedAt.present
          ? data.publishedAt.value
          : this.publishedAt,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalArticle(')
          ..write('id: $id, ')
          ..write('feedId: $feedId, ')
          ..write('title: $title, ')
          ..write('byline: $byline, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('localPath: $localPath, ')
          ..write('isRead: $isRead')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    feedId,
    title,
    byline,
    publishedAt,
    downloadedAt,
    localPath,
    isRead,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalArticle &&
          other.id == this.id &&
          other.feedId == this.feedId &&
          other.title == this.title &&
          other.byline == this.byline &&
          other.publishedAt == this.publishedAt &&
          other.downloadedAt == this.downloadedAt &&
          other.localPath == this.localPath &&
          other.isRead == this.isRead);
}

class LocalArticlesCompanion extends UpdateCompanion<LocalArticle> {
  final Value<String> id;
  final Value<String> feedId;
  final Value<String> title;
  final Value<String?> byline;
  final Value<DateTime?> publishedAt;
  final Value<DateTime> downloadedAt;
  final Value<String> localPath;
  final Value<bool> isRead;
  final Value<int> rowid;
  const LocalArticlesCompanion({
    this.id = const Value.absent(),
    this.feedId = const Value.absent(),
    this.title = const Value.absent(),
    this.byline = const Value.absent(),
    this.publishedAt = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.localPath = const Value.absent(),
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalArticlesCompanion.insert({
    required String id,
    required String feedId,
    required String title,
    this.byline = const Value.absent(),
    this.publishedAt = const Value.absent(),
    required DateTime downloadedAt,
    required String localPath,
    this.isRead = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       feedId = Value(feedId),
       title = Value(title),
       downloadedAt = Value(downloadedAt),
       localPath = Value(localPath);
  static Insertable<LocalArticle> custom({
    Expression<String>? id,
    Expression<String>? feedId,
    Expression<String>? title,
    Expression<String>? byline,
    Expression<DateTime>? publishedAt,
    Expression<DateTime>? downloadedAt,
    Expression<String>? localPath,
    Expression<bool>? isRead,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (feedId != null) 'feed_id': feedId,
      if (title != null) 'title': title,
      if (byline != null) 'byline': byline,
      if (publishedAt != null) 'published_at': publishedAt,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (localPath != null) 'local_path': localPath,
      if (isRead != null) 'is_read': isRead,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalArticlesCompanion copyWith({
    Value<String>? id,
    Value<String>? feedId,
    Value<String>? title,
    Value<String?>? byline,
    Value<DateTime?>? publishedAt,
    Value<DateTime>? downloadedAt,
    Value<String>? localPath,
    Value<bool>? isRead,
    Value<int>? rowid,
  }) {
    return LocalArticlesCompanion(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      title: title ?? this.title,
      byline: byline ?? this.byline,
      publishedAt: publishedAt ?? this.publishedAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      localPath: localPath ?? this.localPath,
      isRead: isRead ?? this.isRead,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (feedId.present) {
      map['feed_id'] = Variable<String>(feedId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (byline.present) {
      map['byline'] = Variable<String>(byline.value);
    }
    if (publishedAt.present) {
      map['published_at'] = Variable<DateTime>(publishedAt.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalArticlesCompanion(')
          ..write('id: $id, ')
          ..write('feedId: $feedId, ')
          ..write('title: $title, ')
          ..write('byline: $byline, ')
          ..write('publishedAt: $publishedAt, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('localPath: $localPath, ')
          ..write('isRead: $isRead, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalFeedsTable localFeeds = $LocalFeedsTable(this);
  late final $LocalArticlesTable localArticles = $LocalArticlesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localFeeds,
    localArticles,
  ];
}

typedef $$LocalFeedsTableCreateCompanionBuilder =
    LocalFeedsCompanion Function({
      required String id,
      required String url,
      Value<String?> title,
      Value<int> rowid,
    });
typedef $$LocalFeedsTableUpdateCompanionBuilder =
    LocalFeedsCompanion Function({
      Value<String> id,
      Value<String> url,
      Value<String?> title,
      Value<int> rowid,
    });

final class $$LocalFeedsTableReferences
    extends BaseReferences<_$AppDatabase, $LocalFeedsTable, LocalFeed> {
  $$LocalFeedsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LocalArticlesTable, List<LocalArticle>>
  _localArticlesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localArticles,
    aliasName: 'local_feeds__id__local_articles__feed_id',
  );

  $$LocalArticlesTableProcessedTableManager get localArticlesRefs {
    final manager = $$LocalArticlesTableTableManager(
      $_db,
      $_db.localArticles,
    ).filter((f) => f.feedId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localArticlesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalFeedsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalFeedsTable> {
  $$LocalFeedsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> localArticlesRefs(
    Expression<bool> Function($$LocalArticlesTableFilterComposer f) f,
  ) {
    final $$LocalArticlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localArticles,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalArticlesTableFilterComposer(
            $db: $db,
            $table: $db.localArticles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalFeedsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalFeedsTable> {
  $$LocalFeedsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalFeedsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalFeedsTable> {
  $$LocalFeedsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  Expression<T> localArticlesRefs<T extends Object>(
    Expression<T> Function($$LocalArticlesTableAnnotationComposer a) f,
  ) {
    final $$LocalArticlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localArticles,
      getReferencedColumn: (t) => t.feedId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalArticlesTableAnnotationComposer(
            $db: $db,
            $table: $db.localArticles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalFeedsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalFeedsTable,
          LocalFeed,
          $$LocalFeedsTableFilterComposer,
          $$LocalFeedsTableOrderingComposer,
          $$LocalFeedsTableAnnotationComposer,
          $$LocalFeedsTableCreateCompanionBuilder,
          $$LocalFeedsTableUpdateCompanionBuilder,
          (LocalFeed, $$LocalFeedsTableReferences),
          LocalFeed,
          PrefetchHooks Function({bool localArticlesRefs})
        > {
  $$LocalFeedsTableTableManager(_$AppDatabase db, $LocalFeedsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalFeedsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalFeedsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalFeedsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFeedsCompanion(
                id: id,
                url: url,
                title: title,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String url,
                Value<String?> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalFeedsCompanion.insert(
                id: id,
                url: url,
                title: title,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalFeedsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localArticlesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localArticlesRefs) db.localArticles,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localArticlesRefs)
                    await $_getPrefetchedData<
                      LocalFeed,
                      $LocalFeedsTable,
                      LocalArticle
                    >(
                      currentTable: table,
                      referencedTable: $$LocalFeedsTableReferences
                          ._localArticlesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LocalFeedsTableReferences(
                            db,
                            table,
                            p0,
                          ).localArticlesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.feedId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LocalFeedsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalFeedsTable,
      LocalFeed,
      $$LocalFeedsTableFilterComposer,
      $$LocalFeedsTableOrderingComposer,
      $$LocalFeedsTableAnnotationComposer,
      $$LocalFeedsTableCreateCompanionBuilder,
      $$LocalFeedsTableUpdateCompanionBuilder,
      (LocalFeed, $$LocalFeedsTableReferences),
      LocalFeed,
      PrefetchHooks Function({bool localArticlesRefs})
    >;
typedef $$LocalArticlesTableCreateCompanionBuilder =
    LocalArticlesCompanion Function({
      required String id,
      required String feedId,
      required String title,
      Value<String?> byline,
      Value<DateTime?> publishedAt,
      required DateTime downloadedAt,
      required String localPath,
      Value<bool> isRead,
      Value<int> rowid,
    });
typedef $$LocalArticlesTableUpdateCompanionBuilder =
    LocalArticlesCompanion Function({
      Value<String> id,
      Value<String> feedId,
      Value<String> title,
      Value<String?> byline,
      Value<DateTime?> publishedAt,
      Value<DateTime> downloadedAt,
      Value<String> localPath,
      Value<bool> isRead,
      Value<int> rowid,
    });

final class $$LocalArticlesTableReferences
    extends BaseReferences<_$AppDatabase, $LocalArticlesTable, LocalArticle> {
  $$LocalArticlesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalFeedsTable _feedIdTable(_$AppDatabase db) =>
      db.localFeeds.createAlias('local_articles__feed_id__local_feeds__id');

  $$LocalFeedsTableProcessedTableManager get feedId {
    final $_column = $_itemColumn<String>('feed_id')!;

    final manager = $$LocalFeedsTableTableManager(
      $_db,
      $_db.localFeeds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_feedIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalArticlesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalArticlesTable> {
  $$LocalArticlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get byline => $composableBuilder(
    column: $table.byline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalFeedsTableFilterComposer get feedId {
    final $$LocalFeedsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.localFeeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalFeedsTableFilterComposer(
            $db: $db,
            $table: $db.localFeeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalArticlesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalArticlesTable> {
  $$LocalArticlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get byline => $composableBuilder(
    column: $table.byline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRead => $composableBuilder(
    column: $table.isRead,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalFeedsTableOrderingComposer get feedId {
    final $$LocalFeedsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.localFeeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalFeedsTableOrderingComposer(
            $db: $db,
            $table: $db.localFeeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalArticlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalArticlesTable> {
  $$LocalArticlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get byline =>
      $composableBuilder(column: $table.byline, builder: (column) => column);

  GeneratedColumn<DateTime> get publishedAt => $composableBuilder(
    column: $table.publishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
    column: $table.downloadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  $$LocalFeedsTableAnnotationComposer get feedId {
    final $$LocalFeedsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.feedId,
      referencedTable: $db.localFeeds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalFeedsTableAnnotationComposer(
            $db: $db,
            $table: $db.localFeeds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalArticlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalArticlesTable,
          LocalArticle,
          $$LocalArticlesTableFilterComposer,
          $$LocalArticlesTableOrderingComposer,
          $$LocalArticlesTableAnnotationComposer,
          $$LocalArticlesTableCreateCompanionBuilder,
          $$LocalArticlesTableUpdateCompanionBuilder,
          (LocalArticle, $$LocalArticlesTableReferences),
          LocalArticle,
          PrefetchHooks Function({bool feedId})
        > {
  $$LocalArticlesTableTableManager(_$AppDatabase db, $LocalArticlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalArticlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalArticlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalArticlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> feedId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> byline = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                Value<DateTime> downloadedAt = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<bool> isRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalArticlesCompanion(
                id: id,
                feedId: feedId,
                title: title,
                byline: byline,
                publishedAt: publishedAt,
                downloadedAt: downloadedAt,
                localPath: localPath,
                isRead: isRead,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String feedId,
                required String title,
                Value<String?> byline = const Value.absent(),
                Value<DateTime?> publishedAt = const Value.absent(),
                required DateTime downloadedAt,
                required String localPath,
                Value<bool> isRead = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalArticlesCompanion.insert(
                id: id,
                feedId: feedId,
                title: title,
                byline: byline,
                publishedAt: publishedAt,
                downloadedAt: downloadedAt,
                localPath: localPath,
                isRead: isRead,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalArticlesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({feedId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (feedId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.feedId,
                                referencedTable: $$LocalArticlesTableReferences
                                    ._feedIdTable(db),
                                referencedColumn: $$LocalArticlesTableReferences
                                    ._feedIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalArticlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalArticlesTable,
      LocalArticle,
      $$LocalArticlesTableFilterComposer,
      $$LocalArticlesTableOrderingComposer,
      $$LocalArticlesTableAnnotationComposer,
      $$LocalArticlesTableCreateCompanionBuilder,
      $$LocalArticlesTableUpdateCompanionBuilder,
      (LocalArticle, $$LocalArticlesTableReferences),
      LocalArticle,
      PrefetchHooks Function({bool feedId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalFeedsTableTableManager get localFeeds =>
      $$LocalFeedsTableTableManager(_db, _db.localFeeds);
  $$LocalArticlesTableTableManager get localArticles =>
      $$LocalArticlesTableTableManager(_db, _db.localArticles);
}

import 'package:drift/drift.dart';

/// 本地导入系列表（归属 `komga_native.sqlite` 不可再生用户资产库，ADR 0008/0009）。
class LocalSeriesRows extends Table {
  TextColumn get id => text()();

  TextColumn get title => text()();

  /// 小写规范化排序键（模拟 `titleSort`）。
  TextColumn get titleSort => text()();

  TextColumn get summary => text().withDefault(const Constant(''))();

  TextColumn get publisher => text().withDefault(const Constant(''))();

  /// JSON 字符串数组（如 `["作者A","作者B"]`）。
  TextColumn get authorsJson => text().withDefault(const Constant('[]'))();

  /// JSON 字符串数组（如 `["奇幻","冒险"]`）。
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// `leftToRight` / `rightToLeft` / `vertical` / `webtoon` / `unknown`。
  TextColumn get readingDirection =>
      text().withDefault(const Constant('unknown'))();

  /// 默认取首卷封面；用户也可指定某本分卷作为封面来源。
  TextColumn get coverBookId => text().nullable()();

  /// 用户手动设置系列封面时的受管相对路径（相对于 `local_comics/`）。
  TextColumn get customCoverPath => text().nullable()();

  /// 手动编辑元数据后置为 `true`，防止后续同名导入覆盖用户手工整理结果。
  BoolColumn get metadataLocked =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get releaseDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 本地导入单册/单卷表。
class LocalBooksRows extends Table {
  TextColumn get id => text()();

  TextColumn get seriesId => text()();

  TextColumn get name => text()();

  TextColumn get number => text().withDefault(const Constant(''))();

  RealColumn get numberSort => real().withDefault(const Constant(0.0))();

  IntColumn get pagesCount => integer()();

  IntColumn get sizeBytes => integer()();

  /// `'zip'`（CBZ/ZIP 单文件）、`'epub'`、`'tar'`、`'folder'`（受管沙盒），
  /// 或 `'ext_zip'` / `'ext_epub'` / `'ext_tar'` / `'ext_folder'` / `'saf_zip'` / `'saf_epub'` / `'saf_tar'`（外部原位挂载，LMB-08）。
  TextColumn get storageKind => text()();

  /// 沙盒受管书为相对于 `<ApplicationSupport>/local_comics/` 的路径；外部原位挂载书为 SAF URI 或原始路径。
  TextColumn get relativePath => text()();

  /// 导入或设封面时生成的缩略图相对路径（相对于 `<ApplicationSupport>/local_comics/`）。
  TextColumn get coverThumbPath => text().nullable()();

  /// 所属外部挂载根目录 ID（`null` 表示受管沙盒导入书，非空表示原位挂载外部书，LMB-08）。
  TextColumn get mountRootId => text().nullable()();

  /// 在挂载根目录下的规范化相对路径（如 `Frieren/Vol.01.cbz`），供增量扫描（LMB-09）与文件夹树视图（LMB-10）使用。
  TextColumn get sourceRelativePath => text().nullable()();

  /// 源文件最后修改时间戳（毫秒），用于增量扫描跳过未变更文件。
  IntColumn get sourceModifiedMs => integer().nullable()();

  /// 是否为尚未下载到本地的云盘占位文件（如 iOS iCloud `.icloud` 占位）。
  BoolColumn get isCloudPlaceholder =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get releaseDate => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 本地书籍页级索引与宽高缓存表（1 基页码，支持阅读器零扫描直开）。
class LocalPagesRows extends Table {
  TextColumn get bookId => text()();

  /// 1 基页码（与 `PageInfo.number` 一致）。
  IntColumn get pageNumber => integer()();

  TextColumn get entryName => text()();

  IntColumn get localHeaderOffset => integer().withDefault(const Constant(0))();

  IntColumn get compressedSize => integer().withDefault(const Constant(0))();

  IntColumn get uncompressedSize => integer().withDefault(const Constant(0))();

  IntColumn get compressionMethod => integer().withDefault(const Constant(0))();

  IntColumn get width => integer().nullable()();

  IntColumn get height => integer().nullable()();

  TextColumn get mediaType => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId, pageNumber};
}

/// 本地收藏集表（一组本地系列）。
class LocalCollectionsRows extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  BoolColumn get ordered => boolean().withDefault(const Constant(false))();

  TextColumn get seriesIdsJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 本地阅读列表表（跨系列本地书籍顺序单）。
class LocalReadListsRows extends Table {
  TextColumn get id => text()();

  TextColumn get name => text()();

  TextColumn get summary => text().withDefault(const Constant(''))();

  BoolColumn get ordered => boolean().withDefault(const Constant(false))();

  TextColumn get bookIdsJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 本地书籍内部章节目录表（EPUB TOC / 多子目录 / `ComicInfo.xml` 书签，LMB-05）。
class LocalBookChaptersRows extends Table {
  TextColumn get bookId => text()();

  /// 章节顺序序号（0 基，保证同一本书内严格保序）。
  IntColumn get chapterIndex => integer()();

  TextColumn get title => text()();

  /// 1 基起始页码。
  IntColumn get startPage => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{bookId, chapterIndex};
}

/// 外部挂载的本地漫画根目录表（Android SAF 树 / iOS Security-Scoped Bookmark / 普通目录，LMB-08）。
class LocalMountedRootsRows extends Table {
  TextColumn get id => text()();

  TextColumn get displayName => text()();

  /// Android SAF `content://` 树 URI、iOS Base64 Bookmark 或绝对目录路径。
  TextColumn get uriOrBookmark => text()();

  /// `'androidSaf'` / `'iosBookmark'` / `'localDirectory'`。
  TextColumn get kind => text()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  BoolColumn get hasNomedia => boolean().withDefault(const Constant(false))();

  DateTimeColumn get lastScannedAt => dateTime().nullable()();

  IntColumn get booksCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

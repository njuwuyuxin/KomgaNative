import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_domain/yomu_domain.dart';

import 'fake_library.dart';
import 'fake_reader.dart';

/// 单源 Komga 测试默认使用的远程内容源标识。
const String kTestKomgaSourceKey = 'https://komga.example.com';

/// 单源 Komga 测试默认内容源描述符。
const RemoteContentSource kTestKomgaSource = RemoteContentSource(
  sourceKey: kTestKomgaSourceKey,
  displayName: 'Test Komga',
  subtitle: kTestKomgaSourceKey,
);

/// 固定激活指定内容源的测试控制器（不触发磁盘设置恢复或真实会话监听）。
final class FixedActiveSourceController extends ActiveSourceController {
  FixedActiveSourceController(this._source);

  final ContentSource _source;

  @override
  ContentSource build() => _source;
}

/// 为单源测试与黄金图构造标准 `SourceRegistry` 覆写：
///
/// 全部路由、能力位查询与跨源「正在读」汇聚均走生产一致的 [sourceRegistryProvider] 链路，
/// 不再依赖生产代码里为测试保留的 `identical()` 特判分支。
List<Override> testSourceOverrides({
  LibraryRepository? library,
  ReaderRepository? reader,
  CollectionsRepository? collections,
  ReadStatusRepository? readStatus,
  DownloadService download = const NoopDownloadService(),
  ContentSource source = kTestKomgaSource,
  bool hideSourceGroupBar = true,
}) {
  final effectiveLibrary = library ?? FakeLibraryRepository();
  final effectiveReader = reader ?? FakeReaderRepository();
  final effectiveCollections =
      collections ??
      (effectiveLibrary is CollectionsRepository
          ? effectiveLibrary as CollectionsRepository
          : FakeLibraryRepository());
  final effectiveReadStatus =
      readStatus ??
      (effectiveLibrary is ReadStatusRepository
          ? effectiveLibrary as ReadStatusRepository
          : FakeLibraryRepository());

  final bundle = SourceBundle(
    source: source,
    library: effectiveLibrary,
    reader: effectiveReader,
    collections: effectiveCollections,
    readStatus: effectiveReadStatus,
    download: download,
  );
  // 若激活源为云端源，本机槽位复用除 ondeck 外的所有查询（兼容未显式标 `.withSource(...)`
  // 的测试实体默认 `kLocalSourceKey`），同时让 `crossSourceOndeckProvider` 只从远程源拉一次 `ondeck()`。
  final localBundle = source.isCloud
      ? SourceBundle(
          source: source,
          library: _EmptyOndeckLibraryProxy(effectiveLibrary),
          reader: effectiveReader,
          collections: effectiveCollections,
          readStatus: effectiveReadStatus,
          download: download,
        )
      : bundle;

  final registry = SourceRegistry(
    localBundle: localBundle,
    remoteBundles: source.isCloud
        ? <String, SourceBundle>{source.sourceKey: bundle}
        : const <String, SourceBundle>{},
  );
  return <Override>[
    sourceRegistryProvider.overrideWithValue(registry),
    activeSourceProvider.overrideWith(
      () => FixedActiveSourceController(source),
    ),
    if (hideSourceGroupBar)
      availableSourcesProvider.overrideWithValue(<ContentSource>[source]),
  ];
}

final class _EmptyOndeckLibraryProxy implements LibraryRepository {
  const _EmptyOndeckLibraryProxy(this._delegate);

  final LibraryRepository _delegate;

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async => PageResult<Book>(
    items: const <Book>[],
    totalElements: 0,
    page: 0,
    size: size,
  );

  @override
  Future<List<Library>> libraries() => _delegate.libraries();

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) => _delegate.series(
    libraryId: libraryId,
    query: query,
    page: page,
    size: size,
    sort: sort,
    readStatus: readStatus,
    tag: tag,
  );

  @override
  Future<Series?> seriesById(String seriesId) => _delegate.seriesById(seriesId);

  @override
  Future<Book?> book(String bookId) => _delegate.book(bookId);

  @override
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) => _delegate.books(
    seriesId,
    page: page,
    size: size,
    sort: sort,
    readStatus: readStatus,
  );

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) => _delegate.searchBooks(query, page: page, size: size);

  @override
  Future<Uint8List?> seriesCover(String seriesId) =>
      _delegate.seriesCover(seriesId);

  @override
  Future<Uint8List?> bookCover(String bookId) => _delegate.bookCover(bookId);
}

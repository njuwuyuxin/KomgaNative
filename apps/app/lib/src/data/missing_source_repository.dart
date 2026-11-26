import 'dart:typed_data';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/data/shelf_failure.dart';

/// 未知或已删除内容源的显式兜底仓库（P1-3）。
///
/// 绝不静默回退到本机书库：装饰性封面按约定返回 `null`，
/// 其余读写查询明确抛出 [ServerFailure]，由页面展示错误态而非读写错误分区。
class MissingSourceRepository
    implements
        LibraryRepository,
        ReaderRepository,
        CollectionsRepository,
        ReadStatusRepository {
  const MissingSourceRepository(this.sourceKey);

  final String sourceKey;

  Never _fail() => throw const ServerFailure();

  @override
  Future<List<Library>> libraries() async => _fail();

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) async => _fail();

  @override
  Future<Series?> seriesById(String seriesId) async => _fail();

  @override
  Future<Book?> book(String bookId) async => _fail();

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async => _fail();

  @override
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) async => _fail();

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async => _fail();

  @override
  Future<Uint8List?> seriesCover(String seriesId) async => null;

  @override
  Future<Uint8List?> bookCover(String bookId) async => null;

  @override
  Future<List<PageInfo>> pages(String bookId) async => _fail();

  @override
  Future<Uint8List> pageImage(String bookId, int page) async => _fail();

  @override
  Uint8List? cachedPageImage(String bookId, int page) => null;

  @override
  Future<Uint8List> pageThumbnail(String bookId, int page) async => _fail();

  @override
  Uint8List? cachedPageThumbnail(String bookId, int page) => null;

  @override
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  }) async => _fail();

  @override
  Future<KomgaCollection?> collectionById(String collectionId) async => _fail();

  @override
  Future<List<KomgaCollection>> seriesCollections(String seriesId) async =>
      _fail();

  @override
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async => _fail();

  @override
  Future<void> renameCollection(String collectionId, String name) async =>
      _fail();

  @override
  Future<void> updateCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  }) async => _fail();

  @override
  Future<void> deleteCollection(String collectionId) async => _fail();

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async => _fail();

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async =>
      _fail();

  @override
  Future<ReadList?> readListById(String readListId) async => _fail();

  @override
  Future<List<ReadList>> bookReadLists(String bookId) async => _fail();

  @override
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async => _fail();

  @override
  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async => _fail();

  @override
  Future<void> deleteReadList(String readListId) async => _fail();

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async => _fail();

  @override
  Future<void> setSeriesRead(String seriesId, {required bool read}) async =>
      _fail();

  @override
  Future<void> setBookRead(
    String bookId, {
    required bool read,
    required int pagesCount,
  }) async => _fail();
}

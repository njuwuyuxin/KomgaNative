/// 领域实体与值对象。
///
/// 命名约定：`Komga*` 前缀只用在 API DTO 上；领域模型不带前缀。
library;

import 'package:yomu_domain/src/content_source.dart';

/// 漫画阅读方向（可由服务端或本地归档元数据下发）。
enum ReadingDirection {
  leftToRight,
  rightToLeft,
  vertical,
  webtoon,
  unknown;

  /// Komga 的取值是字符串且规格未给枚举约束，这里做宽松解析。
  static ReadingDirection parse(String? raw) {
    if (raw == null || raw.isEmpty) return ReadingDirection.unknown;
    return switch (raw.toUpperCase().replaceAll('_', '').replaceAll('-', '')) {
      'LEFTTORIGHT' || 'LTR' => ReadingDirection.leftToRight,
      'RIGHTTOLEFT' || 'RTL' => ReadingDirection.rightToLeft,
      'VERTICAL' => ReadingDirection.vertical,
      'WEBTOON' => ReadingDirection.webtoon,
      _ => ReadingDirection.unknown,
    };
  }

  bool get isRightToLeft => this == ReadingDirection.rightToLeft;
  bool get isScroll =>
      this == ReadingDirection.vertical || this == ReadingDirection.webtoon;
}

/// 书的媒体类型，由服务端 `mediaProfile` 决定阅读器走哪条路径。
enum MediaProfile {
  divina,
  epub,
  pdf,
  unknown;

  static MediaProfile parse(String? raw) => switch ((raw ?? '').toUpperCase()) {
    'DIVINA' => MediaProfile.divina,
    'EPUB' => MediaProfile.epub,
    'PDF' => MediaProfile.pdf,
    _ => MediaProfile.unknown,
  };

  /// v1 阅读器只处理"图片序列"（DiViNa / PDF / Divina-EPUB 都由服务端渲染成页图）。
  bool get isImageSequence =>
      this != MediaProfile.epub && this != MediaProfile.unknown;
}

/// 阅读进度。
///
/// [page] 为 **1 基**页码，与 Komga API 一致；未读书不应有 [ReadProgress] 实例。
/// [lastModified] 是服务端时间，做多设备对账时**只用它**，不用客户端墙钟。
class ReadProgress {
  const ReadProgress({
    required this.page,
    required this.completed,
    required this.lastModified,
    this.readDate,
  });

  final int page;
  final bool completed;
  final DateTime lastModified;
  final DateTime? readDate;

  @override
  bool operator ==(Object other) =>
      other is ReadProgress &&
      other.page == page &&
      other.completed == completed &&
      other.lastModified == lastModified;

  @override
  int get hashCode => Object.hash(page, completed, lastModified);

  @override
  String toString() =>
      'ReadProgress(page: $page, completed: $completed, at: $lastModified)';
}

/// 单页元数据。
class PageInfo {
  const PageInfo({
    required this.number,
    this.width,
    this.height,
    this.mediaType,
    this.sizeBytes,
  });

  /// 1 基页码。
  final int number;

  /// 服务端可能不返回宽高（`/pages` 的 width/height 非必返），此时需要解码后测量。
  final int? width;
  final int? height;
  final String? mediaType;
  final int? sizeBytes;

  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

class Library {
  const Library({
    required this.id,
    required this.name,
    this.unavailable = false,
  });

  final String id;
  final String name;
  final bool unavailable;
}

class Series {
  const Series({
    required this.id,
    required this.libraryId,
    required this.title,
    this.booksCount = 0,
    this.booksReadCount = 0,
    this.readingDirection = ReadingDirection.unknown,
    this.summary,
    this.authors = const <String>[],
    this.publisher,
    this.releaseDate,
    this.tags = const <String>[],
    this.sourceKey = kLocalSourceKey,
  });

  final String id;
  final String libraryId;
  final String title;
  final int booksCount;
  final int booksReadCount;
  final ReadingDirection readingDirection;
  final String? summary;
  final List<String> authors;
  final String? publisher;
  final DateTime? releaseDate;
  final List<String> tags;

  /// 所属内容源标识（默认 [kLocalSourceKey]，远程服务器返回规范化 `sourceKey`）。
  final String sourceKey;

  bool get isCloud => !isLocalSourceKey(sourceKey);

  double get progress {
    if (booksCount <= 0) return 0;
    return (booksReadCount / booksCount).clamp(0, 1).toDouble();
  }

  Series withSource(String nextSourceKey) => Series(
    id: id,
    libraryId: libraryId,
    title: title,
    booksCount: booksCount,
    booksReadCount: booksReadCount,
    readingDirection: readingDirection,
    summary: summary,
    authors: authors,
    publisher: publisher,
    releaseDate: releaseDate,
    tags: tags,
    sourceKey: nextSourceKey,
  );
}

class Book {
  const Book({
    required this.id,
    required this.seriesId,
    required this.name,
    required this.pagesCount,
    this.seriesTitle,
    this.number = '',
    this.mediaProfile = MediaProfile.divina,
    this.sizeBytes = 0,
    this.readProgress,
    this.sourceKey = kLocalSourceKey,
  });

  final String id;
  final String seriesId;
  final String name;
  final String? seriesTitle;
  final String number;
  final int pagesCount;
  final MediaProfile mediaProfile;
  final int sizeBytes;
  final ReadProgress? readProgress;
  final String sourceKey;

  bool get isCloud => !isLocalSourceKey(sourceKey);
  bool get isUnread => readProgress == null;
  bool get isCompleted => readProgress?.completed ?? false;

  Book withProgress(ReadProgress? progress) => Book(
    id: id,
    seriesId: seriesId,
    name: name,
    seriesTitle: seriesTitle,
    number: number,
    pagesCount: pagesCount,
    mediaProfile: mediaProfile,
    sizeBytes: sizeBytes,
    readProgress: progress,
    sourceKey: sourceKey,
  );

  Book withSource(String nextSourceKey) => Book(
    id: id,
    seriesId: seriesId,
    name: name,
    seriesTitle: seriesTitle,
    number: number,
    pagesCount: pagesCount,
    mediaProfile: mediaProfile,
    sizeBytes: sizeBytes,
    readProgress: readProgress,
    sourceKey: nextSourceKey,
  );
}

/// Komga 分页查询结果。
///
/// Komga 的 `page` 是 **0 基**（与阅读进度页码不同），`size` 是每页条数。
class PageResult<T> {
  const PageResult({
    required this.items,
    required this.totalElements,
    required this.page,
    required this.size,
  });

  final List<T> items;
  final int totalElements;

  /// 0 基页序号。
  final int page;
  final int size;

  int get totalPages => size <= 0 ? 0 : (totalElements + size - 1) ~/ size;

  bool get hasMore => (page + 1) * size < totalElements;
}

/// 墨水屏信息。检测不到时返回 [unknown]。
class EinkInfo {
  const EinkInfo({this.isEink = false, this.vendor = 'unknown'});

  static const EinkInfo unknown = EinkInfo();

  final bool isEink;

  /// onyx / hisense / moaan / unknown
  final String vendor;
}

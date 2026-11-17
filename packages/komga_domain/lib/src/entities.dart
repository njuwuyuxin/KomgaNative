/// 领域实体与值对象。
///
/// 命名约定：`Komga*` 前缀只用在 API DTO 上；领域模型不带前缀。
library;

/// 服务器认证方式。
enum AuthKind {
  /// 长期有效的 API Key（`X-API-Key`），推荐。
  apiKey,

  /// 用户名/密码（Basic Auth），仅用于首次换取 API Key。
  basic,
}

/// 用户配置的一台 Komga 服务器。
class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    this.authKind = AuthKind.apiKey,
    this.userId,
  });

  final String id;
  final String displayName;

  /// 形如 `https://komga.example.com`，不带结尾斜杠。
  final String baseUrl;

  final AuthKind authKind;
  final String? userId;

  ServerProfile copyWith({String? displayName, String? baseUrl}) {
    return ServerProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      authKind: authKind,
      userId: userId,
    );
  }
}

/// 漫画阅读方向。Komga 在系列元数据里下发，因此可跨端同步。
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
  });

  final String id;
  final String libraryId;
  final String title;
  final int booksCount;
  final int booksReadCount;
  final ReadingDirection readingDirection;
  final String? summary;

  double get progress {
    if (booksCount <= 0) return 0;
    return (booksReadCount / booksCount).clamp(0, 1).toDouble();
  }
}

class Book {
  const Book({
    required this.id,
    required this.seriesId,
    required this.name,
    required this.pagesCount,
    this.number = '',
    this.mediaProfile = MediaProfile.divina,
    this.sizeBytes = 0,
    this.readProgress,
  });

  final String id;
  final String seriesId;
  final String name;

  /// 卷号/章节号，字符串（Komga 里可能是 "1", "1.5", ""）。
  final String number;

  final int pagesCount;
  final MediaProfile mediaProfile;
  final int sizeBytes;
  final ReadProgress? readProgress;

  bool get isUnread => readProgress == null;
  bool get isCompleted => readProgress?.completed ?? false;
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

/// 设备形态，用于布局与阅读器默认值。
enum FormFactor { phone, tablet, desktopLike }

/// 墨水屏信息。检测不到时返回 [unknown]。
class EinkInfo {
  const EinkInfo({this.isEink = false, this.vendor = 'unknown'});

  static const EinkInfo unknown = EinkInfo();

  final bool isEink;

  /// onyx / hisense / moaan / unknown
  final String vendor;
}

/// 纯 Dart 本地漫画归档引擎。
///
/// 约束：零第三方依赖，禁止 import flutter / dio / drift / go_router（由 `tool/ci.dart layers` 保障）。
library;

export 'src/archive_errors.dart';
export 'src/byte_source.dart';
export 'src/chapter_extractor.dart';
export 'src/comic_info_parser.dart';
export 'src/epub_opf_parser.dart';
export 'src/epub_page_reader.dart';
export 'src/epub_toc_parser.dart';
export 'src/folder_page_reader.dart';
export 'src/image_dimensions.dart';
export 'src/legacy_charset.dart';
export 'src/natural_sort.dart';
export 'src/nested_archive_inspector.dart';
export 'src/rar_header_parser.dart';
export 'src/solid_window_cache.dart';
export 'src/tar_page_reader.dart';
export 'src/zip_directory.dart';
export 'src/zip_page_reader.dart';

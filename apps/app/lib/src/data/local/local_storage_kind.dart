import 'package:yomu/src/data/local/native_archive_reader.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 本地受管沙盒与外部挂载书籍的存储格式枚举（P1-6）。
///
/// 收敛所有散落的 `storageKind == 'pdf' / 'cb7' / 'ext_*'` 字符串分支，
/// 新增格式时由 `switch (kind)` 编译期保证阅读器与封面提取同步覆盖。
enum LocalStorageKind {
  zip('zip'),
  epub('epub'),
  tar('tar'),
  folder('folder'),
  pdf('pdf'),
  cb7('cb7'),
  cbr('cbr'),
  extZip('ext_zip'),
  extEpub('ext_epub'),
  extTar('ext_tar'),
  extFolder('ext_folder'),
  extPdf('ext_pdf'),
  extCb7('ext_cb7'),
  extCbr('ext_cbr'),
  safZip('saf_zip'),
  safEpub('saf_epub'),
  safTar('saf_tar'),
  safPdf('saf_pdf');

  const LocalStorageKind(this.wireValue);

  /// 持久化到 `local_books_rows.storage_kind` 的稳定字符串。
  final String wireValue;

  static final Map<String, LocalStorageKind> _byWire =
      <String, LocalStorageKind>{
        for (final value in values) value.wireValue: value,
      };

  /// 从数据库字段解析枚举；未知旧值温和回退 [LocalStorageKind.zip]。
  static LocalStorageKind parse(String raw) => _byWire[raw] ?? zip;

  /// 根据已打开的受管归档读取器推断存储种类。
  static LocalStorageKind forManagedReader(ComicArchiveReader reader) =>
      switch (reader) {
        NativePdfComicReader() => pdf,
        NativeArchiveComicReader(:final format) =>
          format == NativeArchiveFormat.sevenZip ? cb7 : cbr,
        EpubComicReader() => epub,
        TarComicReader() => tar,
        FolderComicReader() => folder,
        _ => zip,
      };

  /// 根据外部读取器与挂载类型推断外部存储种类。
  static LocalStorageKind forExternalReader(
    ComicArchiveReader reader, {
    required bool useBridge,
  }) => switch (reader) {
    NativePdfComicReader() => useBridge ? safPdf : extPdf,
    NativeArchiveComicReader(:final format) =>
      format == NativeArchiveFormat.sevenZip ? extCb7 : extCbr,
    EpubComicReader() => useBridge ? safEpub : extEpub,
    TarComicReader() => useBridge ? safTar : extTar,
    FolderComicReader() => extFolder,
    _ => useBridge ? safZip : extZip,
  };

  bool get isPdf => this == pdf || this == extPdf || this == safPdf;

  bool get isSaf =>
      this == safZip || this == safEpub || this == safTar || this == safPdf;
}

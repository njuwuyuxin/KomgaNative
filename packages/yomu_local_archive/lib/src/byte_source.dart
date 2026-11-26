import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';

/// 平台与介质无关的随机访问字节源。
///
/// - 单测使用 [MemoryByteSource]（零临时文件 I/O）；
/// - 沙盒文件使用 [FileByteSource]（内置异步互斥锁保护单文件游标）；
/// - 后续扩展 Android SAF 文件描述符或 WebDAV Range 流时只需实现本接口。
abstract interface class RandomAccessByteSource {
  Future<int> length();

  /// 从 [offset] 处读取最多 [count] 字节；若到达文件末尾，返回实际可读字节。
  Future<Uint8List> readRange(int offset, int count);

  Future<void> close();
}

/// 纯内存字节源（单测与小缓冲场景）。
final class MemoryByteSource implements RandomAccessByteSource {
  MemoryByteSource(this._bytes);

  final Uint8List _bytes;
  bool _closed = false;

  @override
  Future<int> length() async {
    _ensureOpen();
    return _bytes.length;
  }

  @override
  Future<Uint8List> readRange(int offset, int count) async {
    _ensureOpen();
    if (offset < 0 || count < 0) {
      throw ArgumentError('Invalid range: offset=$offset, count=$count');
    }
    if (count == 0 || offset >= _bytes.length) return Uint8List(0);
    final end = (offset + count).clamp(offset, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, end);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ArchiveException(
        ArchiveErrorKind.ioError,
        'Byte source is already closed',
      );
    }
  }
}

/// 基于 `dart:io` [RandomAccessFile] 的随机读取实现。
///
/// `RandomAccessFile` 共享单一底层偏移指针；阅读器预取窗口会并发发起多页读取，
/// 因此通过 [_serial] 串行化每次 `setPosition + readInto`，杜绝并发游标串位。
final class FileByteSource implements RandomAccessByteSource {
  FileByteSource._(this._raf, this._length, this.filePath);

  static Future<FileByteSource> open(File file) async {
    try {
      final raf = await file.open();
      final len = await raf.length();
      return FileByteSource._(raf, len, file.path);
    } on FileSystemException catch (e) {
      throw ArchiveException(ArchiveErrorKind.ioError, e.message);
    }
  }

  final RandomAccessFile _raf;
  final int _length;

  /// 底层磁盘文件路径（供大型归档扫描卸载至后台 Isolate 独立读取，不占 UI 线程）。
  final String filePath;
  Future<void> _serial = Future<void>.value();
  bool _closed = false;

  @override
  Future<int> length() async {
    if (_closed) {
      throw const ArchiveException(
        ArchiveErrorKind.ioError,
        'File byte source is closed',
      );
    }
    return _length;
  }

  @override
  Future<Uint8List> readRange(int offset, int count) {
    if (offset < 0 || count < 0) {
      return Future<Uint8List>.error(
        ArgumentError('Invalid range: offset=$offset, count=$count'),
      );
    }
    return _enqueue<Uint8List>(() async {
      if (_closed) {
        throw const ArchiveException(
          ArchiveErrorKind.ioError,
          'File byte source is closed',
        );
      }
      if (count == 0 || offset >= _length) return Uint8List(0);
      final toRead = (offset + count > _length) ? (_length - offset) : count;
      try {
        await _raf.setPosition(offset);
        return await _raf.read(toRead);
      } on FileSystemException catch (e) {
        throw ArchiveException(ArchiveErrorKind.ioError, e.message);
      }
    });
  }

  @override
  Future<void> close() {
    return _enqueue<void>(() async {
      if (_closed) return;
      _closed = true;
      try {
        await _raf.close();
      } on FileSystemException {
        // 关闭时忽略底层句柄释放异常。
      }
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _serial = _serial.whenComplete(() async {
      try {
        completer.complete(await task());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

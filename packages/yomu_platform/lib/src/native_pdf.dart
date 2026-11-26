import 'package:flutter/services.dart';

/// 原生 PDF 引擎抛出的结构化错误分类（LMB-11 / LMB-13）。
enum PdfOpenErrorKind { invalidPassword, corrupted, unsupported, ioError }

final class PdfPlatformException implements Exception {
  const PdfPlatformException(this.kind, [this.message]);

  final PdfOpenErrorKind kind;
  final String? message;

  @override
  String toString() => message == null
      ? 'PdfPlatformException(${kind.name})'
      : 'PdfPlatformException(${kind.name}: $message)';
}

/// PDF 单页尺寸（单位：PDF 点，1 基页码）。
final class PdfPageMetrics {
  const PdfPageMetrics({
    required this.pageNumber,
    required this.widthPt,
    required this.heightPt,
  });

  final int pageNumber;
  final int widthPt;
  final int heightPt;
}

/// PDF 内嵌大纲（Outline / Bookmark）条目（1 基页码）。
final class PdfOutlineItem {
  const PdfOutlineItem({required this.title, required this.startPage});

  final String title;
  final int startPage;
}

/// PDF 文档元信息与大纲快照。
final class PdfDocumentInfo {
  const PdfDocumentInfo({
    required this.pageCount,
    required this.pages,
    this.outline = const <PdfOutlineItem>[],
    this.title,
    this.author,
  });

  final int pageCount;
  final List<PdfPageMetrics> pages;
  final List<PdfOutlineItem> outline;
  final String? title;
  final String? author;
}

/// 平台原生 PDF 渲染与大纲解析抽象（Android `PdfRenderer` + iOS `PDFKit`，零第三方依赖，LMB-11）。
abstract interface class NativePdfBridge {
  /// 检查 PDF 文档页数、每页尺寸、标题作者与内嵌大纲；若文档加密且密码缺失或错误抛出 [PdfOpenErrorKind.invalidPassword]。
  Future<PdfDocumentInfo> inspect(String filePath, {String? password});

  /// 按指定目标宽度像素按需光栅化单页为 PNG 字节（支持标准清晰度与缩放后高清重绘）。
  Future<Uint8List> renderPage({
    required String filePath,
    required int pageNumber,
    required int targetWidthPx,
    String? password,
  });

  /// 释放底层原生 PDF 文档句柄缓存。
  Future<void> closeDocument(String filePath);
}

/// 基于 `yomu/native_pdf` MethodChannel 的原生 PDF 桥接实现。
class ChannelNativePdfBridge implements NativePdfBridge {
  ChannelNativePdfBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yomu/native_pdf');

  final MethodChannel _channel;

  @override
  Future<PdfDocumentInfo> inspect(String filePath, {String? password}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'inspect',
        <String, Object?>{'filePath': filePath, 'password': password},
      );
      if (raw == null) {
        throw const PdfPlatformException(
          PdfOpenErrorKind.unsupported,
          'Native PDF engine unavailable',
        );
      }
      final pageCount = (raw['pageCount'] as int?) ?? 0;
      final rawPages = raw['pages'] as List<Object?>? ?? const <Object?>[];
      final pages = <PdfPageMetrics>[];
      for (var i = 0; i < rawPages.length; i++) {
        final item = rawPages[i];
        if (item is Map<Object?, Object?>) {
          pages.add(
            PdfPageMetrics(
              pageNumber: (item['pageNumber'] as int?) ?? (i + 1),
              widthPt: (item['width'] as int?) ?? 800,
              heightPt: (item['height'] as int?) ?? 1200,
            ),
          );
        }
      }
      final rawOutline = raw['outline'] as List<Object?>? ?? const <Object?>[];
      final outline = <PdfOutlineItem>[];
      for (final item in rawOutline) {
        if (item is Map<Object?, Object?>) {
          final title = (item['title'] as String?)?.trim() ?? '';
          final page = item['startPage'] as int?;
          if (title.isNotEmpty && page != null && page >= 1) {
            outline.add(PdfOutlineItem(title: title, startPage: page));
          }
        }
      }
      return PdfDocumentInfo(
        pageCount: pageCount > 0 ? pageCount : pages.length,
        pages: List<PdfPageMetrics>.unmodifiable(pages),
        outline: List<PdfOutlineItem>.unmodifiable(outline),
        title: _cleanOpt(raw['title'] as String?),
        author: _cleanOpt(raw['author'] as String?),
      );
    } on MissingPluginException {
      throw const PdfPlatformException(
        PdfOpenErrorKind.unsupported,
        'Native PDF channel not implemented on this platform',
      );
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<Uint8List> renderPage({
    required String filePath,
    required int pageNumber,
    required int targetWidthPx,
    String? password,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'renderPage',
        <String, Object?>{
          'filePath': filePath,
          'pageNumber': pageNumber,
          'targetWidthPx': targetWidthPx.clamp(240, 3200),
          'password': password,
        },
      );
      if (bytes == null || bytes.isEmpty) {
        throw const PdfPlatformException(
          PdfOpenErrorKind.corrupted,
          'Empty rendered PDF page bytes',
        );
      }
      return bytes;
    } on MissingPluginException {
      throw const PdfPlatformException(
        PdfOpenErrorKind.unsupported,
        'Native PDF channel not implemented on this platform',
      );
    } on PlatformException catch (e) {
      throw _mapPlatformError(e);
    }
  }

  @override
  Future<void> closeDocument(String filePath) async {
    try {
      await _channel.invokeMethod<void>('closeDocument', <String, Object?>{
        'filePath': filePath,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static PdfPlatformException _mapPlatformError(PlatformException e) {
    final kind = switch (e.code) {
      'INVALID_PASSWORD' => PdfOpenErrorKind.invalidPassword,
      'CORRUPTED' => PdfOpenErrorKind.corrupted,
      'UNSUPPORTED' => PdfOpenErrorKind.unsupported,
      _ => PdfOpenErrorKind.ioError,
    };
    return PdfPlatformException(kind, e.message);
  }

  static String? _cleanOpt(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_repository.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// 阅读器仓库：跟着会话走，会话变了就重建并关掉旧连接。
final Provider<ReaderRepository> readerRepositoryProvider =
    Provider<ReaderRepository>((Ref ref) {
      final session = ref.watch(sessionProvider);
      if (session is! SessionConnected) {
        throw StateError('未连接服务器时不应打开阅读器');
      }
      final komga = KomgaSession.withApiKey(
        address: session.server.address,
        apiKey: session.server.apiKey,
        trust: session.server.tls,
      );
      ref.onDispose(komga.close);
      return KomgaReaderRepository(komga);
    });

final readerBookProvider = FutureProvider.family<Book?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(readerRepositoryProvider).book(bookId);
});

/// 页列表（尺寸用于布局；页码 1 基）。
final readerPagesProvider = FutureProvider.family<List<PageInfo>, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(readerRepositoryProvider).pages(bookId);
});

/// 一页的图片字节。family 参数用 record，值相等即同一个 provider。
typedef PageRequest = ({String bookId, int page});

final readerPageImageProvider = FutureProvider.family<Uint8List, PageRequest>((
  Ref ref,
  PageRequest req,
) {
  return ref.watch(readerRepositoryProvider).pageImage(req.bookId, req.page);
});

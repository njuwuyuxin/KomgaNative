import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/reader_repository.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
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
        // 页图/页列表落盘：看过的页断网还能翻回去。
        cache: ref.watch(httpCacheProvider),
      );
      ref.onDispose(komga.close);
      return KomgaReaderRepository(komga, ref.watch(progressSyncProvider));
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

/// 查"下一本"的键：书 id + 所属系列。
typedef NextBookQuery = ({String seriesId, String bookId});

/// 同一系列里的下一本（按服务端返回顺序，也就是卷号顺序）。
///
/// 返回 null 的四种情况都**正常**：当前是最后一本、书列表还没加载出来、
/// 离线且没有缓存、系列超过 100 本（列表只取前 100）。"下一本"是读完后的
/// 锦上添花，不能因为它让书末报错。
final nextBookProvider = FutureProvider.family<Book?, NextBookQuery>((
  Ref ref,
  NextBookQuery query,
) async {
  final page = await ref.watch(libraryRepositoryProvider).books(query.seriesId);
  final index = page.items.indexWhere((Book book) => book.id == query.bookId);
  if (index < 0 || index + 1 >= page.items.length) return null;
  return page.items[index + 1];
});

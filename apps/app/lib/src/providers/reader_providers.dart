import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/page_border_crop.dart';
import 'package:komga_native/src/data/page_edge_color.dart';
import 'package:komga_native/src/data/reader_repository.dart';
import 'package:komga_native/src/providers/komga_session_provider.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 系统相册 / 默认图片目录保存器：生产走原生通道，测试可替换为假实现。
final Provider<ImageSaver> imageSaverProvider = Provider<ImageSaver>(
  (Ref ref) => ChannelImageSaver(),
);

/// 阅读器仓库：复用共享 [komgaSessionProvider] 连接池（ARC-09）。
final Provider<ReaderRepository> readerRepositoryProvider =
    Provider<ReaderRepository>((Ref ref) {
      final komga = requireKomgaSession(ref, reason: '未连接服务器时不应打开阅读器');
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

/// 单页字节。**故意是 autoDispose**：Riverpod 3 默认不回收，页图一张几百 KB
/// 到 2 MB，读一本 200 页的书就等于把整本留在内存里（还会一直涨）。
/// 只有屏幕上正在看的那一屏需要持有字节；翻走的页交给仓库的 LRU（8 张）
/// 和 `ImageCache`（解码后的位图）兜着，翻回来仍然是秒开。
final readerPageImageProvider = FutureProvider.family<Uint8List, PageRequest>((
  Ref ref,
  PageRequest req,
) {
  return ref.watch(readerRepositoryProvider).pageImage(req.bookId, req.page);
}, isAutoDispose: true);

/// 一页的**页边主色**（动态背景用，UI-P1-5）。
///
/// 也是 autoDispose：它依赖页图字节，必须跟着一起回收——否则读一本 200 页的书，
/// 每一页的字节都会被这个 provider 一直持有（family 默认不回收）。
/// 翻回去重算一次很便宜（32px 解码 + 一千像素平均）。
final pageEdgeColorProvider = FutureProvider.family<RgbColor?, PageRequest>((
  Ref ref,
  PageRequest req,
) async {
  final bytes = await ref.watch(readerPageImageProvider(req).future);
  return pageEdgeColor(bytes);
}, isAutoDispose: true);

/// 一页左右两侧的页边色（沉浸式背景，UI-P3-7）；同样跟着页图回收。
final pageEdgeGradientProvider =
    FutureProvider.family<List<RgbColor>, PageRequest>((
      Ref ref,
      PageRequest req,
    ) async {
      final bytes = await ref.watch(readerPageImageProvider(req).future);
      return pageEdgeGradient(bytes);
    }, isAutoDispose: true);

/// 一页的边框裁剪比例（UI-P3-10）；只在用户开启"去白边"时才被读。
final pageBorderCropProvider = FutureProvider.family<BorderCrop?, PageRequest>((
  Ref ref,
  PageRequest req,
) async {
  final bytes = await ref.watch(readerPageImageProvider(req).future);
  return pageBorderCrop(bytes);
}, isAutoDispose: true);

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

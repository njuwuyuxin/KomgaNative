import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/page_border_crop.dart';
import 'package:yomu/src/data/page_edge_color.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 系统相册 / 默认图片目录保存器：生产走原生通道，测试可替换为假实现。
final Provider<ImageSaver> imageSaverProvider = Provider<ImageSaver>(
  (Ref ref) => ChannelImageSaver(),
);

/// 阅读器默认仓库（跟随当前激活内容源）；跨源阅读请经 [readerRepositoryForSourceProvider]
/// 按显式 `sourceKey` 寻址，避免嵌套 `ProviderScope` 作用域逃逸。
final Provider<ReaderRepository> readerRepositoryProvider =
    Provider<ReaderRepository>((Ref ref) {
      return ref.watch(activeSourceBundleProvider).reader;
    });

/// 按源寻址单本书的查询键。
typedef ReaderBookQuery = ({String? sourceKey, String bookId});

final readerBookProvider = FutureProvider.family<Book?, ReaderBookQuery>((
  Ref ref,
  ReaderBookQuery query,
) {
  final key = resolveEffectiveSourceKey(ref, query.sourceKey);
  return ref.watch(readerRepositoryForSourceProvider(key)).book(query.bookId);
});

/// 页列表（尺寸用于布局；页码 1 基）。
final readerPagesProvider =
    FutureProvider.family<List<PageInfo>, ReaderBookQuery>((
      Ref ref,
      ReaderBookQuery query,
    ) {
      final key = resolveEffectiveSourceKey(ref, query.sourceKey);
      return ref
          .watch(readerRepositoryForSourceProvider(key))
          .pages(query.bookId);
    });

/// 一页的图片字节。family 参数用 record，值相等即同一个 provider。
typedef PageRequest = ({String? sourceKey, String bookId, int page});

/// 单页字节。**故意是 autoDispose**：Riverpod 3 默认不回收，页图一张几百 KB
/// 到 2 MB，读一本 200 页的书就等于把整本留在内存里（还会一直涨）。
/// 只有屏幕上正在看的那一屏需要持有字节；翻走的页交给仓库的 LRU（8 张）
/// 和 `ImageCache`（解码后的位图）兜着，翻回来仍然是秒开。
final readerPageImageProvider = FutureProvider.family<Uint8List, PageRequest>((
  Ref ref,
  PageRequest req,
) {
  final key = resolveEffectiveSourceKey(ref, req.sourceKey);
  return ref
      .watch(readerRepositoryForSourceProvider(key))
      .pageImage(req.bookId, req.page);
}, isAutoDispose: true);

/// 单页低精度缩略图字节（服务端 300px JPEG，autoDispose）。
///
/// 供底栏缩略图滑条、跳页面板以及原图到达前的低清渐进占位使用：体积仅为原图的 1%–5%，
/// 且走仓库独立 LRU，不会把正在阅读的原图挤出内存。
final readerPageThumbnailProvider =
    FutureProvider.family<Uint8List, PageRequest>((Ref ref, PageRequest req) {
      final key = resolveEffectiveSourceKey(ref, req.sourceKey);
      return ref
          .watch(readerRepositoryForSourceProvider(key))
          .pageThumbnail(req.bookId, req.page);
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

/// 查"下一本"的键：所属源 + 系列 id + 书 id。
typedef NextBookQuery = ({String? sourceKey, String seriesId, String bookId});

/// 同一系列里的下一本（按服务端返回顺序，也就是卷号顺序）。
///
/// 返回 null 的四种情况都**正常**：当前是最后一本、书列表还没加载出来、
/// 离线且没有缓存、系列超过 100 本（列表只取前 100）。"下一本"是读完后的
/// 锦上添花，不能因为它让书末报错。
final nextBookProvider = FutureProvider.family<Book?, NextBookQuery>((
  Ref ref,
  NextBookQuery query,
) async {
  final key = resolveEffectiveSourceKey(ref, query.sourceKey);
  final page = await ref
      .watch(libraryRepositoryForSourceProvider(key))
      .books(query.seriesId);
  final index = page.items.indexWhere((Book book) => book.id == query.bookId);
  if (index < 0 || index + 1 >= page.items.length) return null;
  return page.items[index + 1];
});

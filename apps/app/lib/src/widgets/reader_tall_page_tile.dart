import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/widgets/reader_chrome.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 超高条漫长图（> 4096px）的分片 `ui.Image` 缓存与生命周期管理（LMB-02）。
///
/// 解码后立即按 [TallImageTile] 切为多张高度 ≤ 2048px 的独立子纹理，
/// 并立刻释放临时整图，避免超出 GPU `GL_MAX_TEXTURE_SIZE` 黑屏或整图常驻 OOM。
final class TallImageSliceCache {
  TallImageSliceCache({this.maxCachedPages = 4});

  final int maxCachedPages;
  final LinkedHashMap<int, List<ui.Image>> _pages =
      LinkedHashMap<int, List<ui.Image>>();
  final Map<int, Future<List<ui.Image>?>> _inFlight =
      <int, Future<List<ui.Image>?>>{};
  bool _disposed = false;

  /// 同步查询某页某个切片是否已就绪。
  ui.Image? peek(int pageIndex, int tileIndex) {
    final list = _pages.remove(pageIndex);
    if (list == null) return null;
    _pages[pageIndex] = list;
    if (tileIndex < 0 || tileIndex >= list.length) return null;
    return list[tileIndex];
  }

  /// 获取某页某个切片位图（同一页的多个切片并发请求会合并为一次解码切分）。
  Future<ui.Image?> acquire({
    required int pageIndex,
    required Uint8List bytes,
    required List<TallImageTile> tiles,
    required int tileIndex,
    required int targetDecodeWidth,
  }) async {
    if (_disposed || tiles.isEmpty) return null;
    final hit = peek(pageIndex, tileIndex);
    if (hit != null) return hit;

    final pending = _inFlight.putIfAbsent(
      pageIndex,
      () => _decodeAndSlice(
        bytes: bytes,
        tiles: tiles,
        targetDecodeWidth: targetDecodeWidth,
      ),
    );
    final result = await pending;
    unawaited(_inFlight.remove(pageIndex));

    if (result == null) return null;
    if (_disposed) {
      for (final img in result) {
        img.dispose();
      }
      return null;
    }

    final existing = _pages.remove(pageIndex);
    if (existing != null && !identical(existing, result)) {
      for (final img in existing) {
        img.dispose();
      }
    }
    _pages[pageIndex] = result;
    _evictIfNeeded();
    if (tileIndex < 0 || tileIndex >= result.length) return null;
    return result[tileIndex];
  }

  void _evictIfNeeded() {
    while (_pages.length > maxCachedPages) {
      final oldestKey = _pages.keys.first;
      final removed = _pages.remove(oldestKey);
      if (removed != null) {
        for (final img in removed) {
          img.dispose();
        }
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final list in _pages.values) {
      for (final img in list) {
        img.dispose();
      }
    }
    _pages.clear();
  }

  static Future<List<ui.Image>?> _decodeAndSlice({
    required Uint8List bytes,
    required List<TallImageTile> tiles,
    required int targetDecodeWidth,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? fullImage;
    final out = <ui.Image>[];
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final rawW = descriptor.width;
      final rawH = descriptor.height;
      if (rawW <= 0 || rawH <= 0) return null;

      final safeW = targetDecodeWidth.clamp(1, 2048).clamp(1, rawW);
      try {
        codec = await descriptor.instantiateCodec(targetWidth: safeW);
        final frame = await codec.getNextFrame();
        fullImage = frame.image;
      } on Object {
        codec?.dispose();
        codec = await descriptor.instantiateCodec(
          targetHeight: kTallImageTriggerHeight.clamp(1, rawH),
        );
        final frame = await codec.getNextFrame();
        fullImage = frame.image;
      }

      final decW = fullImage.width.toDouble();
      final decH = fullImage.height.toDouble();
      final paint = Paint()..filterQuality = FilterQuality.medium;

      for (final tile in tiles) {
        final srcTop = (tile.topFraction * decH).clamp(0.0, decH);
        final srcBottom = (tile.bottomFraction * decH).clamp(srcTop, decH);
        final sliceH = (srcBottom - srcTop).round().clamp(1, fullImage.height);
        final sliceW = fullImage.width.clamp(1, 2048);

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          fullImage,
          Rect.fromLTRB(0, srcTop, decW, srcBottom),
          Rect.fromLTWH(0, 0, sliceW.toDouble(), sliceH.toDouble()),
          paint,
        );
        final picture = recorder.endRecording();
        final sliceImg = await picture.toImage(sliceW, sliceH);
        picture.dispose();
        out.add(sliceImg);
      }
      return out;
    } on Object {
      for (final img in out) {
        img.dispose();
      }
      return null;
    } finally {
      fullImage?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// 渲染超高条漫长图中的单个纵向分片（LMB-02）。
class ReaderTallPageTile extends ConsumerStatefulWidget {
  const ReaderTallPageTile({
    required this.bookId,
    required this.pageIndex,
    required this.tile,
    required this.allTiles,
    required this.palette,
    required this.cache,
    required this.targetDecodeWidth,
    super.key,
  });

  final String bookId;
  final int pageIndex;
  final TallImageTile tile;
  final List<TallImageTile> allTiles;
  final ReaderPalette palette;
  final TallImageSliceCache cache;
  final int targetDecodeWidth;

  @override
  ConsumerState<ReaderTallPageTile> createState() => _ReaderTallPageTileState();
}

class _ReaderTallPageTileState extends ConsumerState<ReaderTallPageTile> {
  ui.Image? _image;
  Uint8List? _requestedBytes;

  void _ensureTile(Uint8List bytes) {
    final syncHit = widget.cache.peek(widget.pageIndex, widget.tile.index);
    if (syncHit != null) {
      _image = syncHit;
      _requestedBytes = bytes;
      return;
    }
    if (identical(_requestedBytes, bytes)) return;
    _requestedBytes = bytes;
    unawaited(
      widget.cache
          .acquire(
            pageIndex: widget.pageIndex,
            bytes: bytes,
            tiles: widget.allTiles,
            tileIndex: widget.tile.index,
            targetDecodeWidth: widget.targetDecodeWidth,
          )
          .then((ui.Image? img) {
            if (!mounted || img == null) return;
            setState(() => _image = img);
          }),
    );
  }

  @override
  void didUpdateWidget(ReaderTallPageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.tile.index != widget.tile.index ||
        oldWidget.bookId != widget.bookId) {
      _image = widget.cache.peek(widget.pageIndex, widget.tile.index);
      _requestedBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pageIndex + 1;
    final sourceKey =
        ScopedSourceScope.maybeOf(context) ??
        ref.watch(activeSourceProvider).sourceKey;
    final request = (sourceKey: sourceKey, bookId: widget.bookId, page: page);
    final repo = ref.watch(readerRepositoryForSourceProvider(sourceKey));
    final async = ref.watch(readerPageImageProvider(request));
    final bytes = async.value ?? repo.cachedPageImage(widget.bookId, page);
    final error = async.error;

    if (bytes != null) {
      _ensureTile(bytes);
      final img = _image;
      if (img != null) {
        return SizedBox.expand(
          key: Key('reader-tall-tile-${widget.pageIndex}-${widget.tile.index}'),
          child: RawImage(
            image: img,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        );
      }
      return SizedBox.expand(
        key: Key(
          'reader-tall-tile-loading-${widget.pageIndex}-${widget.tile.index}',
        ),
        child: widget.tile.index == 0
            ? Center(
                child: CircularProgressIndicator(
                  color: widget.palette.onBackgroundMuted,
                ),
              )
            : const SizedBox.shrink(),
      );
    }

    if (error != null) {
      if (widget.tile.index != 0) return const SizedBox.shrink();
      return Center(
        child: PageError(
          error: error,
          palette: widget.palette,
          onRetry: () => ref.invalidate(readerPageImageProvider(request)),
        ),
      );
    }

    if (widget.tile.index != 0) return const SizedBox.shrink();
    return Center(
      child: CircularProgressIndicator(
        key: Key('reader-page-loading-${widget.pageIndex}'),
        color: widget.palette.onBackgroundMuted,
      ),
    );
  }
}

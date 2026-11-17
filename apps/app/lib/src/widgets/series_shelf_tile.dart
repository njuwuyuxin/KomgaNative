import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 书架上的一个系列卡片：把"封面字节"翻译成 [SeriesTile] 认的 widget。
///
/// 关键点：**没有封面时必须把 `cover` 传成 null**，让 [SeriesTile] 画占位图；
/// 传一个空 widget 会把占位图顶掉，屏幕上就是一块白板。
class SeriesShelfTile extends ConsumerWidget {
  const SeriesShelfTile({required this.series, this.onTap, super.key});

  final Series series;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(seriesCoverProvider(series.id));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };

    return SeriesTile(
      series: series,
      onTap: onTap,
      cover: bytes == null || bytes.isEmpty
          ? null
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

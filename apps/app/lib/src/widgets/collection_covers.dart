import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集的封面拼贴（UI-02）：最多 4 张系列封面。
///
/// 为什么用 `seriesCoverProvider` 而不是新接口：收藏集本来就带着 `seriesIds`，
/// 封面走已有的 LRU 缓存，一次收藏集列表最多多取 4×N 张缩略图，
/// 而且第二屏再滚动时全是缓存命中。
class CollectionCovers extends StatelessWidget {
  const CollectionCovers({
    required this.collectionId,
    required this.name,
    required this.seriesIds,
    this.size = AppSizes.collectionCoverSize,
    super.key,
  });

  final String collectionId;
  final String name;
  final List<String> seriesIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ids = seriesIds.take(4).toList(growable: false);
    if (ids.isEmpty) {
      return _InitialBadge(name: name, size: size);
    }
    if (ids.length == 1) {
      return _Cover(seriesId: ids.first, size: size, flat: false);
    }
    // 2–4 张：两列网格。2 张时是上下两格，3 张时右下补一个首字母块。
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Column(
          children: <Widget>[
            for (var row = 0; row < 2; row++)
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (var col = 0; col < 2; col++)
                      Expanded(child: _cellFor(row * 2 + col, ids)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cellFor(int index, List<String> ids) {
    if (index < ids.length) {
      return _Cover(seriesId: ids[index], size: size, flat: true);
    }
    // 3 张封面时右下角空一格：补首字母块，比留白更像"卡"。
    return _InitialBadge(name: name, size: size, flat: true);
  }
}

class _Cover extends ConsumerWidget {
  const _Cover({
    required this.seriesId,
    required this.size,
    required this.flat,
  });

  final String seriesId;
  final double size;

  /// 拼贴内的格子不自己圆角，靠外层统一裁。
  final bool flat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(seriesCoverProvider(seriesId)).value;
    return SizedBox.expand(child: _paint(context, bytes));
  }

  Widget _paint(BuildContext context, Uint8List? bytes) {
    if (bytes == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );
    }
    return CoverImage(bytes: bytes);
  }
}

/// 没有封面时的首字母色块：颜色由名字的哈希决定，同一本书每次打开都是同一个色。
class _InitialBadge extends StatelessWidget {
  const _InitialBadge({
    required this.name,
    required this.size,
    this.flat = false,
  });

  final String name;
  final double size;

  /// 拼贴内的格子不自己圆角，靠外层统一裁。
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final hue = (name.hashCode.abs() % 360).toDouble();
    final color = HSLColor.fromAHSL(
      1,
      hue,
      dark ? 0.35 : 0.45,
      dark ? 0.32 : 0.55,
    ).toColor();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(flat ? 0 : AppRadii.sm),
      ),
      child: Text(
        initial,
        style: theme.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

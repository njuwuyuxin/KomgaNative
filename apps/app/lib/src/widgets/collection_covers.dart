import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
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
      // 必须自己钉死宽高：`_Cover` 内部是 `SizedBox.expand`，
      // 直接塞进 ListTile.leading 会横向撑满整行（实测把标题挤没了）。
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: _Cover(seriesId: ids.first, size: size, flat: false),
        ),
      );
    }
    // 2–4 张：2×2 网格，数量不足 4 张时其余槽位保持透明，不画占位图。
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
    return const SizedBox.shrink();
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
    final sourceKey = ScopedSourceScope.maybeOf(context);
    final bytes = ref
        .watch(seriesCoverProvider((sourceKey: sourceKey, id: seriesId)))
        .value;
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
  const _InitialBadge({required this.name, required this.size});

  final String name;
  final double size;

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
        borderRadius: BorderRadius.circular(AppRadii.sm),
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 解析"这一屏"的阅读器配色（UI-P1-5 动态背景）。
///
/// 背景选"动态"时，把这一屏每页的页边主色取平均（双页跨页就是两页的融合）；
/// 还没算出来时由 [ReaderPalette.resolve] 退回黑色，不会先闪一帧奇怪的颜色。
///
/// 单独成函数是为了让 `ReaderScreen` 只做编排——它已经贴着 350 行上限。
ReaderPalette resolveReaderPalette({
  required bool isEink,
  required ReaderConfig config,
  required ReaderLayout layout,
  required WidgetRef ref,
  required String bookId,
  String? sourceKey,
}) {
  if (isEink) {
    return ReaderPalette.resolve(isEink: true, choice: config.background);
  }
  if (config.background == ReaderBackgroundChoice.immersive) {
    final gradients = <List<RgbColor>>[
      for (final index in layout.spread)
        ref
                .watch(
                  pageEdgeGradientProvider((
                    sourceKey: sourceKey,
                    bookId: bookId,
                    page: index + 1,
                  )),
                )
                .value ??
            const <RgbColor>[],
    ];
    final merged = <RgbColor>[];
    for (var side = 0; side < 2; side++) {
      final color = averageColors(<RgbColor?>[
        for (final gradient in gradients)
          side < gradient.length ? gradient[side] : null,
      ]);
      if (color != null) merged.add(color);
    }
    return ReaderPalette.resolve(
      isEink: false,
      choice: ReaderBackgroundChoice.immersive,
      immersive: merged,
    );
  }
  if (config.background != ReaderBackgroundChoice.dynamic) {
    return ReaderPalette.resolve(isEink: isEink, choice: config.background);
  }
  final colors = <RgbColor?>[
    for (final index in layout.spread)
      ref
          .watch(
            pageEdgeColorProvider((
              sourceKey: sourceKey,
              bookId: bookId,
              page: index + 1,
            )),
          )
          .value,
  ];
  return ReaderPalette.resolve(
    isEink: false,
    choice: ReaderBackgroundChoice.dynamic,
    dynamic: averageColors(colors),
  );
}

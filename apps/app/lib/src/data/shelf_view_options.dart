import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 书架的呈现方式（UI-P2-7）。
enum ShelfView { grid, list }

/// 网格里的封面档位（UI-P2-7）。
///
/// 用"一列最宽多少"表达大小，而不是写死列数：手机 2–3 列、平板 5–7 列都是
/// 同一条规则算出来的，页面里仍然不需要判断"是不是平板"。
enum ShelfCoverSize {
  small(150),
  medium(190),
  large(260);

  const ShelfCoverSize(this.maxExtent);

  /// 单个单元格的最大宽度（逻辑像素）。
  final double maxExtent;

  /// 列表视图里的行封面：比网格小，跟"书行"的比例一致。
  Size get rowCover => switch (this) {
    small => const Size(36, 52),
    medium => AppSizes.rowCover,
    large => const Size(64, 92),
  };
}

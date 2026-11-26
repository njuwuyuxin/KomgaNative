part of 'series_tile.dart';

/// 选中封面时的方向性半透明轻纱：右上角（对勾附近）略深、左下角渐透。
class _SelectedCoverVeil extends StatelessWidget {
  const _SelectedCoverVeil({required this.eink, required this.dark});

  final bool eink;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (eink) {
      return ColoredBox(color: AppTheme.einkPaper.withValues(alpha: 0.32));
    }
    final primary = Theme.of(context).colorScheme.primary;
    final topRight = Color.lerp(
      Colors.black,
      primary,
      0.45,
    )!.withValues(alpha: dark ? 0.42 : 0.34);
    final bottomLeft = Color.lerp(
      Colors.black,
      primary,
      0.35,
    )!.withValues(alpha: dark ? 0.20 : 0.14);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[topRight, bottomLeft],
        ),
      ),
    );
  }
}

/// 已读/总数：半透明胶囊，压在封面右下角。
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.read, required this.total});

  final int read;
  final int total;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          '$read/$total',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 没有封面时的占位：渐变底 + 标题首字。
class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.color, required this.initial});

  final Color color;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, Color.lerp(color, Colors.black, 0.35)!],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.displayMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

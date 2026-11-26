import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 封面左上角的"未读本数"角标（LIB-02）。
///
/// 为什么放左上：右下角已经是"已读/总数"的进度角标，两个数字挤在一起
/// 读起来像一串。左上角只表示一件更紧急的事——这个系列还有几本没看。
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$count unread',
      excludeSemantics: true,
      child: Container(
        key: const Key('series-unread-badge'),
        constraints: const BoxConstraints(minWidth: AppSizes.minTouch / 2.5),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

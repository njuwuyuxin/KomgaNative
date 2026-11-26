import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:material_ui/material_ui.dart';

/// 书末卡片（UI-P1-7）：告诉用户"读完了"，并把下一步做成一个明确的动作。
///
/// 为什么不弹窗：弹窗会打断"翻到最后一页还想再看一眼"的动作，而且每次进阅读器
/// 都弹一次很烦。这条卡片常驻在底部 chrome 里，只在完成态出现。
///
/// 拿不到下一本时（最后一本 / 离线 / 书列表还没到）只显示"已读完"和"返回系列"，
/// **不报错**：这是锦上添花的能力，不能因为多一次列表请求把书末弄成错误页。
class ReaderFinishedCard extends ConsumerWidget {
  const ReaderFinishedCard({
    required this.palette,
    required this.onBack,
    this.nextBook,
    this.onNext,
    super.key,
  });

  final ReaderPalette palette;
  final Book? nextBook;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final motion = AppMotion.of(context);
    final next = nextBook;
    final back = TextButton(
      key: const Key('reader-back-series'),
      style: TextButton.styleFrom(foregroundColor: palette.muted),
      onPressed: onBack,
      child: Text(l10n.seriesButton),
    );

    // 入场：淡入 + 轻微上浮。墨水屏 / 减少动态效果时时长为 0，等价于直接到位。
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.standard,
      curve: motion.standardCurve,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, AppSpacing.sm * (1 - t)),
          child: child,
        ),
      ),
      child: Padding(
        key: const Key('reader-finished'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: next == null
            ? _FinishedRow(palette: palette, back: back, label: l10n.finished)
            : _NextBook(
                palette: palette,
                next: next,
                back: back,
                onNext: onNext,
                finishedLabel: l10n.finished,
                nextLabel: l10n.nextBook,
              ),
      ),
    );
  }
}

/// 没有下一本时的精简版：一个勾 + "读完" + 返回系列。
class _FinishedRow extends StatelessWidget {
  const _FinishedRow({
    required this.palette,
    required this.back,
    required this.label,
  });

  final ReaderPalette palette;
  final Widget back;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.check_circle_outline,
          size: AppSizes.iconSm,
          color: palette.foreground,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.foreground),
          ),
        ),
        back,
      ],
    );
  }
}

/// 有下一本时的卡片：封面 + 书名 + 卷号，按钮是"继续阅读"（主）和"返回系列"（次）。
class _NextBook extends ConsumerWidget {
  const _NextBook({
    required this.palette,
    required this.next,
    required this.back,
    required this.finishedLabel,
    required this.nextLabel,
    this.onNext,
  });

  final ReaderPalette palette;
  final Book next;
  final Widget back;
  final String finishedLabel;
  final String nextLabel;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = AppTypography.of(context);
    final sourceKey = ScopedSourceScope.maybeOf(context) ?? next.sourceKey;
    final cover = ref
        .watch(bookCoverProvider((sourceKey: sourceKey, id: next.id)))
        .value;
    final volume = next.number.isEmpty ? null : '#${next.number}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            ClipPath(
              clipper: ShapeBorderClipper(
                shape: AppShapes.cover(eink: palette.isEink),
              ),
              child: SizedBox.fromSize(
                size: AppSizes.rowCover,
                child: cover == null
                    ? ColoredBox(color: palette.outline)
                    : CoverImage(bytes: cover),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.check_circle_outline,
                        size: AppSizes.iconXs,
                        color: palette.muted,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        finishedLabel,
                        style: typography.label.copyWith(color: palette.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    next.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typography.headline.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                  if (volume != null)
                    Text(
                      volume,
                      style: typography.caption.copyWith(color: palette.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            back,
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              key: const Key('reader-next-book'),
              onPressed: onNext,
              child: Text(nextLabel),
            ),
          ],
        ),
      ],
    );
  }
}

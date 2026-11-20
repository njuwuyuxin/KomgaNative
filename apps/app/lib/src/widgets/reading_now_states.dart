import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// "正在读"页的空态、骨架与错误提示组件（ARC-12 拆分独立文件）。
class EmptyContinueCard extends StatelessWidget {
  const EmptyContinueCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: StatusView(
        key: const Key('reading-now-empty'),
        icon: Icons.auto_stories_outlined,
        title: l10n.readingNowEmpty,
        message: l10n.readingNowEmptyHint,
      ),
    );
  }
}

class ContinueSkeleton extends StatelessWidget {
  const ContinueSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GlassSurface(
        key: const Key('reading-now-continue-skeleton'),
        shape: AppShapes.of(context, AppShapes.panel),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AppSizes.shelfCover.width,
                height: AppSizes.shelfCover.height,
                child: const SkeletonBox(),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _SkeletonLine(
                      widthFactor: 0.45,
                      height: AppSizes.skeletonLineSm,
                    ),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonLine(widthFactor: 0.9),
                    SizedBox(height: AppSpacing.sm),
                    _SkeletonLine(
                      widthFactor: 0.7,
                      height: AppSizes.skeletonLineSm,
                    ),
                    SizedBox(height: AppSpacing.md),
                    _SkeletonLine(
                      widthFactor: 0.5,
                      height: AppSizes.skeletonLineLg,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContinueFailure extends StatelessWidget {
  const ContinueFailure({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: StatusView(
        key: const Key('reading-now-error'),
        icon: Icons.cloud_off_outlined,
        title: l10n.readingNowLoadFailed,
        message: l10n.readingNowLoadFailedHint,
        actionLabel: l10n.retry,
        onAction: () => unawaited(onRetry()),
      ),
    );
  }
}

class RefreshFailureHint extends StatelessWidget {
  const RefreshFailureHint({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: const Key('reading-now-refresh-failed'),
      children: <Widget>[
        Icon(
          Icons.cloud_off_outlined,
          size: AppSizes.iconSm,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            l10n.readingNowRefreshFailed,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          onPressed: () => unawaited(onRetry()),
          child: Text(l10n.retry),
        ),
      ],
    );
  }
}

class ShelfRowSkeleton extends StatelessWidget {
  const ShelfRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SizedBox(
        key: const Key('reading-now-shelf-skeleton'),
        height: AppSizes.shelfRowHeight + AppSpacing.md,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: 3,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) => SizedBox(
            width: AppSizes.shelfCover.width + AppSpacing.xl,
            child: const SkeletonBox(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.widthFactor,
    this.height = AppSizes.skeletonLineLg,
  });

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SizedBox(height: height, child: const SkeletonBox()),
    );
  }
}

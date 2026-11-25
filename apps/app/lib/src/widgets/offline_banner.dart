import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 底部悬浮离线提示浮层：通过 `Stack` 覆盖在内容上方，出现/消失不改变文档流布局。
///
/// 位置直接对齐 `MediaQuery.paddingOf(context).bottom`：
/// - 在 `AdaptiveShell`（`Scaffold(extendBody: true, bottomNavigationBar: FloatingNavBar)`）下，
///   Flutter 已把导航条高度折算进 `padding.bottom`，因此自动浮在导航条正上方 `AppSpacing.sm`；
/// - 在平板侧边导航或无底栏的详情页中，自动浮在底部安全区（或批量操作栏）上方。
class OfflineOverlay extends StatelessWidget {
  const OfflineOverlay({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final bottomOffset = MediaQuery.paddingOf(context).bottom + AppSpacing.sm;
    return Positioned(
      left: AppSpacing.md,
      right: AppSpacing.md,
      bottom: bottomOffset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: OfflineBanner(onRetry: onRetry),
      ),
    );
  }
}

/// 离线提示胶囊。
///
/// 数据来源是传输层经 `ConnectivityFilter` 滤波后的观测结果（`DriftHttpCache.offline`），
/// 避免弱网下偶发超时或并发缩略图失败导致的频繁闪动。
///
/// [onRetry] 由页面决定重试什么（书架刷新、系列重取）；不给就只提示。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);
    final motion = AppMotion.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: offline,
      builder: (BuildContext context, bool isOffline, Widget? _) {
        final Widget content = isOffline
            ? _OfflinePill(
                onRetry: onRetry == null
                    ? null
                    : () {
                        ref.read(httpCacheProvider).markRetryRequested();
                        onRetry!();
                      },
              )
            : const SizedBox.shrink(key: ValueKey<String>('offline-hidden'));

        if (!motion.enabled) return content;

        return AnimatedSwitcher(
          duration: motion.quick,
          reverseDuration: motion.quick,
          switchInCurve: motion.standardCurve,
          switchOutCurve: motion.exitCurve,
          transitionBuilder: (Widget child, Animation<double> animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: content,
        );
      },
    );
  }
}

class _OfflinePill extends StatelessWidget {
  const _OfflinePill({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizes.formMaxWidth),
      child: GlassSurface(
        key: const Key('offline-banner'),
        shape: const StadiumBorder(),
        shadows: AppShadows.card,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            onRetry != null ? AppSpacing.xs : AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.cloud_off_outlined,
                size: AppSizes.iconXs,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  l10n.offlineSavedContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  style: TextButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                  onPressed: onRetry,
                  child: Text(l10n.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

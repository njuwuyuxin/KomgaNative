import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 离线提示条。
///
/// 数据来源是传输层的真实观测（`DriftHttpCache.offline`），不是猜的网络状态：
/// 只有"刚才那次请求失败了"才会出现，网络一恢复（任意 GET/PATCH 成功）就消失。
///
/// [onRetry] 由页面决定重试什么（书架刷新、系列重取）；不给就只提示。
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({this.onRetry, super.key});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: offline,
      builder: (BuildContext context, bool isOffline, Widget? _) {
        if (!isOffline) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final foreground = theme.colorScheme.onSecondaryContainer;
        return Material(
          key: const Key('offline-banner'),
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.cloud_off_outlined, size: 16, color: foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Offline · showing saved content',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        );
      },
    );
  }
}

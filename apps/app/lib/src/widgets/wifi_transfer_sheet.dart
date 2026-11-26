import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/wifi_transfer_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 弹出内置局域网 HTTP Wi-Fi 传书面板（打开自动启服，关闭自动停服释放端口，LMB-07）。
Future<void> showWifiTransferSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext context) {
      final theme = Theme.of(context);
      final eink = AppTheme.isEink(theme);
      return FrostedSurface(
        kind: AppMaterialKind.sheet,
        material: AppMaterial.resolve(
          AppMaterialKind.sheet,
          eink: eink,
          dark: theme.brightness == Brightness.dark,
        ),
        shape: AppShapes.sheet(eink: eink),
        child: const Material(
          type: MaterialType.transparency,
          child: WifiTransferSheet(),
        ),
      );
    },
  );
  // 关闭面板后自动停服，避免后台长期挂起开放端口。
  await container.read(wifiTransferProvider.notifier).stop();
}

class WifiTransferSheet extends ConsumerStatefulWidget {
  const WifiTransferSheet({super.key});

  @override
  ConsumerState<WifiTransferSheet> createState() => _WifiTransferSheetState();
}

class _WifiTransferSheetState extends ConsumerState<WifiTransferSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(wifiTransferProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typography = AppTypography.of(context);
    final state = ref.watch(wifiTransferProvider);
    final controller = ref.read(wifiTransferProvider.notifier);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          key: const Key('wifi-transfer-sheet'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.wifi_tethering),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.wifiTransferTitle,
                      style: typography.headline,
                    ),
                  ),
                  IconButton(
                    key: const Key('wifi-transfer-close'),
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.wifiTransferHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _AddressCard(state: state, l10n: l10n),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                key: const Key('wifi-transfer-pin-toggle'),
                contentPadding: EdgeInsets.zero,
                value: state.pinEnabled,
                onChanged: controller.setPinEnabled,
                title: Text(l10n.wifiTransferPinToggle),
                subtitle: Text(
                  state.pinEnabled
                      ? l10n.wifiTransferPinValue(state.pin)
                      : l10n.wifiTransferPinHint,
                ),
                secondary: state.pinEnabled
                    ? IconButton(
                        key: const Key('wifi-transfer-pin-refresh'),
                        tooltip: l10n.wifiTransferPinRefresh,
                        icon: const Icon(Icons.refresh),
                        onPressed: controller.regeneratePin,
                      )
                    : const Icon(Icons.lock_outline),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('wifi-transfer-toggle-btn'),
                      onPressed: state.starting
                          ? null
                          : () => unawaited(
                              state.running
                                  ? controller.stop()
                                  : controller.start(),
                            ),
                      icon: Icon(
                        state.running
                            ? Icons.stop_circle_outlined
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        state.running
                            ? l10n.wifiTransferStop
                            : l10n.wifiTransferStart,
                      ),
                    ),
                  ),
                ],
              ),
              if (state.activeFileName != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: AppSizes.iconSm,
                      height: AppSizes.iconSm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.wifiTransferReceiving(state.activeFileName!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (state.logs.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.wifiTransferReceivedCount(state.receivedCount),
                  style: typography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final log in state.logs.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      log.kind == WifiTransferEventKind.imported
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: log.kind == WifiTransferEventKind.imported
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    title: Text(
                      log.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: log.errorDetail != null
                        ? Text(log.errorDetail!)
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.state, required this.l10n});

  final WifiTransferState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typography = AppTypography.of(context);
    final primaryUrl = state.urls.isNotEmpty ? state.urls.first : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: state.starting
            ? const Center(child: CircularProgressIndicator())
            : primaryUrl == null
            ? Text(
                state.error ?? l10n.wifiTransferStopped,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          l10n.wifiTransferUrlLabel,
                          style: typography.caption.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        SelectableText(
                          primaryUrl,
                          key: const Key('wifi-transfer-url'),
                          style: typography.progressNumber.copyWith(
                            fontSize: theme.textTheme.titleMedium?.fontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('wifi-transfer-copy'),
                    tooltip: l10n.wifiTransferCopyUrl,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: primaryUrl)),
                      );
                      ScaffoldMessenger.maybeOf(context)
                        ?..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text(l10n.wifiTransferCopied)),
                        );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

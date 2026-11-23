import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/screens/collections_tab.dart';
import 'package:komga_native/src/screens/readlists_tab.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集 / 阅读列表入口（UI-P3-8 / ARC-12 拆分子标签页）。
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen>
    with TickerProviderStateMixin {
  TabController? _tab;
  TabController? _pendingDispose;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = AppMotion.of(context).standard;
    final current = _tab;
    if (current == null) {
      _tab = TabController(length: 2, vsync: this, animationDuration: duration);
      return;
    }
    if (current.animationDuration == duration) return;
    final next = TabController(
      length: 2,
      initialIndex: current.index,
      vsync: this,
      animationDuration: duration,
    );
    _tab = next;
    _pendingDispose?.dispose();
    _pendingDispose = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingDispose == current) {
        _pendingDispose = null;
        current.dispose();
      }
    });
  }

  @override
  void dispose() {
    _pendingDispose?.dispose();
    _pendingDispose = null;
    _tab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tab = _tab!;
    final topInset =
        MediaQuery.paddingOf(context).top + AppSizes.glassHeaderClearance;

    return Scaffold(
      body: GlassPageBackground(
        child: Stack(
          children: <Widget>[
            TabBarView(
              controller: tab,
              children: <Widget>[
                CollectionsTab(topPadding: topInset),
                ReadListsTab(topPadding: topInset),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: GlassHeader(
                    bar: AnimatedBuilder(
                      animation: tab,
                      builder: (BuildContext context, _) =>
                          GlassSegmentedControl<int>(
                            segments: <GlassSegment<int>>[
                              GlassSegment<int>(
                                value: 0,
                                label: l10n.collectionsTab,
                              ),
                              GlassSegment<int>(
                                value: 1,
                                label: l10n.readListsTab,
                              ),
                            ],
                            selected: tab.index,
                            position: tab.animation,
                            onSelected: tab.animateTo,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CollectionsTabLoading extends StatelessWidget {
  const CollectionsTabLoading({required this.topPadding, super.key});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class CollectionsTabError extends StatelessWidget {
  const CollectionsTabError({
    required this.topPadding,
    required this.message,
    required this.onRetry,
    super.key,
  });

  final double topPadding;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              GlassPillButton(
                label: l10n.retry,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionsTabEmpty extends StatelessWidget {
  const CollectionsTabEmpty({
    required this.topPadding,
    required this.icon,
    required this.text,
    super.key,
  });

  final double topPadding;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: AppSizes.iconLg,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(text, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

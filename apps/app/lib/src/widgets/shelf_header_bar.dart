import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/shelf_query_buttons.dart';
import 'package:material_ui/material_ui.dart';

part 'shelf_header_actions.dart';

/// 书架顶部悬浮栏：在「浏览搜索」与「管理书籍」两态之间原地形变过渡。
///
/// 三个视觉槽位保持一一对应，让管理态按钮像由原按钮形变而来：
/// 1. 左侧胶囊：搜索栏 ↔「管理书籍」标题胶囊（高度 44 ↔ 52 平滑舒展）；
/// 2. 中间圆球：管理书籍入口（checklist）↔ 退出管理（close），旋转并带液态脉冲；
/// 3. 右侧三格胶囊：排序 / 筛选 / 视图 ↔ 全标已读 / 全标未读 / 收藏集，交错旋变形变。
class ShelfHeaderBar extends StatefulWidget {
  const ShelfHeaderBar({
    required this.selecting,
    required this.selectedCount,
    required this.batchBusy,
    required this.searchController,
    required this.onSearchChanged,
    required this.onEnterSelection,
    required this.onExitSelection,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onAddToCollection,
    super.key,
  });

  final bool selecting;
  final int selectedCount;
  final bool batchBusy;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onEnterSelection;
  final VoidCallback onExitSelection;
  final Future<void> Function() onMarkRead;
  final Future<void> Function() onMarkUnread;
  final Future<void> Function() onAddToCollection;

  @override
  State<ShelfHeaderBar> createState() => _ShelfHeaderBarState();
}

class _ShelfHeaderBarState extends State<ShelfHeaderBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.selecting ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant ShelfHeaderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selecting == widget.selecting) return;
    if (widget.selecting) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _controller.value = widget.selecting ? 1 : 0;
      return;
    }
    _controller.duration = motion.standard;
    _controller.reverseDuration = motion.standard;
    if (widget.selecting) {
      unawaited(_controller.forward());
    } else {
      unawaited(_controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final motion = AppMotion.of(context);
    final batchDisabled = widget.batchBusy || widget.selectedCount == 0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final raw = _controller.value;
        final easeT = motion.standardCurve.transform(raw);
        final springT = motion.emphasizedCurve.transform(raw);
        return Row(
          children: <Widget>[
            Expanded(
              child: _MorphingLeadCapsule(
                raw: raw,
                easeT: easeT,
                springT: springT,
                searchController: widget.searchController,
                onSearchChanged: widget.onSearchChanged,
                l10n: l10n,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _MorphingToggleOrb(
              raw: raw,
              easeT: easeT,
              selecting: widget.selecting,
              onEnter: widget.onEnterSelection,
              onExit: widget.onExitSelection,
              l10n: l10n,
            ),
            const SizedBox(width: AppSpacing.xs),
            _MorphingActionsCapsule(
              raw: raw,
              easeT: easeT,
              disabled: batchDisabled,
              onMarkRead: widget.onMarkRead,
              onMarkUnread: widget.onMarkUnread,
              onAddToCollection: widget.onAddToCollection,
              l10n: l10n,
            ),
          ],
        );
      },
    );
  }
}

/// 左侧胶囊：常态为 `GlassSearchField`（高 44），管理态舒展为「管理书籍」胶囊（高 52）。
class _MorphingLeadCapsule extends StatelessWidget {
  const _MorphingLeadCapsule({
    required this.raw,
    required this.easeT,
    required this.springT,
    required this.searchController,
    required this.onSearchChanged,
    required this.l10n,
  });

  final double raw;
  final double easeT;
  final double springT;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    if (raw == 0) {
      return GlassSearchField(
        key: const Key('shelf-search-field'),
        controller: searchController,
        hintText: l10n.searchSeriesHint,
        clearLabel: l10n.closeSearch,
        onChanged: onSearchChanged,
      );
    }

    final theme = Theme.of(context);
    final titleStyle = AppTypography.of(context).headline
        .copyWith(fontSize: theme.textTheme.bodyLarge?.fontSize);
    final titleContent = Padding(
      key: raw == 1 ? const Key('shelf-selection-bar') : null,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          l10n.manageBooks,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
      ),
    );

    if (raw == 1) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: GlassSurface(
          shape: AppShapes.of(context, AppShapes.bar),
          child: SizedBox(height: AppSizes.glassOrb, child: titleContent),
        ),
      );
    }

    final height = lerpDouble(
      AppSizes.glassSearchHeight,
      AppSizes.glassOrb,
      springT,
    )!.clamp(AppSizes.glassSearchHeight, AppSizes.glassHeaderHeight);
    final outP = (1.0 - easeT / 0.45).clamp(0.0, 1.0);
    final inP = ((easeT - 0.35) / 0.65).clamp(0.0, 1.0);
    final muted = theme.colorScheme.onSurfaceVariant;
    final query = searchController.text;

    return GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      child: SizedBox(
        height: height,
        child: ClipRect(
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: <Widget>[
              if (outP > 0)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: outP,
                      child: Transform.translate(
                        offset: Offset(-(1 - outP) * AppSpacing.sm, 0),
                        child: Transform.scale(
                          scale: 0.94 + 0.06 * outP,
                          alignment: AlignmentDirectional.centerStart,
                          child: Row(
                            children: <Widget>[
                              SizedBox(
                                width: AppSizes.glassSearchHeight,
                                height: AppSizes.glassSearchHeight,
                                child: Icon(
                                  Icons.search,
                                  size: AppSizes.iconMd,
                                  color: muted,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  query.isEmpty ? l10n.searchSeriesHint : query,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: query.isEmpty ? muted : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (inP > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: inP,
                    child: Transform.translate(
                      offset: Offset((1 - inP) * AppSpacing.sm, 0),
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * inP,
                        alignment: AlignmentDirectional.centerStart,
                        child: titleContent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

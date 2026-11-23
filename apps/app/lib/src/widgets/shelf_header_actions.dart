part of 'shelf_header_bar.dart';

/// 中间独立玻璃圆球：管理书籍按钮（checklist）↔ 退出管理（close）原地形变。
class _MorphingToggleOrb extends StatelessWidget {
  const _MorphingToggleOrb({
    required this.raw,
    required this.easeT,
    required this.selecting,
    required this.onEnter,
    required this.onExit,
    required this.l10n,
  });

  final double raw;
  final double easeT;
  final bool selecting;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final normalColors = GlassControlColors.resolve(context);
    final selectedColors = GlassControlColors.resolve(context, selected: true);
    final fill = Color.lerp(Colors.transparent, selectedColors.fill, easeT);
    final label = selecting ? l10n.cancel : l10n.selectSeries;
    final buttonKey = raw == 1
        ? const Key('shelf-selection-close')
        : (raw == 0 ? const Key('shelf-select-button') : null);

    void handleTap() {
      unawaited(AppHaptics.selection());
      if (selecting) {
        onExit();
      } else {
        onEnter();
      }
    }

    Widget iconLayer;
    if (raw == 0) {
      iconLayer = Icon(
        Icons.checklist,
        size: AppSizes.iconLg,
        color: normalColors.foreground,
      );
    } else if (raw == 1) {
      iconLayer = Icon(
        Icons.close,
        size: AppSizes.iconLg,
        color: selectedColors.foreground,
      );
    } else {
      final outP = (1.0 - easeT / 0.55).clamp(0.0, 1.0);
      final inP = ((easeT - 0.40) / 0.60).clamp(0.0, 1.0);
      iconLayer = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (outP > 0)
            Opacity(
              opacity: outP,
              child: Transform.rotate(
                angle: (1 - outP) * (math.pi / 2),
                child: Transform.scale(
                  scale: 0.40 + 0.60 * outP,
                  child: Icon(
                    Icons.checklist,
                    size: AppSizes.iconLg,
                    color: normalColors.foreground,
                  ),
                ),
              ),
            ),
          if (inP > 0)
            Opacity(
              opacity: inP,
              child: Transform.rotate(
                angle: -(1 - inP) * (math.pi / 2),
                child: Transform.scale(
                  scale: 0.40 + 0.60 * inP,
                  child: Icon(
                    Icons.close,
                    size: AppSizes.iconLg,
                    color: selectedColors.foreground,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    Widget orb = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: handleTap,
      child: GlassSurface(
        shape: const StadiumBorder(),
        child: SizedBox(
          width: AppSizes.glassOrb,
          height: AppSizes.glassOrb,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: fill ?? Colors.transparent,
            ),
            child: Center(child: iconLayer),
          ),
        ),
      ),
    );

    if (raw > 0 && raw < 1) {
      final pulse = 1.0 - 0.08 * math.sin(math.pi * easeT);
      orb = Transform.scale(scale: pulse, child: orb);
    }

    return Semantics(
      key: buttonKey,
      container: true,
      button: true,
      selected: selecting,
      label: label,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: PressableScale(child: orb),
        ),
      ),
    );
  }
}

/// 右侧三格液态玻璃胶囊：排序 / 筛选 / 视图 ↔ 全标已读 / 全标未读 / 收藏集。
class _MorphingActionsCapsule extends StatelessWidget {
  const _MorphingActionsCapsule({
    required this.raw,
    required this.easeT,
    required this.disabled,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onAddToCollection,
    required this.l10n,
  });

  final double raw;
  final double easeT;
  final bool disabled;
  final Future<void> Function() onMarkRead;
  final Future<void> Function() onMarkUnread;
  final Future<void> Function() onAddToCollection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final readAction = GlassBarAction(
      key: const Key('shelf-batch-read'),
      icon: Icons.done_all,
      label: l10n.markAllRead,
      subdued: false,
      onPressed: disabled ? null : () => unawaited(onMarkRead()),
    );
    final unreadAction = GlassBarAction(
      key: const Key('shelf-batch-unread'),
      icon: Icons.remove_done,
      label: l10n.markAllUnread,
      subdued: false,
      onPressed: disabled ? null : () => unawaited(onMarkUnread()),
    );
    final collectionAction = GlassBarAction(
      key: const Key('shelf-batch-collection'),
      icon: Icons.collections_bookmark_outlined,
      label: l10n.batchAddToCollection,
      subdued: false,
      onPressed: disabled ? null : () => unawaited(onAddToCollection()),
    );

    final row = Row(
      key: raw == 1 ? const Key('shelf-batch-bar') : null,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _MorphingActionSlot(
          raw: raw,
          start: 0.00,
          end: 0.80,
          normal: const ShelfSortButton(),
          batch: readAction,
        ),
        _MorphingActionSlot(
          raw: raw,
          start: 0.10,
          end: 0.90,
          normal: const ShelfFilterButton(),
          batch: unreadAction,
        ),
        _MorphingActionSlot(
          raw: raw,
          start: 0.20,
          end: 1.00,
          normal: const ShelfViewButton(),
          batch: collectionAction,
        ),
      ],
    );

    Widget capsule = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: GlassSurface(
        shape: AppShapes.of(context, AppShapes.bar),
        child: SizedBox(
          height: AppSizes.glassOrb,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: row,
          ),
        ),
      ),
    );

    if (raw > 0 && raw < 1) {
      final wave = math.sin(math.pi * easeT);
      capsule = Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(
          1.0 - 0.04 * wave,
          1.0 + 0.03 * wave,
          1.0,
        ),
        child: capsule,
      );
    }

    return capsule;
  }
}

/// 单个 44×44 槽位的旋变形变器：按交错区间把旧按钮拧转缩放成新按钮。
class _MorphingActionSlot extends StatelessWidget {
  const _MorphingActionSlot({
    required this.raw,
    required this.start,
    required this.end,
    required this.normal,
    required this.batch,
  });

  final double raw;
  final double start;
  final double end;
  final Widget normal;
  final Widget batch;

  @override
  Widget build(BuildContext context) {
    if (raw == 0) return normal;
    if (raw == 1) return batch;

    final local = Curves.easeInOutCubic.transform(
      ((raw - start) / (end - start)).clamp(0.0, 1.0),
    );
    final outP = (1.0 - local / 0.55).clamp(0.0, 1.0);
    final inP = ((local - 0.40) / 0.60).clamp(0.0, 1.0);

    return SizedBox(
      width: GlassBarAction.size,
      height: GlassBarAction.size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (outP > 0)
            IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: outP,
                  child: Transform.rotate(
                    angle: -(1 - outP) * 0.55,
                    child: Transform.scale(
                      scale: 0.45 + 0.55 * outP,
                      child: normal,
                    ),
                  ),
                ),
              ),
            ),
          if (inP > 0)
            IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: inP,
                  child: Transform.rotate(
                    angle: (1 - inP) * 0.55,
                    child: Transform.scale(
                      scale: 0.45 + 0.55 * inP,
                      child: batch,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

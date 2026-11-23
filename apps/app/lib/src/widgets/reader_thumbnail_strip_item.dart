part of 'reader_thumbnail_strip.dart';

enum _PageAction { share, group }

Future<void> _showThumbnailPageActions(
  BuildContext context, {
  required ReaderPalette palette,
  required int page,
  required Future<void> Function(int page)? onSharePage,
  required ValueChanged<int>? onGroupFrom,
}) async {
  final l10n = AppLocalizations.of(context);
  final action = await showModalBottomSheet<_PageAction>(
    context: context,
    backgroundColor: palette.background,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onSharePage != null)
            ListTile(
              key: const Key('reader-page-share'),
              leading: Icon(Icons.ios_share, color: palette.foreground),
              title: Text(
                l10n.sharePage,
                style: TextStyle(color: palette.foreground),
              ),
              onTap: () => Navigator.of(context).pop(_PageAction.share),
            ),
          if (onGroupFrom != null)
            ListTile(
              key: const Key('reader-page-group'),
              leading: Icon(
                Icons.grid_view_outlined,
                color: palette.foreground,
              ),
              title: Text(
                l10n.groupFromPage,
                style: TextStyle(color: palette.foreground),
              ),
              onTap: () => Navigator.of(context).pop(_PageAction.group),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _PageAction.share:
      await onSharePage?.call(page);
    case _PageAction.group:
      onGroupFrom?.call(page);
  }
}

class _StripGrabber extends StatelessWidget {
  const _StripGrabber({required this.palette, required this.onTap});

  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('reader-thumb-grabber'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.muted.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: SizedBox(
              width: AppSizes.grabber.width,
              height: AppSizes.grabber.height,
            ),
          ),
        ),
      ),
    );
  }
}

class _StripThumb extends StatelessWidget {
  const _StripThumb({
    required this.bookId,
    required this.page,
    required this.label,
    required this.current,
    required this.palette,
    required this.width,
    required this.height,
    required this.horizontalPadding,
    required this.cacheWidth,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final String bookId;
  final int page;
  final String label;
  final bool current;
  final ReaderPalette palette;
  final double width;
  final double height;
  final double horizontalPadding;
  final int cacheWidth;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.xs);
    return Semantics(
      container: true,
      button: true,
      selected: current,
      label: label,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: radius,
                    border: Border.all(
                      color: current ? palette.foreground : palette.outline,
                      width: current
                          ? AppSizes.hairline * 2
                          : AppSizes.hairline,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: PageThumbnailImage(
                      bookId: bookId,
                      page: page,
                      palette: palette,
                      cacheWidth: cacheWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

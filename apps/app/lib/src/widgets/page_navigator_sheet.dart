import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/page_thumbnail.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 页缩略图面板的选择结果。
typedef PageNavigatorChoice = ({int page, bool groupFrom});

/// 缩略图跳页面板。
///
/// 走 Komga 页级缩略图端点 `/api/v1/books/{id}/pages/{n}/thumbnail`（长边 300px JPEG）
/// 并配合 `cacheWidth` 降采样，网格懒构建，仅请求可见项。
///
/// 双页模式下长按某一页 = "从这一页开始重新分组"（UI-P3-5），通过
/// [onGroupFrom] 回传；不传时没有长按行为。
Future<void> showPageNavigator(
  BuildContext context, {
  required String bookId,
  required int total,
  required int currentPage,
  required ReaderPalette palette,
  required ValueChanged<int> onJump,
  ValueChanged<int>? onGroupFrom,
}) async {
  final choice = await showModalBottomSheet<PageNavigatorChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.background,
    builder: (BuildContext context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: PageNavigatorSheet(
        bookId: bookId,
        total: total,
        currentPage: currentPage,
        palette: palette,
        allowGroup: onGroupFrom != null,
      ),
    ),
  );
  if (choice == null) return;
  if (choice.groupFrom && onGroupFrom != null) {
    onGroupFrom(choice.page);
  } else {
    onJump(choice.page);
  }
}

class PageNavigatorSheet extends StatelessWidget {
  const PageNavigatorSheet({
    required this.bookId,
    required this.total,
    required this.currentPage,
    required this.palette,
    this.allowGroup = false,
    super.key,
  });

  final String bookId;
  final int total;
  final int currentPage;
  final ReaderPalette palette;

  /// 双页模式才允许长按重新分组。
  final bool allowGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  l10n.pagesTitle,
                  style: AppTypography.of(context).headline
                      .copyWith(color: palette.foreground),
                ),
                const Spacer(),
                Text(
                  l10n.readerPageOf(currentPage, total),
                  style: TextStyle(color: palette.muted),
                ),
                IconButton(
                  key: const Key('page-navigator-close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  color: palette.foreground,
                  tooltip: l10n.close,
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              key: const Key('page-navigator-grid'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120,
                childAspectRatio: 0.66,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
              ),
              itemCount: total,
              itemBuilder: (BuildContext context, int index) {
                final page = index + 1;
                return _PageThumbnail(
                  key: Key('page-thumb-$page'),
                  bookId: bookId,
                  page: page,
                  current: page == currentPage,
                  palette: palette,
                  onLongPress: allowGroup
                      ? () =>
                            Navigator.of(context)
                                .pop((page: page, groupFrom: true))
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PageThumbnail extends ConsumerWidget {
  const _PageThumbnail({
    required this.bookId,
    required this.page,
    required this.current,
    required this.palette,
    this.onLongPress,
    super.key,
  });

  final String bookId;
  final int page;
  final bool current;
  final ReaderPalette palette;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => Navigator.of(context).pop((page: page, groupFrom: false)),
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(
            color: current ? palette.foreground : palette.outline,
            width: current ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PageThumbnailImage(
                bookId: bookId,
                page: page,
                palette: palette,
                cacheWidth: 240,
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  color: palette.background.withValues(alpha: 0.7),
                  child: Text(
                    '$page',
                    style: AppTypography.of(context).label
                        .copyWith(color: palette.foreground),
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

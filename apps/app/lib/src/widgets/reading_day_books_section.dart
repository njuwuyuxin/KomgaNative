import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reading_stats.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 阅读热力图下方选中日期的阅读明细：当天日期、时长与读过的书（封面 + 标题）。
class ReadingDayBooksSection extends StatelessWidget {
  const ReadingDayBooksSection({
    required this.day,
    required this.existingLocalIds,
    super.key,
  });

  final ReadingDay day;
  final Set<String>? existingLocalIds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final iso = formatIsoDate(day.date);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  iso,
                  key: const Key('insights-selected-date'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures: AppTypography.tabularFigures,
                  ),
                ),
              ),
              if (day.minutes > 0)
                Text(
                  l10n.insightsMinutes(day.minutes),
                  key: const Key('insights-selected-minutes'),
                  style: AppTypography.of(context).progressNumber
                      .copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (day.readBooks.isEmpty)
            Text(
              l10n.insightsDayEmpty,
              key: const Key('insights-selected-empty'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            SizedBox(
              height: AppSizes.recentHistoryHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: day.readBooks.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final book = day.readBooks[index];
                  final removed =
                      existingLocalIds != null &&
                      isLocalSourceKey(book.scope) &&
                      !existingLocalIds!.contains(book.bookId);
                  return _DayBookTile(book: book, removed: removed);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DayBookTile extends ConsumerWidget {
  const _DayBookTile({required this.book, required this.removed});

  final ReadingDayBook book;
  final bool removed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    final cover = removed
        ? null
        : ref
              .watch(
                bookCoverProvider((
                  sourceKey: book.scope.isEmpty ? null : book.scope,
                  id: book.bookId,
                )),
              )
              .value;

    return SizedBox(
      width: AppSizes.recentHistoryTileWidth,
      child: InkWell(
        key: Key('insights-day-book-${book.bookId}'),
        borderRadius: eink
            ? BorderRadius.zero
            : BorderRadius.circular(AppRadii.sm),
        onTap: removed
            ? null
            : () {
                final query = book.scope.isEmpty
                    ? ''
                    : '?source=${Uri.encodeComponent(book.scope)}';
                unawaited(context.push('/reader/${book.bookId}$query'));
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: eink
                    ? BorderRadius.zero
                    : BorderRadius.circular(AppRadii.sm),
                child: SizedBox.expand(
                  child: cover != null
                      ? CoverImage(bytes: cover)
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: eink
                                ? AppTheme.einkPaper
                                : theme.colorScheme.surfaceContainerHighest,
                            border: eink
                                ? Border.all(color: AppTheme.einkInk)
                                : null,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.auto_stories_outlined,
                              size: AppSizes.iconMd,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              book.bookName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: removed ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 格式化本地日期为 `YYYY-MM-DD`。
String formatIsoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 打开一本书（方向来自所属系列，拿不到就按未知处理）。
typedef OpenBook = void Function(Book book, ReadingDirection direction);

/// 书架顶部的"继续阅读"横排。
///
/// 数据是 Komga 的 ondeck（读过但没读完）；读完的书会自动从这一行消失，
/// 所以它天然回答"我上次看到哪了"。
///
/// 空/失败/加载中都**不占位**：这是锦上添花的一行，不能因为离线或多一次请求
/// 把书架主体往下推、甚至挡住。
class ContinueReadingRow extends ConsumerWidget {
  const ContinueReadingRow({required this.onOpen, super.key});

  final OpenBook onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(ondeckProvider).value?.items;
    if (books == null || books.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(l10n.continueReading, style: theme.textTheme.titleSmall),
        ),
        SizedBox(
          height: 196,
          child: ListView.separated(
            key: const Key('continue-reading'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: books.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) =>
                _ContinueCard(book: books[index], onOpen: onOpen),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.book, required this.onOpen});

  final Book book;
  final OpenBook onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = ref.watch(bookCoverProvider(book.id)).value;
    // 阅读方向存在系列元数据里，不在书上；这里多一次按系列的查询（有 family 缓存）。
    final direction =
        ref
            .watch(seriesDetailProvider(book.seriesId))
            .value
            ?.readingDirection ??
        ReadingDirection.unknown;
    final progress = book.readProgress;
    final progressLabel = progress == null
        ? l10n.bookPages(book.pagesCount)
        : l10n.continueReadingProgress(progress.page, book.pagesCount);

    // 整张卡片是一个按钮：读屏念「书名 + 进度」，不逐条念封面/标题/页码。
    // 卡片宽 96、高 196，满足最小点击区（48）要求。
    return Semantics(
      key: Key('continue-${book.id}'),
      container: true,
      button: true,
      label: '${book.name}, $progressLabel',
      onTap: () => onOpen(book, direction),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onOpen(book, direction),
          child: SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: SizedBox(
                    width: 96,
                    height: 136,
                    child: cover == null
                        ? ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                          )
                        : Image.memory(
                            cover,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  book.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  progressLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

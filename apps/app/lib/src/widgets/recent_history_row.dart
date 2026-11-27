import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// "最近阅读"横滑条（HIS-02）：按会话时间取最近读过的书，点一下直接回到那本书。
///
/// 同一本书只出现一次（最近那次的位置）：用户关心的是"我刚才读的是哪本"，
/// 不是"这本书我读了几次"。已从本机书库删除的书籍会从快捷入口中过滤，
/// 但仍保留在 `reading_sessions` 中供阅读统计与热力图使用。
class RecentHistoryRow extends ConsumerWidget {
  const RecentHistoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(readingSessionsProvider).value;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();

    final hasLocal = sessions.any(
      (ReadingSession session) => isLocalSourceKey(session.scope),
    );
    final localAsync = hasLocal
        ? ref.watch(existingLocalBookIdsProvider)
        : null;
    final existingLocalIds = localAsync?.value;
    final waitingLocalIds =
        hasLocal && existingLocalIds == null && !(localAsync?.hasError ?? true);

    final seen = <String>{};
    final books = <ReadingSession>[];
    for (final session in sessions) {
      if (isLocalSourceKey(session.scope) && waitingLocalIds) continue;
      if (isRemovedLocalSession(session, existingLocalIds)) continue;
      if (!seen.add('${session.scope}|${session.bookId}')) continue;
      books.add(session);
      if (books.length >= 8) break;
    }
    if (books.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('recent-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.history,
                  style: AppTypography.of(context).title,
                ),
              ),
              TextButton(
                key: const Key('recent-history-see-all'),
                onPressed: () => context.push('/history'),
                child: Text(l10n.historySeeAll),
              ),
            ],
          ),
        ),
        SizedBox(
          height: AppSizes.recentHistoryHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: books.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (BuildContext context, int index) =>
                _RecentHistoryTile(session: books[index]),
          ),
        ),
      ],
    );
  }
}

class _RecentHistoryTile extends ConsumerWidget {
  const _RecentHistoryTile({required this.session});

  final ReadingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final resolvedScope = session.scope.isEmpty
        ? kLocalSourceKey
        : session.scope;
    final cover = ref
        .watch(
          bookCoverProvider((sourceKey: resolvedScope, id: session.bookId)),
        )
        .value;
    return SizedBox(
      width: AppSizes.recentHistoryTileWidth,
      child: InkWell(
        key: Key('recent-history-${session.bookId}'),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: () {
          final query = '?source=${Uri.encodeComponent(resolvedScope)}';
          context.push('/reader/${session.bookId}$query');
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: SizedBox.expand(
                  child: cover == null
                      ? ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                        )
                      : CoverImage(bytes: cover),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              session.bookName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

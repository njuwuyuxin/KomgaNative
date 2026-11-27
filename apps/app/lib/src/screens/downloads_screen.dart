import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/widgets/download_queue_menu.dart';
import 'package:yomu/src/widgets/download_row.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 下载管理页（UI-P3-13）：进行中 / 排队 / 已下载，可取消、删除。
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final records = ref.watch(downloadedBooksProvider);
    final active = ref.watch(downloadsProvider);
    final ids = <String>{
      ...?records.value?.map((DownloadedBookRecord r) => r.bookId),
      ...active.keys,
    }.toList(growable: false);

    return Scaffold(
      body: GlassPageBackground(
        child: RefreshIndicator(
          edgeOffset:
              MediaQuery.paddingOf(context).top + AppSizes.glassHeaderClearance,
          onRefresh: () async {
            ref.invalidate(downloadedBooksProvider);
            ref.invalidate(downloadsUsageProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              GlassHeaderSliver(
                // UI-01：整条标题栏只有**一层**玻璃——返回、标题、"取消全部"
                // 全在同一个胶囊里，不再是"圆球 + 胶囊 + 圆球"三件套。
                header: GlassHeader(
                  bar: GlassSurface(
                    shape: AppShapes.of(context, AppShapes.bar),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          key: const Key('downloads-back'),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              context.pop();
                            }
                          },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            l10n.downloadedBooks,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).title,
                          ),
                        ),
                        // 队列动作收进一个菜单（DLD-02）：暂停/继续、重试失败、
                        // 取消全部、删除全部——四个按钮平铺会把标题挤没。
                        if (active.isNotEmpty || ids.isNotEmpty)
                          QueueMenu(
                            paused: ref.read(downloadsProvider.notifier).paused,
                            hasActive: active.isNotEmpty,
                            hasFailed: active.values.any(
                              (DownloadStatus s) => s.hasError,
                            ),
                            hasRecords: records.value?.isNotEmpty ?? false,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (ids.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.download_outlined,
                        size: AppSpacing.xxl,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.downloadsEmpty),
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: Text(
                          l10n.downloadsEmptyHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSizes.navBarClearance,
                  ),
                  sliver: SliverList.list(
                    children: <Widget>[
                      AppListGroup(
                        key: const Key('downloads-list'),
                        children: <Widget>[
                          for (final id in ids) DownloadRow(bookId: id),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

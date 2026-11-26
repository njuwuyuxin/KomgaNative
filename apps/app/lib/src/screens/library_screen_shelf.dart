part of 'library_screen.dart';

/// 书架内容区：三态（骨架/空错/内容）与网格/列表的 sliver 拼装。
///
/// 从页面里拆出来是为了守住单文件行数上限：页面只管布局与意图派发，
/// 这里管"当前状态该画成什么"。
mixin _ShelfSlivers on ConsumerState<LibraryScreen> {
  /// 页面提供：错误态的"重试"要能触发同一套刷新（含"正在读"页的失效）。
  Future<void> _refresh();

  /// 三态的稳定标识：只有它变了才播一次入场淡入。
  ///
  /// 用"加载中/空/错/内容"四档而不是整份 state：列表滚动、追加下一页
  /// 都不该触发一次全屏淡入。
  String _phaseOf(ShelfState state) {
    if (state.loading && state.series.isEmpty) return 'loading';
    if (state.failure != null && state.series.isEmpty) return 'error';
    if (state.isEmpty) return 'empty';
    return 'content';
  }

  /// 骨架 / 空错 / 内容三态，各自是 sliver（三态之间交叉淡入，UI-P2-8）。
  List<Widget> _shelfSlivers(
    AppLocalizations l10n,
    ShelfState state,
    ShelfController controller, {
    required bool isRealLocalShelf,
  }) {
    if (state.loading && state.series.isEmpty) {
      return <Widget>[const SliverFillRemaining(child: ShelfSkeleton())];
    }
    final failure = state.failure;
    if (failure != null && state.series.isEmpty) {
      final needsSignIn = failure is AuthFailure;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView(
            key: const Key('shelf-error'),
            icon: Icons.cloud_off_outlined,
            title: l10n.failureTitle(failure.kind),
            message: l10n.failureHint(failure.kind),
            actionLabel: needsSignIn ? l10n.signOut : l10n.retry,
            onAction: needsSignIn
                ? () => ref.read(sessionProvider.notifier).signOut()
                : () => unawaited(_refresh()),
          ),
        ),
      ];
    }
    if (state.isEmpty) {
      if (isRealLocalShelf && state.query.isEmpty) {
        return <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  key: const Key('shelf-local-onboarding'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    StatusView(
                      icon: Icons.auto_stories_outlined,
                      title: l10n.localEmptyShelfTitle,
                      message: l10n.localEmptyShelfHint,
                      actionLabel: l10n.importComics,
                      onAction: () =>
                          unawaited(runLocalArchiveImport(context, ref)),
                    ),
                    if (GoRouter.maybeOf(context) != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        key: const Key('shelf-connect-komga-button'),
                        onPressed: () => unawaited(context.push('/connect')),
                        icon: const Icon(
                          Icons.cloud_outlined,
                          size: AppSizes.iconSm,
                        ),
                        label: Text(l10n.connectKomgaOptional),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ];
      }
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView(
            key: const Key('shelf-empty'),
            icon: Icons.auto_stories_outlined,
            title: state.query.isEmpty ? l10n.noSeriesYet : l10n.noMatches,
            message: state.query.isEmpty
                ? l10n.emptyShelfHint
                : l10n.noSearchMatchesHint,
          ),
        ),
      ];
    }
    // 多选态（LIB-03）：勾选只影响卡片的外观与点击行为。
    final selection = ref.watch(shelfSelectionProvider);
    // 置顶区（LIB-02）：单独取这几本的元数据排在前面，主列表里把它们剔掉，
    // 免得同一个系列在屏幕上出现两次。
    final pinned = ref.watch(pinnedSeriesProvider).value ?? const <Series>[];
    final pinnedIds = <String>{for (final series in pinned) series.id};
    final series = <Series>[
      for (final item in state.series)
        if (!pinnedIds.contains(item.id)) item,
    ];
    return <Widget>[
      if (pinned.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.push_pin,
                  size: AppSizes.iconSm,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.pinned,
                  key: const Key('shelf-pinned-header'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: shelfGridDelegate(state.coverSize),
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              final item = pinned[index];
              return SeriesShelfTile(
                series: item,
                selecting: selection.active,
                selected: selection.contains(item.id),
                onTap: () => selection.active
                    ? _toggleSelect(item.id)
                    : unawaited(_openSeries(item)),
                onLongPress: selection.active
                    ? () => _toggleSelect(item.id)
                    : null,
              );
            }, childCount: pinned.length),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
      ],
      // 网格 / 列表（UI-P2-7）：两种视图共用同一份列表，
      // 切换只是换 sliver 的类型，不重新请求。
      if (state.view == ShelfView.grid)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: shelfGridDelegate(state.coverSize),
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              final item = series[index];
              return SeriesShelfTile(
                series: item,
                selecting: selection.active,
                selected: selection.contains(item.id),
                onTap: () => selection.active
                    ? _toggleSelect(item.id)
                    : unawaited(_openSeries(item)),
                onLongPress: selection.active
                    ? () => _toggleSelect(item.id)
                    : null,
              );
            }, childCount: series.length),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((
            BuildContext context,
            int index,
          ) {
            final item = series[index];
            return SeriesShelfRow(
              key: Key('series-${item.id}'),
              series: item,
              coverSize: state.coverSize,
              selecting: selection.active,
              selected: selection.contains(item.id),
              onTap: () => selection.active
                  ? _toggleSelect(item.id)
                  : unawaited(_openSeries(item)),
              onLongPress: selection.active
                  ? () => _toggleSelect(item.id)
                  : null,
            );
          }, childCount: series.length),
        ),
      SliverToBoxAdapter(
        child: ShelfPagingFooter(
          state: state,
          onRetry: () => controller.loadMore(),
        ),
      ),
    ];
  }

  void _toggleSelect(String seriesId) {
    unawaited(AppHaptics.selection());
    ref.read(shelfSelectionProvider.notifier).toggle(seriesId);
  }

  /// 进系列页；回来时原地刷新进度（别把列表清空跳回顶部）。
  Future<void> _openSeries(Series series) async {
    await context.push('/series/${series.id}');
    await ref.read(shelfProvider.notifier).refreshInPlace();
  }
}

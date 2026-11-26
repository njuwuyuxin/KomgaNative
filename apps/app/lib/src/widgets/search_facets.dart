import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 搜索页的筛选条（SCH-02）。
///
/// 只上线**服务端已验证**的两个维度：
/// - `read_status`：UNREAD / IN_PROGRESS / READ（与书架筛选同一套枚举，已验证）；
/// - `tag`：2026-11-20 在本机 Komga 1.30.1 上写了两条对照数据后验证
///   （`tag=VerifyTag` 只返回那一部，`tag=NotATag` 返回 0）。
///
/// `author=` **没有做**：同一个库上 `author=Verify Author` 与 `author=NobodyHere`
/// 返回的结果完全一样（都是全部 5 部）——服务端静默忽略该参数，做上去等于骗人。
///
/// 标签候选来自 `searchTagFacetsProvider`：Komga 没有 facets 接口，
/// 只能从"未加标签筛选"的结果里按出现次数聚合。
class SearchFacets extends ConsumerWidget {
  const SearchFacets({
    required this.query,
    required this.readStatus,
    required this.tag,
    required this.onReadStatus,
    required this.onTag,
    required this.onClear,
    super.key,
  });

  final String query;
  final SeriesReadStatus? readStatus;
  final String? tag;
  final ValueChanged<SeriesReadStatus?> onReadStatus;
  final ValueChanged<String?> onTag;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tags =
        ref
            .watch(
              searchTagFacetsProvider((
                query: query,
                readStatus: null,
                tag: null,
              )),
            )
            .value ??
        const <String>[];
    final active = readStatus != null || tag != null;

    return Padding(
      key: const Key('search-facets'),
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Text(l10n.searchFilter, style: theme.textTheme.labelLarge),
                const Spacer(),
                if (active)
                  TextButton(
                    key: const Key('search-facets-clear'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, AppSizes.minTouch),
                    ),
                    onPressed: onClear,
                    child: Text(l10n.clearFilters),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 不裁阴影：SingleChildScrollView 默认 Clip.hardEdge 会贴着胶囊边缘切掉
          // GlassPillButton 的 AppShadows.card，真机上会在圆角外露出方形硬边阴影
          // （与 GlassMenuButton 同因）；横向左右溢出由外层 CustomScrollView 视口裁切。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: <Widget>[
                _Chip(
                  key: const Key('search-facet-all'),
                  label: l10n.all,
                  selected: readStatus == null,
                  onTap: () => onReadStatus(null),
                ),
                _Chip(
                  key: const Key('search-facet-unread'),
                  label: l10n.statusUnread,
                  selected: readStatus == SeriesReadStatus.unread,
                  onTap: () => onReadStatus(SeriesReadStatus.unread),
                ),
                _Chip(
                  key: const Key('search-facet-inProgress'),
                  label: l10n.statusInProgress,
                  selected: readStatus == SeriesReadStatus.inProgress,
                  onTap: () => onReadStatus(SeriesReadStatus.inProgress),
                ),
                _Chip(
                  key: const Key('search-facet-read'),
                  label: l10n.statusRead,
                  selected: readStatus == SeriesReadStatus.read,
                  onTap: () => onReadStatus(SeriesReadStatus.read),
                ),
                for (final item in tags)
                  _Chip(
                    key: Key('search-facet-tag-$item'),
                    label: item,
                    selected: tag == item,
                    // 再点一次同一个标签 = 取消。
                    onTap: () => onTag(tag == item ? null : item),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: GlassPillButton(
        label: label,
        onPressed: onTap,
        expanded: false,
        icon: selected ? Icons.check : null,
      ),
    );
  }
}

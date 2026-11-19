import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart' show iconForMode;
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 顶栏菜单里的一项（RDR-03）。
///
/// 顶栏只留 4 个槽位：返回 / 标题+页码 / AA / ⋯。目录、隐身、页面缩略图、
/// 阅读设置、分享都收进这个菜单——6 颗图标挤在一条里，每颗的点击区都被压到
/// 40pt 以下，比"少一次点击"更难受。
enum ReaderBarAction { toc, incognito, pages, settings, share }

/// 阅读器顶栏。
///
/// [pageLabel] 留在标题槽位里（书名右侧的小字）：它和书名是同一件事的两个粒度，
/// 单独占一个槽位太贵。
class ReaderBar extends StatelessWidget {
  const ReaderBar({
    required this.title,
    required this.pageLabel,
    required this.palette,
    required this.mode,
    required this.onClose,
    required this.onOpenQuickSettings,
    required this.onOpenSettings,
    required this.onOpenPages,
    required this.incognito,
    required this.onToggleIncognito,
    this.onOpenToc,
    this.onSharePage,
    this.offline = false,
    super.key,
  });

  final String title;

  /// 单页是 `3 / 12`，双页是 `3–4 / 12`。
  final String pageLabel;

  final ReaderPalette palette;

  /// 当前生效的模式：菜单里的"阅读设置"用它显示图标。
  final ReadingMode mode;

  final VoidCallback onClose;
  final VoidCallback onOpenQuickSettings;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPages;

  /// 目录（RDR-02）；系列未知时不出现。
  final VoidCallback? onOpenToc;

  /// 分享当前页（UI-P3-6）。
  final VoidCallback? onSharePage;

  /// 本次阅读是否不回写进度（UI-P3-12）。
  final bool incognito;
  final VoidCallback onToggleIncognito;

  /// 当前内容可能来自缓存（断网/服务端不可用）。
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = <ReaderBarAction>[
      if (onOpenToc != null) ReaderBarAction.toc,
      ReaderBarAction.incognito,
      ReaderBarAction.pages,
      ReaderBarAction.settings,
      if (onSharePage != null) ReaderBarAction.share,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            key: const Key('reader-close-button'),
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back),
            color: palette.foreground,
            tooltip: l10n.close,
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (offline) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: l10n.offlineSavedPages,
                    child: Icon(
                      Icons.cloud_off_outlined,
                      size: AppSizes.iconXs,
                      color: palette.muted,
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
                Text(
                  pageLabel,
                  // 页码每翻一页都在变：等宽数字让它不左右跳（UI-01）。
                  style: AppTypography.of(context).progressNumber
                      .copyWith(color: palette.muted),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('reader-quick-settings-button'),
            onPressed: onOpenQuickSettings,
            icon: const Icon(Icons.text_fields),
            color: palette.foreground,
            tooltip: l10n.readerQuickSettings,
          ),
          IconTheme(
            data: IconThemeData(color: palette.foreground),
            child: PopupMenuButton<ReaderBarAction>(
              key: const Key('reader-more-button'),
              tooltip: l10n.readerMore,
              icon: const Icon(Icons.more_horiz),
              onSelected: (ReaderBarAction action) => _run(context, action),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<ReaderBarAction>>[
                    for (final action in actions)
                      PopupMenuItem<ReaderBarAction>(
                        key: Key(_keyFor(action)),
                        value: action,
                        child: Row(
                          children: <Widget>[
                            Icon(_iconFor(action), size: AppSizes.iconMd),
                            const SizedBox(width: AppSpacing.sm),
                            Flexible(child: Text(_labelFor(l10n, action))),
                          ],
                        ),
                      ),
                  ],
            ),
          ),
        ],
      ),
    );
  }

  void _run(BuildContext context, ReaderBarAction action) {
    switch (action) {
      case ReaderBarAction.toc:
        onOpenToc?.call();
      case ReaderBarAction.incognito:
        onToggleIncognito();
      case ReaderBarAction.pages:
        onOpenPages();
      case ReaderBarAction.settings:
        onOpenSettings();
      case ReaderBarAction.share:
        onSharePage?.call();
    }
  }

  /// 菜单项的 key 沿用原来的按钮名（`reader-settings-button` 等）：
  /// 测试和外部脚本只要"先开菜单"就能照旧点到。
  static String _keyFor(ReaderBarAction action) => switch (action) {
    ReaderBarAction.toc => 'reader-toc-button',
    ReaderBarAction.incognito => 'reader-incognito-button',
    ReaderBarAction.pages => 'reader-pages-button',
    ReaderBarAction.settings => 'reader-settings-button',
    ReaderBarAction.share => 'reader-share-button',
  };

  IconData _iconFor(ReaderBarAction action) => switch (action) {
    ReaderBarAction.toc => Icons.toc_outlined,
    ReaderBarAction.incognito =>
      incognito ? Icons.visibility_off_outlined : Icons.visibility_outlined,
    ReaderBarAction.pages => Icons.grid_view_outlined,
    ReaderBarAction.settings => iconForMode(mode),
    ReaderBarAction.share => Icons.ios_share,
  };

  String _labelFor(AppLocalizations l10n, ReaderBarAction action) =>
      switch (action) {
        ReaderBarAction.toc => l10n.readerToc,
        ReaderBarAction.incognito =>
          incognito ? l10n.incognitoOn : l10n.incognitoOff,
        ReaderBarAction.pages => l10n.pageThumbnailsTooltip,
        ReaderBarAction.settings => l10n.readingSettingsTooltip,
        ReaderBarAction.share => l10n.sharePage,
      };
}

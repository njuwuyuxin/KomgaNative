import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器的失败页（书打不开 / 页列表加载失败）。
class ReaderFailure extends StatelessWidget {
  const ReaderFailure({
    required this.failure,
    required this.onRetry,
    required this.palette,
    this.title,
    super.key,
  });

  final Object failure;
  final VoidCallback onRetry;
  final ReaderPalette palette;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        foregroundColor: palette.onBackground,
        title: Text(l10n.readerTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.broken_image_outlined,
                size: AppSpacing.xxl,
                color: palette.onBackgroundMuted,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title ??
                    (message == null
                        ? null
                        : l10n.failureTitle(message.kind)) ??
                    l10n.readerOpenFailed,
                style: TextStyle(color: palette.onBackground),
                textAlign: TextAlign.center,
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.failureHint(message.kind),
                  style: TextStyle(color: palette.onBackgroundMuted),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单页加载失败时的占位（还能翻页/退出）。
class PageError extends StatelessWidget {
  const PageError({
    required this.error,
    required this.onRetry,
    required this.palette,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = error is ShelfFailure ? error as ShelfFailure : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.broken_image_outlined,
          color: palette.onBackgroundMuted,
          size: AppSpacing.xl,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message == null
              ? l10n.readerPageFailed
              : l10n.failureTitle(message.kind),
          style: TextStyle(color: palette.onBackgroundMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
  }
}

/// 模式图标：顶栏按钮与设置面板共用，避免两处各写一份。
IconData iconForMode(ReadingMode mode) => switch (mode) {
  ReadingMode.paged => Icons.crop_portrait,
  ReadingMode.doublePage => Icons.auto_stories_outlined,
  ReadingMode.verticalScroll => Icons.view_agenda_outlined,
};

/// 书末的"读完 / 下一本"卡片见 `reader_finished_card.dart`（UI-P1-7：从条改成卡片）。

/// 底部：上一屏 / 当前页码 / 下一屏。
///
/// 左右箭头的**位置**跟着阅读方向走（RTL 漫画的"下一页"在左侧），与画面点击区
/// 共用同一个判断 [leftTurnsNext]，所以不会出现"点左边是前进、箭头左边却是后退"。
class ReaderControls extends StatelessWidget {
  const ReaderControls({
    required this.pageLabel,
    required this.palette,
    required this.leftTurnsNext,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  /// 当前页码（不是总页数）：单页 `Page 3`，双页 `Pages 3–4`。
  final String pageLabel;

  final ReaderPalette palette;

  /// 左侧按钮是不是"下一页"。
  final bool leftTurnsNext;

  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget button({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon),
        color: palette.foreground,
        disabledColor: palette.outline,
        tooltip: tooltip,
      );
    }

    // 图标永远指向"这一侧"（左箭头朝左、右箭头朝右），语义（上一页/下一页）
    // 由 [leftTurnsNext] 决定，两者不会再各说各话。
    final leftButton = leftTurnsNext
        ? button(
            key: const Key('reader-next-button'),
            icon: Icons.chevron_left,
            tooltip: l10n.nextPage,
            onPressed: onNext,
          )
        : button(
            key: const Key('reader-previous-button'),
            icon: Icons.chevron_left,
            tooltip: l10n.previousPage,
            onPressed: onPrevious,
          );
    final rightButton = leftTurnsNext
        ? button(
            key: const Key('reader-previous-button'),
            icon: Icons.chevron_right,
            tooltip: l10n.previousPage,
            onPressed: onPrevious,
          )
        : button(
            key: const Key('reader-next-button'),
            icon: Icons.chevron_right,
            tooltip: l10n.nextPage,
            onPressed: onNext,
          );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          leftButton,
          if (pageLabel.isNotEmpty)
            Text(pageLabel, style: TextStyle(color: palette.muted)),
          rightButton,
        ],
      ),
    );
  }
}

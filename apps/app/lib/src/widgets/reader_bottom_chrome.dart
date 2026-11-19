import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_finished_card.dart';
import 'package:komga_native/src/widgets/reader_layout.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_thumbnail_strip.dart';
import 'package:material_ui/material_ui.dart';

/// 底部 chrome 的三段：缩略图滑条（UI-P1-2）、书末卡片（UI-P1-7）、翻页控件。
///
/// 抽出来是为了让 `ReaderScreen` 只做编排（它已经贴着 350 行上限），
/// 三段共用的 `ReaderLayout` 也在这里一次性展开，避免页面里再算一遍分屏。
class ReaderBottomChrome extends StatelessWidget {
  const ReaderBottomChrome({
    required this.bookId,
    required this.layout,
    required this.palette,
    required this.rightToLeft,
    required this.onJump,
    required this.onBack,
    this.onGroupFrom,
    this.onSharePage,
    this.nextBook,
    this.onOpenNext,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final String bookId;
  final ReaderLayout layout;
  final ReaderPalette palette;
  final bool rightToLeft;

  /// 点缩略图 / 书末卡片的"继续阅读"。
  final ValueChanged<int> onJump;

  /// 双页模式长按缩略图："从这一页开始分组"（UI-P3-5）；其他模式为空。
  final ValueChanged<int>? onGroupFrom;

  /// 长按缩略图分享某页（UI-P3-6）。
  final Future<void> Function(int page)? onSharePage;

  /// 书末卡片的"返回系列"。
  final VoidCallback onBack;

  final Book? nextBook;
  final VoidCallback? onOpenNext;

  /// 翻页控件（上下箭头 / 音量键同一入口）。
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (layout.completed)
          ReaderFinishedCard(
            palette: palette,
            nextBook: nextBook,
            onNext: onOpenNext,
            onBack: onBack,
          ),
        ReaderThumbnailStrip(
          bookId: bookId,
          layout: layout,
          palette: palette,
          rightToLeft: rightToLeft,
          onJump: onJump,
          onGroupFrom: onGroupFrom,
          onSharePage: onSharePage,
        ),
        ReaderControls(
          pageLabel: layout.positionLabel(l10n),
          palette: palette,
          // 点击区与底部箭头共用这一个判断：RTL 时左侧（点/箭头）
          // 都是"下一页"。后续加"阅读方向"设置时只改这里的来源。
          leftTurnsNext: rightToLeft,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
      ],
    );
  }
}

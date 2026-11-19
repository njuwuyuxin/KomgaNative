import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 适配方式的界面文案（数据层只保留枚举，文案全在 ARB）。
String readerFitLabel(AppLocalizations l10n, ReaderFitChoice choice) =>
    switch (choice) {
      ReaderFitChoice.contain => l10n.readerFitContain,
      ReaderFitChoice.cover => l10n.readerFitCover,
      ReaderFitChoice.fitWidth => l10n.readerFitWidth,
      ReaderFitChoice.fitHeight => l10n.readerFitHeight,
    };

String readerFitHint(AppLocalizations l10n, ReaderFitChoice choice) =>
    switch (choice) {
      ReaderFitChoice.contain => l10n.readerFitContainHint,
      ReaderFitChoice.cover => l10n.readerFitCoverHint,
      ReaderFitChoice.fitWidth => l10n.readerFitWidthHint,
      ReaderFitChoice.fitHeight => l10n.readerFitHeightHint,
    };

/// 阅读方向的界面文案。
String readerDirectionLabel(
  AppLocalizations l10n,
  ReaderDirectionChoice choice,
) => switch (choice) {
  ReaderDirectionChoice.auto => l10n.readerDirectionAuto,
  ReaderDirectionChoice.leftToRight => l10n.readerDirectionLtr,
  ReaderDirectionChoice.rightToLeft => l10n.readerDirectionRtl,
};

String readerDirectionHint(
  AppLocalizations l10n,
  ReaderDirectionChoice choice,
) => switch (choice) {
  ReaderDirectionChoice.auto => l10n.readerDirectionAutoHint,
  ReaderDirectionChoice.leftToRight => l10n.readerDirectionLtrHint,
  ReaderDirectionChoice.rightToLeft => l10n.readerDirectionRtlHint,
};

/// 背景的界面文案。
String readerBackgroundLabel(
  AppLocalizations l10n,
  ReaderBackgroundChoice choice,
) => switch (choice) {
  ReaderBackgroundChoice.black => l10n.readerBackgroundBlack,
  ReaderBackgroundChoice.white => l10n.readerBackgroundWhite,
  ReaderBackgroundChoice.dynamic => l10n.readerBackgroundDynamic,
  ReaderBackgroundChoice.immersive => l10n.readerBackgroundImmersive,
};

String readerBackgroundHint(
  AppLocalizations l10n,
  ReaderBackgroundChoice choice,
) => switch (choice) {
  ReaderBackgroundChoice.black => l10n.readerBackgroundBlackHint,
  ReaderBackgroundChoice.white => l10n.readerBackgroundWhiteHint,
  ReaderBackgroundChoice.dynamic => l10n.readerBackgroundDynamicHint,
  ReaderBackgroundChoice.immersive => l10n.readerBackgroundImmersiveHint,
};

/// 面板里的一个"单选一组"区块：小标题 + 若干行。
///
/// 四种设置（模式 / 适配 / 方向 / 背景）的结构完全一样，抽成一个泛型区块，
/// 避免在 `reader_settings_sheet.dart` 里复制四遍同样的 Row + 单选图标。
class ReaderOptionSection<T> extends StatelessWidget {
  const ReaderOptionSection({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.hint,
    required this.keyPrefix,
    required this.palette,
    required this.onSelect,
    this.preview,
    super.key,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(AppLocalizations l10n, T value) label;
  final String Function(AppLocalizations l10n, T value) hint;

  /// 行的 key 前缀：`reader-mode` → `reader-mode-double`。
  final String keyPrefix;

  final ReaderPalette palette;
  final ValueChanged<T> onSelect;

  /// 行首的小示意图（适配方式用，RDR-04）；为空时就是普通单选行。
  final Widget Function(BuildContext context, T value)? preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ReaderSectionLabel(title, palette: palette),
        for (final value in values)
          InkWell(
            key: Key('$keyPrefix-${(value as Enum).name}'),
            onTap: () => onSelect(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (preview != null) ...<Widget>[
                    preview!(context, value),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Icon(
                    value == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: AppSizes.iconMd,
                    color: value == selected
                        ? palette.foreground
                        : palette.muted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label(l10n, value),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: palette.foreground,
                            fontWeight: value == selected
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                        // 说明只给选中项看：全带说明会把面板撑到屏幕外，
                        // 而用户真正需要解释的只有"我正要选的那个"。
                        if (value == selected)
                          Text(
                            hint(l10n, value),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 区块小标题（全大写、字距放宽）。
class ReaderSectionLabel extends StatelessWidget {
  const ReaderSectionLabel(this.text, {required this.palette, super.key});

  final String text;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.of(context).label
            .copyWith(letterSpacing: 1.2, color: palette.muted),
      ),
    );
  }
}

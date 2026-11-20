import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_settings_group.dart';
import 'package:komga_native/src/widgets/reader_settings_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板的「颜色」与「交互」两组（ARC-12 拆分独立组件）。
class ReaderSettingsColorInteraction extends StatelessWidget {
  const ReaderSettingsColorInteraction({
    required this.prefs,
    required this.palette,
    required this.controller,
    required this.writeSeriesId,
    super.key,
  });

  final ReaderConfig prefs;
  final ReaderPalette palette;
  final ReaderPrefsController controller;
  final String? writeSeriesId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ReaderSettingsGroupHeader(
          group: 'color',
          title: l10n.readerGroupColor,
          palette: palette,
          enabled: !prefs.isGroupDefault(ReaderSettingsGroup.color),
          onReset: () => controller.resetGroup(
            ReaderSettingsGroup.color,
            seriesId: writeSeriesId,
          ),
        ),
        if (!palette.isEink) ...<Widget>[
          ReaderOptionSection<ReaderBackgroundChoice>(
            title: l10n.readerBackground,
            values: ReaderBackgroundChoice.values,
            selected: prefs.background,
            label: readerBackgroundLabel,
            hint: readerBackgroundHint,
            keyPrefix: 'reader-background',
            palette: palette,
            onSelect: (ReaderBackgroundChoice value) =>
                controller.setBackground(value, seriesId: writeSeriesId),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ReaderSectionLabel(l10n.brightness, palette: palette),
        Row(
          children: <Widget>[
            Icon(
              Icons.brightness_low,
              color: palette.muted,
              size: AppSizes.iconMd,
            ),
            Expanded(
              child: Slider(
                key: const Key('reader-brightness-slider'),
                value: prefs.brightness,
                min: ReaderPrefs.minBrightness,
                max: 1,
                activeColor: palette.foreground,
                inactiveColor: palette.outline,
                onChanged: (double value) =>
                    controller.setBrightness(value, seriesId: writeSeriesId),
              ),
            ),
            SizedBox(
              width: AppSizes.valueColumn,
              child: Text(
                l10n.brightnessPercent((prefs.brightness * 100).round()),
                textAlign: TextAlign.end,
                style: textStyle.bodySmall?.copyWith(color: palette.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReaderSettingsGroupHeader(
          group: 'interaction',
          title: l10n.readerGroupInteraction,
          palette: palette,
          enabled: !prefs.isGroupDefault(ReaderSettingsGroup.interaction),
          onReset: () => controller.resetGroup(
            ReaderSettingsGroup.interaction,
            seriesId: writeSeriesId,
          ),
        ),
        ReaderOptionSection<ReaderPageTurnChoice>(
          title: l10n.readerPageTurn,
          values: ReaderPageTurnChoice.values,
          selected: prefs.pageTurn,
          label: readerPageTurnLabel,
          hint: readerPageTurnHint,
          keyPrefix: 'reader-turn',
          palette: palette,
          onSelect: (ReaderPageTurnChoice value) =>
              controller.setPageTurn(value, seriesId: writeSeriesId),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReaderSettingsSwitch(
          switchKey: const Key('reader-lock-zoom'),
          value: prefs.lockZoom,
          title: l10n.readerLockZoom,
          hint: l10n.readerLockZoomHint,
          palette: palette,
          onChanged: (bool value) =>
              controller.setLockZoom(value, seriesId: writeSeriesId),
        ),
        ReaderSettingsSwitch(
          switchKey: const Key('reader-keep-awake'),
          value: prefs.keepAwake,
          title: l10n.keepScreenAwake,
          hint: l10n.keepScreenAwakeHint,
          palette: palette,
          onChanged: (bool value) =>
              controller.setKeepAwake(value, seriesId: writeSeriesId),
        ),
      ],
    );
  }
}

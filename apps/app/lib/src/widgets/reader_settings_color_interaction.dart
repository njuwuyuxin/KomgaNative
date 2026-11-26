import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/widgets/reader_mode_text.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_settings_group.dart';
import 'package:yomu/src/widgets/reader_settings_rows.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板的「颜色」与「交互」两组（ARC-12 拆分独立组件）。
class ReaderSettingsColorInteraction extends StatelessWidget {
  const ReaderSettingsColorInteraction({
    required this.prefs,
    required this.palette,
    required this.controller,
    required this.writeSeriesId,
    required this.serverKey,
    super.key,
  });

  final ReaderConfig prefs;
  final ReaderPalette palette;
  final ReaderPrefsController controller;
  final String? writeSeriesId;
  final String serverKey;

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
            serverKey: serverKey,
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
                controller.setBackground(
                  value,
                  seriesId: writeSeriesId,
                  serverKey: serverKey,
                ),
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
                onChanged: (double value) => controller.setBrightness(
                  value,
                  seriesId: writeSeriesId,
                  serverKey: serverKey,
                ),
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
        const SizedBox(height: AppSpacing.sm),
        ReaderOptionSection<ReaderImageFilterPreset>(
          title: l10n.readerImageFilter,
          values: ReaderImageFilterPreset.values,
          selected: prefs.imageFilter.preset,
          label: readerFilterPresetLabel,
          hint: readerFilterPresetHint,
          keyPrefix: 'reader-filter',
          palette: palette,
          onSelect: (ReaderImageFilterPreset preset) {
            final next = switch (preset) {
              ReaderImageFilterPreset.none => ReaderImageFilter.none,
              ReaderImageFilterPreset.einkCrisp => ReaderImageFilter.einkCrisp,
              ReaderImageFilterPreset.vintageDeYellow =>
                ReaderImageFilter.vintageDeYellow,
              ReaderImageFilterPreset.grayscale =>
                ReaderImageFilter.grayscaleOnly,
              ReaderImageFilterPreset.custom =>
                prefs.imageFilter.resolved().copyWith(
                  preset: ReaderImageFilterPreset.custom,
                ),
            };
            controller.setImageFilter(
              next,
              seriesId: writeSeriesId,
              serverKey: serverKey,
            );
          },
        ),
        if (prefs.imageFilter.preset ==
            ReaderImageFilterPreset.custom) ...<Widget>[
          _FilterSliderRow(
            sliderKey: const Key('reader-filter-contrast-slider'),
            label: l10n.readerFilterContrast,
            valueLabel: '${prefs.imageFilter.contrast.toStringAsFixed(2)}×',
            value: prefs.imageFilter.contrast,
            min: ReaderImageFilter.minContrast,
            max: ReaderImageFilter.maxContrast,
            palette: palette,
            onChanged: (double v) => controller.setImageFilter(
              prefs.imageFilter.copyWith(contrast: v),
              seriesId: writeSeriesId,
              serverKey: serverKey,
            ),
          ),
          _FilterSliderRow(
            sliderKey: const Key('reader-filter-white-slider'),
            label: l10n.readerFilterWhitePoint,
            valueLabel: '${prefs.imageFilter.whiteThreshold}',
            value: prefs.imageFilter.whiteThreshold.toDouble(),
            min: ReaderImageFilter.minWhiteThreshold.toDouble(),
            max: ReaderImageFilter.maxWhiteThreshold.toDouble(),
            palette: palette,
            onChanged: (double v) => controller.setImageFilter(
              prefs.imageFilter.copyWith(whiteThreshold: v.round()),
              seriesId: writeSeriesId,
              serverKey: serverKey,
            ),
          ),
          ReaderSettingsSwitch(
            switchKey: const Key('reader-filter-grayscale'),
            value: prefs.imageFilter.grayscale,
            title: l10n.readerFilterGrayscaleToggle,
            hint: l10n.readerFilterGrayscaleHint,
            palette: palette,
            onChanged: (bool value) => controller.setImageFilter(
              prefs.imageFilter.copyWith(grayscale: value),
              seriesId: writeSeriesId,
              serverKey: serverKey,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ReaderSettingsGroupHeader(
          group: 'interaction',
          title: l10n.readerGroupInteraction,
          palette: palette,
          enabled: !prefs.isGroupDefault(ReaderSettingsGroup.interaction),
          onReset: () => controller.resetGroup(
            ReaderSettingsGroup.interaction,
            seriesId: writeSeriesId,
            serverKey: serverKey,
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
          onSelect: (ReaderPageTurnChoice value) => controller.setPageTurn(
            value,
            seriesId: writeSeriesId,
            serverKey: serverKey,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReaderSettingsSwitch(
          switchKey: const Key('reader-lock-zoom'),
          value: prefs.lockZoom,
          title: l10n.readerLockZoom,
          hint: l10n.readerLockZoomHint,
          palette: palette,
          onChanged: (bool value) => controller.setLockZoom(
            value,
            seriesId: writeSeriesId,
            serverKey: serverKey,
          ),
        ),
        ReaderSettingsSwitch(
          switchKey: const Key('reader-keep-awake'),
          value: prefs.keepAwake,
          title: l10n.keepScreenAwake,
          hint: l10n.keepScreenAwakeHint,
          palette: palette,
          onChanged: (bool value) => controller.setKeepAwake(
            value,
            seriesId: writeSeriesId,
            serverKey: serverKey,
          ),
        ),
      ],
    );
  }
}

class _FilterSliderRow extends StatelessWidget {
  const _FilterSliderRow({
    required this.sliderKey,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.palette,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ReaderPalette palette;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: palette.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: style),
        Row(
          children: <Widget>[
            Expanded(
              child: Slider(
                key: sliderKey,
                value: value.clamp(min, max),
                min: min,
                max: max,
                activeColor: palette.foreground,
                inactiveColor: palette.outline,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: AppSizes.valueColumn,
              child: Text(valueLabel, textAlign: TextAlign.end, style: style),
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_settings_rows.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

/// 顶栏 `AA` 打开的快捷设置（RDR-03）。
///
/// 只放"读的时候真的会改"的五项：亮度、背景、方向、适配、锁定缩放。
/// 模式/预设/常亮/跳页留完整面板——它们要么低频，要么需要更大的控件。
///
/// 用紧凑胶囊而不是完整面板的单选行：完整面板一屏放不下四组，而这一层
/// 的意义就是"改完立刻回到画面"。
Future<void> showReaderQuickSettingsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required String sourceKey,
  String? seriesId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext context) => ScopedSourceScope(
      sourceKey: sourceKey,
      child: FrostedSurface(
        kind: AppMaterialKind.sheet,
        material: AppMaterial.resolve(
          AppMaterialKind.sheet,
          eink: palette.isEink,
          dark: !palette.isEink,
        ),
        shape: AppShapes.sheet(eink: palette.isEink),
        child: Material(
          type: MaterialType.transparency,
          child: ReaderQuickSettingsSheet(
            palette: palette,
            sourceKey: sourceKey,
            seriesId: seriesId,
          ),
        ),
      ),
    ),
  );
}

class ReaderQuickSettingsSheet extends ConsumerWidget {
  const ReaderQuickSettingsSheet({
    required this.palette,
    required this.sourceKey,
    this.seriesId,
    super.key,
  });

  final ReaderPalette palette;

  /// 当前书的系列：有值时这些改动只作用在这个系列（"按系列记住"开着的话）。
  final String? seriesId;
  final String sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = ref.watch(readerPrefsProvider);
    final serverKey = sourceKey;
    // 与完整面板同一条规则：只有这个系列**已经**开了"按系列记住"才写覆盖，
    // 否则改动应该是全局的（否则用户会发现"改了只有这一本生效"）。
    final writeSeriesId = all.hasSeriesOverride(seriesId, serverKey: serverKey)
        ? seriesId
        : null;
    final prefs = all.forSeries(seriesId, serverKey: serverKey);
    final controller = ref.read(readerPrefsProvider.notifier);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    l10n.readerQuickSettings,
                    style: AppTypography.of(context).headline
                        .copyWith(color: palette.foreground),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('quick-settings-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: palette.muted,
                    tooltip: l10n.close,
                  ),
                ],
              ),
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
                      key: const Key('quick-brightness-slider'),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
              // 墨水屏固定白底黑字，不给背景选项，改为提供一键「墨水屏清晰增强」去底灰开关。
              if (!palette.isEink) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                ReaderSectionLabel(l10n.readerBackground, palette: palette),
                _PillChoices<ReaderBackgroundChoice>(
                  values: ReaderBackgroundChoice.values,
                  selected: prefs.background,
                  palette: palette,
                  keyPrefix: 'quick-background',
                  label: readerBackgroundLabel,
                  onSelect: (value) => controller.setBackground(
                    value,
                    seriesId: writeSeriesId,
                    serverKey: serverKey,
                  ),
                ),
              ] else ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  key: const Key('quick-eink-crisp'),
                  contentPadding: EdgeInsets.zero,
                  value:
                      prefs.imageFilter.preset ==
                      ReaderImageFilterPreset.einkCrisp,
                  onChanged: (bool value) => controller.setImageFilter(
                    value
                        ? ReaderImageFilter.einkCrisp
                        : ReaderImageFilter.none,
                    seriesId: writeSeriesId,
                    serverKey: serverKey,
                  ),
                  activeThumbColor: palette.foreground,
                  title: Text(
                    l10n.readerFilterEinkCrisp,
                    style: AppTypography.of(context).body
                        .copyWith(color: palette.foreground),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              ReaderSectionLabel(l10n.readerDirection, palette: palette),
              _PillChoices<ReaderDirectionChoice>(
                values: ReaderDirectionChoice.values,
                selected: prefs.direction,
                palette: palette,
                keyPrefix: 'quick-direction',
                label: readerDirectionLabel,
                onSelect: (value) => controller.setDirection(
                  value,
                  seriesId: writeSeriesId,
                  serverKey: serverKey,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ReaderSectionLabel(l10n.readerFit, palette: palette),
              _PillChoices<ReaderFitChoice>(
                values: ReaderFitChoice.values,
                selected: prefs.fit,
                palette: palette,
                keyPrefix: 'quick-fit',
                label: readerFitLabel,
                onSelect: (value) => controller.setFit(
                  value,
                  seriesId: writeSeriesId,
                  serverKey: serverKey,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                key: const Key('quick-lock-zoom'),
                contentPadding: EdgeInsets.zero,
                value: prefs.lockZoom,
                onChanged: (bool value) => controller.setLockZoom(
                  value,
                  seriesId: writeSeriesId,
                  serverKey: serverKey,
                ),
                activeThumbColor: palette.foreground,
                title: Text(
                  l10n.readerLockZoom,
                  style: AppTypography.of(context).body
                      .copyWith(color: palette.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一排可横滚的紧凑胶囊（单选）。
class _PillChoices<T extends Enum> extends StatelessWidget {
  const _PillChoices({
    required this.values,
    required this.selected,
    required this.palette,
    required this.keyPrefix,
    required this.label,
    required this.onSelect,
  });

  final List<T> values;
  final T selected;
  final ReaderPalette palette;
  final String keyPrefix;
  final String Function(AppLocalizations l10n, T value) label;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = Theme.of(context).textTheme.labelLarge;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: InkWell(
                key: Key('$keyPrefix-${value.name}'),
                onTap: () => onSelect(value),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: value == selected
                        ? palette.foreground.withValues(alpha: 0.18)
                        : Colors.transparent,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: value == selected
                            ? palette.foreground
                            : palette.outline,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      label(l10n, value),
                      style: textStyle?.copyWith(
                        color: value == selected
                            ? palette.foreground
                            : palette.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

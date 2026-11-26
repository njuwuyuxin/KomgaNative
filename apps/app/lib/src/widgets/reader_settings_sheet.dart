import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/widgets/reader_fit_preview.dart';
import 'package:yomu/src/widgets/reader_mode_text.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_preset_section.dart';
import 'package:yomu/src/widgets/reader_settings_color_interaction.dart';
import 'package:yomu/src/widgets/reader_settings_group.dart';
import 'package:yomu/src/widgets/reader_settings_rows.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板：按"页面 / 布局 / 颜色 / 交互"四组排（RDR-04）。
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required String sourceKey,
  required int page,
  required int total,
  String? seriesId,
  required ValueChanged<int> onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
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
          child: ReaderSettingsSheet(
            palette: palette,
            sourceKey: sourceKey,
            page: page,
            total: total,
            seriesId: seriesId,
            onJump: onJump,
          ),
        ),
      ),
    ),
  );
}

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({
    required this.palette,
    required this.sourceKey,
    required this.page,
    required this.total,
    required this.onJump,
    this.seriesId,
    super.key,
  });

  final ReaderPalette palette;
  final String sourceKey;
  final int page;
  final int total;
  final ValueChanged<int> onJump;
  final String? seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final global = ref.watch(readerPrefsProvider);
    final serverKey = sourceKey;
    final controller = ref.read(readerPrefsProvider.notifier);
    final textStyle = Theme.of(context).textTheme;
    final seriesId = this.seriesId;
    final seriesOverridden = global.hasSeriesOverride(
      seriesId,
      serverKey: serverKey,
    );
    final writeSeriesId = seriesOverridden ? seriesId : null;
    final prefs = global.forSeries(seriesId, serverKey: serverKey);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * AppSizes.modalHeightFraction,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 顶部拖拽区放在滚动视图之外，避免 SingleChildScrollView 拦截纵向手势，
            // 从横条/标题区下拉时直接由 BottomSheet 接管并关闭面板。
            ColoredBox(
              key: const Key('reader-settings-drag-handle'),
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        key: const Key('reader-settings-grabber'),
                        width: AppSizes.grabber.width,
                        height: AppSizes.grabber.height,
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: palette.outline,
                          borderRadius: BorderRadius.circular(
                            AppSizes.grabber.height / 2,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      l10n.readingSettings,
                      style: AppTypography.of(context).title
                          .copyWith(color: palette.foreground),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      key: const Key('reader-settings-summary'),
                      '${l10n.readerCurrentSummary} · ${_summary(l10n, prefs, palette)}',
                      style: textStyle.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (seriesId != null) ...<Widget>[
                      ReaderSettingsSwitch(
                        switchKey: const Key('reader-series-remember'),
                        value: seriesOverridden,
                        title: l10n.readerSeriesRemember,
                        hint: l10n.readerSeriesRememberHint,
                        palette: palette,
                        onChanged: (bool value) => controller.setSeriesOverride(
                          seriesId,
                          value,
                          serverKey: serverKey,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    ReaderPresetSection(
                      presets: global.presets,
                      palette: palette,
                      onApply: (String id) => controller.applyPreset(
                        id,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                      onDelete: controller.deletePreset,
                      onSave: (String name) => controller.savePreset(
                        name,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ReaderSettingsGroupHeader(
                      group: 'pages',
                      title: l10n.readerGroupPages,
                      palette: palette,
                      enabled: !prefs.isGroupDefault(ReaderSettingsGroup.pages),
                      onReset: () => controller.resetGroup(
                        ReaderSettingsGroup.pages,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    ReaderOptionSection<ReaderModeChoice>(
                      title: l10n.readingMode,
                      values: ReaderModeChoice.values,
                      selected: prefs.mode,
                      label: readerModeLabel,
                      hint: readerModeHint,
                      keyPrefix: 'reader-mode',
                      palette: palette,
                      onSelect: (ReaderModeChoice value) => controller.setMode(
                        value,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ReaderJumpSlider(
                      page: page,
                      total: total,
                      palette: palette,
                      onJump: onJump,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ReaderSettingsGroupHeader(
                      group: 'layout',
                      title: l10n.readerGroupLayout,
                      palette: palette,
                      enabled: !prefs.isGroupDefault(
                        ReaderSettingsGroup.layout,
                      ),
                      onReset: () => controller.resetGroup(
                        ReaderSettingsGroup.layout,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    ReaderOptionSection<ReaderFitChoice>(
                      title: l10n.readerFit,
                      values: ReaderFitChoice.values,
                      selected: prefs.fit,
                      label: readerFitLabel,
                      hint: readerFitHint,
                      keyPrefix: 'reader-fit',
                      palette: palette,
                      preview: (BuildContext context, ReaderFitChoice value) =>
                          ReaderFitPreview(fit: value, palette: palette),
                      onSelect: (ReaderFitChoice value) => controller.setFit(
                        value,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ReaderOptionSection<ReaderDirectionChoice>(
                      title: l10n.readerDirection,
                      values: ReaderDirectionChoice.values,
                      selected: prefs.direction,
                      label: readerDirectionLabel,
                      hint: readerDirectionHint,
                      keyPrefix: 'reader-direction',
                      palette: palette,
                      onSelect: (ReaderDirectionChoice value) =>
                          controller.setDirection(
                            value,
                            seriesId: writeSeriesId,
                            serverKey: serverKey,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ReaderSettingsSwitch(
                      switchKey: const Key('reader-trim-borders'),
                      value: prefs.trimBorders,
                      title: l10n.readerTrimBorders,
                      hint: l10n.readerTrimBordersHint,
                      palette: palette,
                      onChanged: (bool value) => controller.setTrimBorders(
                        value,
                        seriesId: writeSeriesId,
                        serverKey: serverKey,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ReaderOptionSection<WidePageSplitMode>(
                      title: l10n.readerSplitWidePages,
                      values: WidePageSplitMode.values,
                      selected: prefs.splitWidePages,
                      label: readerSplitWideLabel,
                      hint: readerSplitWideHint,
                      keyPrefix: 'reader-split-wide',
                      palette: palette,
                      onSelect: (WidePageSplitMode value) =>
                          controller.setSplitWidePages(
                            value,
                            seriesId: writeSeriesId,
                            serverKey: serverKey,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ReaderSettingsColorInteraction(
                      prefs: prefs,
                      palette: palette,
                      controller: controller,
                      writeSeriesId: writeSeriesId,
                      serverKey: serverKey,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(
    AppLocalizations l10n,
    ReaderConfig prefs,
    ReaderPalette palette,
  ) {
    return <String>[
      readerModeLabel(l10n, prefs.mode),
      readerFitLabel(l10n, prefs.fit),
      readerDirectionLabel(l10n, prefs.direction),
      if (!palette.isEink) readerBackgroundLabel(l10n, prefs.background),
    ].join(' · ');
  }
}

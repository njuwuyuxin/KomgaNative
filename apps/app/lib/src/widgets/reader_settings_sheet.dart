import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/widgets/reader_fit_preview.dart';
import 'package:komga_native/src/widgets/reader_mode_text.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_preset_section.dart';
import 'package:komga_native/src/widgets/reader_settings_group.dart';
import 'package:komga_native/src/widgets/reader_settings_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板：按"页面 / 布局 / 颜色 / 交互"四组排（RDR-04）。
///
/// 为什么放底部面板而不是顶栏一排图标：这些设置里有"连续值"（亮度、页码），
/// 只有面板放得下；而且它盖住内容的同时还能看到页面在变，调亮度时有参照。
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required int page,
  required int total,
  String? seriesId,
  required ValueChanged<int> onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // 内容可能超过默认的 9/16 高度（小屏、大字号、平板上四个区块），必须可滚动。
    isScrollControlled: true,
    // 面板自己用设计系统的 sheet 材质（毛玻璃 + 顶部圆角；墨水屏退化成纸色 + 描边）。
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext context) => FrostedSurface(
      kind: AppMaterialKind.sheet,
      // 阅读器面板压在漫画上，普通设备固定用深色材质：浅色主题下若跟随
      // Theme.brightness，会得到浅灰底 + 白字（真机上实测不可读）。
      material: AppMaterial.resolve(
        AppMaterialKind.sheet,
        eink: palette.isEink,
        dark: !palette.isEink,
      ),
      shape: AppShapes.sheet(eink: palette.isEink),
      // 透明 Material：面板里的 InkWell / SwitchListTile 要在这里画水波纹，
      // 否则它们会穿到毛玻璃后面（Flutter 会直接断言"水波纹可能看不见"）。
      child: Material(
        type: MaterialType.transparency,
        child: ReaderSettingsSheet(
          palette: palette,
          page: page,
          total: total,
          seriesId: seriesId,
          onJump: onJump,
        ),
      ),
    ),
  );
}

class ReaderSettingsSheet extends ConsumerWidget {
  const ReaderSettingsSheet({
    required this.palette,
    required this.page,
    required this.total,
    required this.onJump,
    this.seriesId,
    super.key,
  });

  final ReaderPalette palette;
  final int page;
  final int total;
  final ValueChanged<int> onJump;

  /// 当前书的系列；为空（深链/书还没回来）时不显示"按系列记住"。
  final String? seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final global = ref.watch(readerPrefsProvider);
    final controller = ref.read(readerPrefsProvider.notifier);
    final palette = this.palette;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme;
    final seriesId = this.seriesId;
    final seriesOverridden =
        seriesId != null && global.seriesOverrides.containsKey(seriesId);
    // 开关关着时改的是全局；开着时才写这个系列的覆盖。
    final writeSeriesId = seriesOverridden ? seriesId : null;
    final prefs = global.forSeries(seriesId);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
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
              // 顶部摘要（RDR-04）：不开面板里的任何一组也知道现在是什么组合。
              Text(
                key: const Key('reader-settings-summary'),
                '${l10n.readerCurrentSummary} · ${_summary(l10n, prefs, palette)}',
                style: textStyle.bodySmall?.copyWith(color: palette.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              if (seriesId != null) ...<Widget>[
                ReaderSettingsSwitch(
                  switchKey: const Key('reader-series-remember'),
                  value: seriesOverridden,
                  title: l10n.readerSeriesRemember,
                  hint: l10n.readerSeriesRememberHint,
                  palette: palette,
                  onChanged: (bool value) =>
                      controller.setSeriesOverride(seriesId, value),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              ReaderPresetSection(
                prefs: prefs,
                palette: palette,
                onApply: (String id) =>
                    controller.applyPreset(id, seriesId: writeSeriesId),
                onDelete: controller.deletePreset,
                onSave: (String name) =>
                    controller.savePreset(name, seriesId: writeSeriesId),
              ),
              const SizedBox(height: AppSpacing.md),
              // ---- 页面：模式 + 跳页 ----
              ReaderSettingsGroupHeader(
                group: 'pages',
                title: l10n.readerGroupPages,
                palette: palette,
                enabled: !prefs.isGroupDefault(ReaderSettingsGroup.pages),
                onReset: () => controller.resetGroup(
                  ReaderSettingsGroup.pages,
                  seriesId: writeSeriesId,
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
                onSelect: (ReaderModeChoice value) =>
                    controller.setMode(value, seriesId: writeSeriesId),
              ),
              const SizedBox(height: AppSpacing.sm),
              ReaderJumpSlider(
                page: page,
                total: total,
                palette: palette,
                onJump: onJump,
              ),
              const SizedBox(height: AppSpacing.md),
              // ---- 布局：适配 + 方向 + 去白边 ----
              ReaderSettingsGroupHeader(
                group: 'layout',
                title: l10n.readerGroupLayout,
                palette: palette,
                enabled: !prefs.isGroupDefault(ReaderSettingsGroup.layout),
                onReset: () => controller.resetGroup(
                  ReaderSettingsGroup.layout,
                  seriesId: writeSeriesId,
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
                onSelect: (ReaderFitChoice value) =>
                    controller.setFit(value, seriesId: writeSeriesId),
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
                    controller.setDirection(value, seriesId: writeSeriesId),
              ),
              const SizedBox(height: AppSpacing.sm),
              ReaderSettingsSwitch(
                switchKey: const Key('reader-trim-borders'),
                value: prefs.trimBorders,
                title: l10n.readerTrimBorders,
                hint: l10n.readerTrimBordersHint,
                palette: palette,
                onChanged: (bool value) =>
                    controller.setTrimBorders(value, seriesId: writeSeriesId),
              ),
              const SizedBox(height: AppSpacing.md),
              // ---- 颜色：背景 + 亮度（墨水屏只有亮度） ----
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
                      onChanged: (double value) => controller.setBrightness(
                        value,
                        seriesId: writeSeriesId,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: AppSizes.valueColumn,
                    child: Text(
                      l10n.brightnessPercent((prefs.brightness * 100).round()),
                      textAlign: TextAlign.end,
                      style: textStyle.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // ---- 交互：锁定缩放 + 常亮 ----
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
          ),
        ),
      ),
    );
  }

  /// 顶部摘要：模式 · 适配 · 方向（+ 非墨水屏时的背景）。
  String _summary(
    AppLocalizations l10n,
    ReaderPrefs prefs,
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

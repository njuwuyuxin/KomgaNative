import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/widgets/reader_mode_text.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_preset_section.dart';
import 'package:komga_native/src/widgets/reader_settings_rows.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读设置面板：模式 / 适配 / 方向 / 背景 / 亮度 / 常亮 / 跳页。
///
/// 为什么放在底部面板而不是顶栏一排图标：这些设置里有"连续值"（亮度、页码），
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

class ReaderSettingsSheet extends ConsumerStatefulWidget {
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
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  /// 拖动中的页码（松手才跳，避免拖动时每帧都改阅读位置）。
  double? _dragging;

  /// 松手后停住的页码。
  ///
  /// 不能在松手时直接丢掉局部状态：`widget.page` 是**打开面板那一刻**的快照，
  /// `onJump` 只会改阅读器、不会重建这个面板。回到 `widget.page` 会让滑条
  /// "弹回原位"，看起来像拖动失败（其实页面已经跳过去了）。
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.page.clamp(1, widget.total < 1 ? 1 : widget.total);
  }

  void _onSlideEnd(double value) {
    final target = value.round().clamp(1, widget.total);
    // 先落本地页码再通知外部：两者顺序反了会有一帧仍显示旧值。
    setState(() {
      _dragging = null;
      _page = target;
    });
    widget.onJump(target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final global = ref.watch(readerPrefsProvider);
    final controller = ref.read(readerPrefsProvider.notifier);
    final palette = widget.palette;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme;
    final seriesId = widget.seriesId;
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
              const SizedBox(height: AppSpacing.md),
              if (seriesId != null) ...<Widget>[
                SwitchListTile(
                  key: const Key('reader-series-remember'),
                  contentPadding: EdgeInsets.zero,
                  value: seriesOverridden,
                  onChanged: (bool value) =>
                      controller.setSeriesOverride(seriesId, value),
                  activeThumbColor: palette.foreground,
                  title: Text(
                    l10n.readerSeriesRemember,
                    style: textStyle.bodyMedium?.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                  subtitle: Text(
                    l10n.readerSeriesRememberHint,
                    style: textStyle.bodySmall?.copyWith(color: palette.muted),
                  ),
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
              const SizedBox(height: AppSpacing.md),
              ReaderOptionSection<ReaderFitChoice>(
                title: l10n.readerFit,
                values: ReaderFitChoice.values,
                selected: prefs.fit,
                label: readerFitLabel,
                hint: readerFitHint,
                keyPrefix: 'reader-fit',
                palette: palette,
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
              // 墨水屏不给背景选项：它固定白底黑字（黑底会触发整屏全刷）。
              if (!palette.isEink) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
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
              ],
              const SizedBox(height: AppSpacing.md),
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
              SwitchListTile(
                key: const Key('reader-keep-awake'),
                contentPadding: EdgeInsets.zero,
                value: prefs.keepAwake,
                onChanged: (bool value) =>
                    controller.setKeepAwake(value, seriesId: writeSeriesId),
                activeThumbColor: palette.foreground,
                title: Text(
                  l10n.keepScreenAwake,
                  style: textStyle.bodyMedium?.copyWith(
                    color: palette.foreground,
                  ),
                ),
                subtitle: Text(
                  l10n.keepScreenAwakeHint,
                  style: textStyle.bodySmall?.copyWith(color: palette.muted),
                ),
              ),
              if (widget.total > 1) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    ReaderSectionLabel(l10n.goToPage, palette: palette),
                    const Spacer(),
                    Text(
                      l10n.readerPageOf(
                        _dragging?.round() ?? _page,
                        widget.total,
                      ),
                      style: textStyle.bodySmall?.copyWith(
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const Key('reader-jump-slider'),
                  value: (_dragging ?? _page.toDouble()).clamp(
                    1,
                    widget.total.toDouble(),
                  ),
                  min: 1,
                  max: widget.total.toDouble(),
                  divisions: widget.total > 1 ? widget.total - 1 : null,
                  activeColor: palette.foreground,
                  inactiveColor: palette.outline,
                  onChanged: (double value) =>
                      setState(() => _dragging = value),
                  onChangeEnd: _onSlideEnd,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
